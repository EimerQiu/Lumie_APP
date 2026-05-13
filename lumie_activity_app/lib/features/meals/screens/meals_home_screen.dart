// MealsHomeScreen — Meals feature main surface.
//
// Layout (top → bottom):
//   • AppBar with "Meals" title
//   • DateTabStrip (Yesterday / Today / picked-date pill / 📅)
//   • Weekly nutrition trend chart (Limited→Nutritious × past 7 days)
//   • "Logged meals" section header
//   • List of MealRowItems for the SELECTED date (filtered locally)
//   • Bottom-pinned "Log a meal" button
//
// Pull-to-refresh refetches both the meal history and the trend.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';
import '../../meals/utils/food_input_split.dart'
    show splitFoodInput, deriveMealNameFromFoods;
import '../providers/meal_provider.dart';
import '../screens/meal_log_screen.dart';
import '../widgets/date_tab_strip.dart';
import '../widgets/meal_row_item.dart';
import '../widgets/weekly_trend_chart.dart';

class MealsHomeScreen extends StatefulWidget {
  const MealsHomeScreen({super.key});

  @override
  State<MealsHomeScreen> createState() => _MealsHomeScreenState();
}

class _MealsHomeScreenState extends State<MealsHomeScreen> {
  late DateTime _selectedDate;
  bool _initialLoadStarted = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = _stripTime(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialLoadStarted && mounted) {
        _initialLoadStarted = true;
        final provider = context.read<MealProvider>();
        if (provider.myMeals.isEmpty) {
          provider.loadMyMeals(refresh: true);
        }
        // Trend always loads on first visit; provider de-dupes if cached.
        provider.loadTrend();
      }
    });
  }

  static DateTime _stripTime(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  List<Meal> _mealsForSelectedDate(List<Meal> all) {
    final target = _selectedDate;
    final filtered = all.where((m) {
      final local = _stripTime(m.effectiveTime.toLocal());
      return local == target;
    }).toList()
      ..sort((a, b) => b.effectiveTime.compareTo(a.effectiveTime));
    return filtered;
  }

  Future<void> _onRefresh() {
    final p = context.read<MealProvider>();
    return Future.wait([
      p.loadMyMeals(refresh: true),
      p.loadTrend(refresh: true),
    ]);
  }

  // ─── Entry sheet ───────────────────────────────────────────────────

  /// Refresh the trend chart and return to the home date after any log flow.
  void _afterLog() {
    if (!mounted) return;
    // Select today so the user immediately sees the meal they just logged.
    setState(() => _selectedDate = _stripTime(DateTime.now()));
    context.read<MealProvider>().loadTrend(refresh: true);
  }

  Future<void> _openLogMeal() => _showEntrySheet();

  /// Show the four-option entry bottom sheet and route to the chosen path.
  Future<void> _showEntrySheet() async {
    final choice = await showModalBottomSheet<_EntryChoice>(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _EntrySheet(),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _EntryChoice.camera:
        await _pushLog(MealLogScreen(autoPickSource: ImageSource.camera));
      case _EntryChoice.library:
        await _pushLog(MealLogScreen(autoPickSource: ImageSource.gallery));
      case _EntryChoice.recentMeals:
        await _showRecentMealsPicker();
      case _EntryChoice.typeInMeal:
        await _showTypeInMealDialog();
    }
  }

  Future<void> _pushLog(MealLogScreen screen) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    _afterLog();
  }

  /// Show a scrollable list of recent unique meals. Tapping one pre-fills
  /// a fresh log session with the same items and runs a background
  /// re-analysis to get up-to-date Nutrition Level / Advisor insight.
  Future<void> _showRecentMealsPicker() async {
    final meals = context.read<MealProvider>().myMeals;
    final recent = _recentUniqueMeals(meals);
    if (recent.isEmpty) {
      // Fall back to the camera if there's no history yet.
      await _pushLog(MealLogScreen(autoPickSource: ImageSource.camera));
      return;
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<Meal>(
      context: context,
      backgroundColor: AppColors.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RecentMealsPicker(meals: recent),
    );
    if (!mounted || selected == null) return;
    await _pushLog(
      MealLogScreen(
        textOnly: true,
        prefillFoodItems: selected.foodItems,
        prefillMealName: selected.mealName ?? selected.displayName,
        prefillMealType: selected.mealType,
      ),
    );
  }

  /// Show a text-input dialog. The typed items are comma-split, then passed
  /// to the log screen which runs the full structuring analysis pipeline
  /// (same as the photo path — no photo required).
  Future<void> _showTypeInMealDialog() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Type your meal',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. Rice, tuna in water, kimchi, seaweed',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLemonDark,
              foregroundColor: Colors.white,
            ),
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
    if (!mounted || input == null || input.isEmpty) return;
    final names = splitFoodInput(input);
    if (names.isEmpty) return;
    final foodItems = names.map((n) => FoodItem(name: n)).toList();
    await _pushLog(
      MealLogScreen(
        textOnly: true,
        prefillFoodItems: foodItems,
        prefillMealName: deriveMealNameFromFoods(names),
      ),
    );
  }

  /// Return the most recently logged unique meals (by display name), newest
  /// first, capped at 10 entries. De-duplication is case-insensitive on the
  /// display name so the same dish logged multiple times shows only once.
  static List<Meal> _recentUniqueMeals(List<Meal> meals) {
    final seen = <String>{};
    final result = <Meal>[];
    for (final meal in meals) {
      final key = meal.displayName.toLowerCase().trim();
      if (seen.add(key)) {
        result.add(meal);
        if (result.length >= 10) break;
      }
    }
    return result;
  }

  Future<void> _openDetail(Meal meal) async {
    await Navigator.of(context)
        .pushNamed('/meals/detail', arguments: meal);
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Meals',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        centerTitle: true,
      ),
      body: SafeArea(
        bottom: false,
        child: Consumer<MealProvider>(
          builder: (context, provider, _) {
            final mealsToday = _mealsForSelectedDate(provider.myMeals);
            final datesWithMeals = provider.myMeals
                .map((m) => _stripTime(m.effectiveTime.toLocal()))
                .toSet();
            return Column(
              children: [
                DateTabStrip(
                  selectedDate: _selectedDate,
                  onDateChanged: (d) => setState(() => _selectedDate = d),
                  datesWithMeals: datesWithMeals,
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: AppColors.primaryLemonDark,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                      children: [
                        _buildTrendCard(provider),
                        _buildSectionHeader('Logged meals'),
                        if (mealsToday.isEmpty)
                          _buildEmptyDay()
                        else
                          ...mealsToday.map(
                            (m) => MealRowItem(
                              meal: m,
                              onTap: () => _openDetail(m),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _buildLogButton(),
    );
  }

  Widget _buildTrendCard(MealProvider provider) {
    final trend = provider.trend;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                const Text(
                  'This week',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                if (provider.isTrendLoading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.primaryLemonDark,
                    ),
                  ),
              ],
            ),
          ),
          if (trend == null && provider.isTrendLoading)
            const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryLemonDark,
                ),
              ),
            )
          else if (trend != null)
            WeeklyTrendChart(days: trend.days)
          else
            const SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  'Pull down to refresh',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildEmptyDay() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.warmGradient,
            ),
            child: const Icon(
              Icons.restaurant_menu,
              color: AppColors.primaryLemonDark,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No meals on this day',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap the button below to add one — '
            "no calories, no judgment.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _openLogMeal,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text(
              'Log a meal',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLemonDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Entry sheet types ────────────────────────────────────────────────────────

enum _EntryChoice { camera, library, recentMeals, typeInMeal }

class _EntrySheet extends StatelessWidget {
  const _EntrySheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Log a meal',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            _EntryTile(
              icon: Icons.camera_alt_outlined,
              label: 'Take Photo',
              onTap: () => Navigator.pop(context, _EntryChoice.camera),
            ),
            _EntryTile(
              icon: Icons.photo_library_outlined,
              label: 'Choose from Library',
              onTap: () => Navigator.pop(context, _EntryChoice.library),
            ),
            _EntryTile(
              icon: Icons.history_outlined,
              label: 'Recent Meals',
              onTap: () => Navigator.pop(context, _EntryChoice.recentMeals),
            ),
            _EntryTile(
              icon: Icons.edit_outlined,
              label: 'Type in Meal',
              onTap: () => Navigator.pop(context, _EntryChoice.typeInMeal),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _EntryTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primaryLemonLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primaryLemonDark, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.textLight,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

// ─── Recent meals picker ──────────────────────────────────────────────────────

class _RecentMealsPicker extends StatelessWidget {
  final List<Meal> meals;

  const _RecentMealsPicker({required this.meals});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${_months[local.month - 1]} ${local.day}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (_, scrollController) => Column(
        children: [
          // Drag handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent meals',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              itemCount: meals.length,
              itemBuilder: (_, i) {
                final meal = meals[i];
                final type = meal.mealType?.displayName ?? 'Meal';
                final date = _formatDate(meal.effectiveTime);
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLemonLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.restaurant_outlined,
                      color: AppColors.primaryLemonDark,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    meal.mealName ?? meal.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '$type · $date',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, meal),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
