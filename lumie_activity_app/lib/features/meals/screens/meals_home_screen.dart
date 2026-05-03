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
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';
import '../providers/meal_provider.dart';
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

  Future<void> _openLogMeal() async {
    await Navigator.of(context).pushNamed('/meals/log');
    // Provider already prepended any newly-confirmed meal; trend was invalidated
    // by confirmDraft, so a passive next-visit fetch will refresh it.
    if (mounted) {
      // Touch trend refresh in case the user crossed midnight or logged on
      // another day via a custom meal_time.
      // ignore: use_build_context_synchronously
      context.read<MealProvider>().loadTrend(refresh: true);
    }
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
            return Column(
              children: [
                DateTabStrip(
                  selectedDate: _selectedDate,
                  onDateChanged: (d) {
                    setState(() => _selectedDate = d);
                  },
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
