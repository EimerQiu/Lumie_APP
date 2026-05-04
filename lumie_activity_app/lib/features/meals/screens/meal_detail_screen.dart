// MealDetailScreen — full meal view with always-on inline editing.
//
// Sections (top → bottom):
//   1. AppBar with back arrow + delete (owner only)
//   2. Meal photo
//   3. Meal name (tap to rename)
//   4. Advisor insight paragraph
//   5. NUTRITION LEVEL header + slider
//   6. "Dive in with Advisor" button
//   7. Meal Type / Time row (two tappable pills)
//   8. Meal Items list (chips with X, +Add)
//   9. Done button (saves and pops; owner-only)
//  10. NUTRITION BREAKDOWN — exactly 4 macros
//  11. Sharing (visibility) — owner-only
//
// Non-owners see a fully read-only view (no edit affordances, no Done).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';
import '../../advisor/screens/advisor_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../teams/providers/teams_provider.dart';
import '../providers/meal_provider.dart';
import '../utils/food_input_split.dart';
import '../widgets/drum_time_picker.dart';
import '../widgets/macro_segmented_bar.dart';
import '../widgets/meal_card.dart' show mealImageUrl;
import '../widgets/meal_pill_field.dart';
import '../widgets/nutrition_level_slider.dart';
import '../widgets/portion_ratio_bar.dart';

class MealDetailScreen extends StatefulWidget {
  final String mealId;
  final Meal? initialMeal;

  const MealDetailScreen({super.key, required this.mealId, this.initialMeal});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  Meal? _meal;
  bool _isLoading = false;
  bool _saving = false;
  String? _error;

  // Local editable copy
  late List<FoodItem> _foodItems;
  late MacroRatio _macroRatio;
  late MealVisibility _visibility;
  String? _selectedTeamId;
  String? _mealName;
  MealType? _mealType;
  DateTime? _mealTime;
  late MacroLevel _processingLevel;
  late MacroLevel _addedSugar;

  // Snapshot for correction-tracking
  late List<FoodItem> _originalFoods;
  late MacroRatio _originalMacros;

  @override
  void initState() {
    super.initState();
    _meal = widget.initialMeal;
    _resetFromMeal();
    if (_meal == null) {
      _load();
    }
  }

  void _resetFromMeal() {
    final m = _meal;
    final defaultRatio = const MacroRatio(
      protein: MacroLevel.moderate,
      carbs: MacroLevel.moderate,
      fat: MacroLevel.moderate,
      fiber: MacroLevel.low,
    );
    _foodItems = m == null ? <FoodItem>[] : List.of(m.foodItems);
    _macroRatio = m?.macroRatio ?? defaultRatio;
    _originalFoods = m == null ? const [] : List.of(m.foodItems);
    _originalMacros = m?.macroRatio ?? defaultRatio;
    _visibility = m?.visibility ?? MealVisibility.private;
    _selectedTeamId = m?.teamId;
    _mealName = m?.mealName ?? m?.displayName;
    _mealType = m?.mealType;
    _mealTime = m?.mealTime ?? m?.createdAt;
    // Slice 7C: processing_level / added_sugar with neutral baselines for
    // legacy meals that pre-date the fields.
    _processingLevel = m?.processingLevel ?? MacroLevel.moderate;
    _addedSugar = m?.addedSugar ?? MacroLevel.low;
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final fresh = await context.read<MealProvider>().reloadMeal(
        widget.mealId,
      );
      setState(() => _meal = fresh);
      _resetFromMeal();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isOwner {
    final meal = _meal;
    if (meal == null) return false;
    final myId = context.read<AuthProvider>().user?.userId;
    return myId != null && myId == meal.userId;
  }

  // ─── Dirty check + save ─────────────────────────────────────────────

  bool _isDirty() {
    final m = _meal;
    if (m == null) return false;
    if (_visibility != m.visibility) return true;
    if (_selectedTeamId != m.teamId) return true;
    if ((_mealName ?? '') != (m.mealName ?? m.displayName)) return true;
    if (_mealType != m.mealType) return true;
    if (_mealTime != (m.mealTime ?? m.createdAt)) return true;
    if (!_macroRatiosEqual(_macroRatio, m.macroRatio)) return true;
    if (!_foodItemsEqual(_foodItems, m.foodItems)) return true;
    if (_processingLevel != (m.processingLevel ?? MacroLevel.moderate))
      return true;
    if (_addedSugar != (m.addedSugar ?? MacroLevel.low)) return true;
    return false;
  }

  bool _foodWasCorrected() {
    if (!_macroRatiosEqual(_originalMacros, _macroRatio)) return true;
    return !_foodNameSetsEqual(_originalFoods, _foodItems);
  }

  /// Whether the user has edited any food item since the last load / re-analyze.
  /// When true, the bottom button flips from "Done" to "Re-analyze".
  ///
  /// Positional + trim-only comparison so the smallest possible edit flips
  /// the button: a single rename, deletion, addition, or reorder all count.
  /// Trim is applied so trailing whitespace from a dialog field doesn't trick
  /// the user into thinking they edited when they didn't, but case differences
  /// still count (a deliberate retype is a real edit).
  bool _hasFoodEdits() {
    final m = _meal;
    if (m == null) return false;
    if (_foodItems.length != m.foodItems.length) return true;
    for (var i = 0; i < _foodItems.length; i++) {
      if (_foodItems[i].name.trim() != m.foodItems[i].name.trim()) {
        return true;
      }
      // Portion-bar drags also flip Done → Re-analyze, so the backend
      // re-runs structuring with the new portion weights and refreshes the
      // macro/level fields accordingly.
      if (_foodItems[i].portionWeight != m.foodItems[i].portionWeight) {
        return true;
      }
    }
    return false;
  }

  Future<void> _onDone() async {
    if (!_isOwner || _saving) return;
    final reanalyzeMode = _hasFoodEdits();

    if (!reanalyzeMode && !_isDirty()) {
      Navigator.of(context).pop(false);
      return;
    }
    if (_visibility == MealVisibility.team && _selectedTeamId == null) {
      _snack('Pick a team to share with, or switch to Private.');
      return;
    }
    setState(() => _saving = true);
    try {
      final provider = context.read<MealProvider>();

      // In re-analyze mode we deliberately do NOT send macro_ratio /
      // processing_level / added_sugar / nutrition_level / advisor_insight —
      // the backend's update_meal will detect the food_items change, run
      // _structure_text_to_meal against the new list, and re-derive every
      // one of those fields from the corrected foods.
      final updated = await provider.updateMeal(
        mealId: widget.mealId,
        foodItems: _foodItems,
        macroRatio: reanalyzeMode ? null : _macroRatio,
        mealName: _mealName?.trim().isNotEmpty == true
            ? _mealName!.trim()
            : null,
        mealType: _mealType,
        mealTime: _mealTime,
        visibility: _visibility,
        sendTeamId: true,
        teamId: _visibility == MealVisibility.team ? _selectedTeamId : null,
        processingLevel: reanalyzeMode ? null : _processingLevel,
        addedSugar: reanalyzeMode ? null : _addedSugar,
      );
      if (_foodWasCorrected()) {
        unawaited(
          provider.submitCorrection(
            mealId: widget.mealId,
            originalFoodItems: _originalFoods,
            correctedFoodItems: updated.foodItems,
            originalMacroRatio: _originalMacros,
            correctedMacroRatio: updated.macroRatio,
          ),
        );
      }

      if (!mounted) return;
      if (reanalyzeMode) {
        // Stay on the screen and refresh local state from the re-analysed
        // meal so the macro bars, level slider, advisor insight, and tier
        // colour all update in place. The button flips back to "Done"
        // automatically because _foodNameSetsEqual(_foodItems, _meal.foodItems)
        // is now true.
        setState(() {
          _meal = updated;
        });
        _resetFromMeal();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final provider = context.read<MealProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this meal?'),
        content: const Text(
          'This removes the meal and its photos. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await provider.deleteMeal(widget.mealId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ─── Inline edit dialogs ────────────────────────────────────────────

  Future<void> _editMealName() async {
    if (!_isOwner) return;
    final controller = TextEditingController(text: _mealName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename meal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'e.g. Salmon Bowl'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _mealName = result);
    }
  }

  Future<void> _editMealType() async {
    if (!_isOwner) return;
    final picked = await showModalBottomSheet<MealType>(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Meal type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final t in MealType.values)
              ListTile(
                leading: Icon(
                  _iconForMealType(t),
                  color: t == _mealType
                      ? AppColors.primaryLemonDark
                      : AppColors.textSecondary,
                ),
                title: Text(
                  t.displayName,
                  style: TextStyle(
                    fontWeight: t == _mealType
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: t == _mealType
                        ? AppColors.textOnYellow
                        : AppColors.textPrimary,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, t),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _mealType = picked);
  }

  IconData _iconForMealType(MealType t) {
    switch (t) {
      case MealType.breakfast:
        return Icons.wb_sunny_outlined;
      case MealType.lunch:
        return Icons.restaurant_outlined;
      case MealType.dinner:
        return Icons.dinner_dining_outlined;
      case MealType.snack:
        return Icons.cookie_outlined;
    }
  }

  Future<void> _editMealTime() async {
    if (!_isOwner) return;
    final initial = (_mealTime ?? DateTime.now()).toLocal();
    final picked = await showDrumTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked != null) {
      setState(() {
        _mealTime = DateTime(
          initial.year,
          initial.month,
          initial.day,
          picked.hour,
          picked.minute,
        ).toUtc();
      });
    }
  }

  Future<void> _editFoodName(int index) async {
    if (!_isOwner) return;
    final controller = TextEditingController(text: _foodItems[index].name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit food'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Food name (commas split into separate items)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final pieces = splitFoodInput(result);
    if (pieces.isEmpty) return;
    setState(() {
      final next = [..._foodItems];
      next[index] = next[index].copyWith(name: pieces.first);
      for (var i = 1; i < pieces.length; i++) {
        next.insert(index + i, FoodItem(name: pieces[i]));
      }
      _foodItems = next;
    });
  }

  Future<void> _addFood() async {
    if (!_isOwner) return;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add food'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. "Greek yoghurt, Berries, Granola"',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final pieces = splitFoodInput(result);
    if (pieces.isEmpty) return;
    setState(() {
      _foodItems = [
        ..._foodItems,
        for (final name in pieces) FoodItem(name: name),
      ];
    });
  }

  void _removeFood(int index) {
    if (!_isOwner) return;
    setState(() => _foodItems = [..._foodItems]..removeAt(index));
  }

  void _onPortionsChanged(List<int> weights) {
    if (!_isOwner) return;
    if (weights.length != _foodItems.length) return;
    setState(() {
      _foodItems = [
        for (var i = 0; i < _foodItems.length; i++)
          _foodItems[i].copyWith(portionWeight: weights[i]),
      ];
    });
  }

  void _openDiveInWithAdvisor() {
    final meal = _meal;
    if (meal == null) return;
    final seed = _buildAdvisorSeed(meal);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdvisorScreen(initialMessage: seed)),
    );
  }

  /// Build the Advisor seed message — a friendly, structured first turn that
  /// gives Advisor everything it needs about this meal so the user doesn't
  /// have to re-explain it. Uses categorical macros only (low/mod/high) and
  /// the Limited→Nutritious tier; never includes grams or calories.
  String _buildAdvisorSeed(Meal meal) {
    final name = (_mealName?.trim().isNotEmpty == true)
        ? _mealName!.trim()
        : meal.displayName;

    final type = _mealType?.displayName ?? meal.mealType?.displayName;
    final time = (_mealTime ?? meal.mealTime ?? meal.createdAt).toLocal();
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final whenLine = type != null ? '$type at $hh:$mm' : 'Eaten at $hh:$mm';

    final foods = _foodItems.isNotEmpty ? _foodItems : meal.foodItems;
    final foodList = foods.isEmpty
        ? '(no items detected)'
        : foods.map((f) => '• ${f.name}').join('\n');

    final macros = _macroRatio;
    final levelLabel = meal.nutritionLevel?.displayName ?? 'unrated';

    final buffer = StringBuffer()
      ..writeln("Hi! I just logged a meal — let's dive in.")
      ..writeln()
      ..writeln('**$name**')
      ..writeln(whenLine)
      ..writeln()
      ..writeln('What I had:')
      ..writeln(foodList)
      ..writeln()
      ..writeln('Nutrition Breakdown:')
      ..writeln('• Protein — ${macros.protein.displayName}')
      ..writeln('• Carbs — ${macros.carbs.displayName}')
      ..writeln('• Fat — ${macros.fat.displayName}')
      ..writeln('• Fiber — ${macros.fiber.displayName}')
      ..writeln('Overall level: $levelLabel.')
      ..writeln()
      ..write('What does this meal give me, and how does it fit my day?');

    return buffer.toString();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final meal = _meal;
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Meal',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        centerTitle: true,
        actions: [
          if (meal != null && _isOwner)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: AppColors.error,
                      ),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(meal)),
    );
  }

  Widget _buildBody(Meal? meal) {
    if (_isLoading && meal == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLemonDark),
      );
    }
    if (_error != null && meal == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }
    if (meal == null) {
      return const Center(child: Text('Meal not found'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      children: [
        _buildPhoto(meal),
        const SizedBox(height: 16),
        _buildNameAndInsight(meal),
        const SizedBox(height: 20),
        _buildSectionHeader('NUTRITION LEVEL'),
        _buildLevelCard(meal),
        const SizedBox(height: 12),
        _buildDiveInButton(),
        const SizedBox(height: 24),
        _buildTypeAndTimeRow(),
        const SizedBox(height: 20),
        _buildSectionHeader('MEAL ITEMS'),
        _buildItemsCard(),
        if (_foodItems.length > 1) ...[
          const SizedBox(height: 16),
          _buildPortionBarSection(),
        ],
        if (_isOwner) ...[const SizedBox(height: 24), _buildDoneButton()],
        const SizedBox(height: 32),
        _buildSectionHeader('NUTRITION BREAKDOWN'),
        _buildBreakdownCard(),
        if (_isOwner) ...[
          const SizedBox(height: 24),
          _buildSectionHeader('SHARING'),
          _buildSharingCard(),
        ],
      ],
    );
  }

  // ─── Photo ──────────────────────────────────────────────────────────

  Widget _buildPhoto(Meal meal) {
    if (meal.images.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primaryLemonLight,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.restaurant,
              color: AppColors.primaryLemonDark,
              size: 48,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: PageView.builder(
            itemCount: meal.images.length,
            itemBuilder: (context, i) {
              final url = mealImageUrl(meal.images[i].url);
              return Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: AppColors.primaryLemonLight,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                      color: AppColors.primaryLemonDark,
                      strokeWidth: 2.5,
                    ),
                  );
                },
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.primaryLemonLight,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.primaryLemonDark,
                    size: 32,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Name + insight ─────────────────────────────────────────────────

  Widget _buildNameAndInsight(Meal meal) {
    final name = _mealName?.trim().isNotEmpty == true
        ? _mealName!
        : meal.displayName;
    final insight = (meal.advisorInsight ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _isOwner ? _editMealName : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.15,
                        fontFamily: 'Playfair Display',
                      ),
                    ),
                  ),
                  if (_isOwner) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppColors.textLight,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (insight.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              insight,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.45,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Section header + cards ─────────────────────────────────────────

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }

  Widget _buildLevelCard(Meal meal) {
    final level = meal.nutritionLevel ?? NutritionLevel.fair;
    return _card(child: NutritionLevelSlider(level: level));
  }

  Widget _buildDiveInButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _openDiveInWithAdvisor,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text(
            'Dive in with Advisor',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accentOrange,
            side: const BorderSide(
              color: AppColors.primaryLemonDark,
              width: 1.4,
            ),
            backgroundColor: AppColors.primaryLemonLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Type / time row ────────────────────────────────────────────────

  Widget _buildTypeAndTimeRow() {
    final type = _mealType ?? MealType.snack;
    final time = (_mealTime ?? DateTime.now()).toLocal();
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: MealPillField(
              label: 'MEAL TYPE',
              value: type.displayName,
              icon: _iconForMealType(type),
              onTap: _isOwner ? _editMealType : null,
              enabled: _isOwner,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MealPillField(
              label: 'TIME',
              value: '$hh:$mm',
              icon: Icons.schedule_outlined,
              onTap: _isOwner ? _editMealTime : null,
              enabled: _isOwner,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Items card ────────────────────────────────────────────────────

  Widget _buildItemsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_foodItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No items detected.',
                style: TextStyle(fontSize: 13, color: AppColors.textLight),
              ),
            )
          else
            for (var i = 0; i < _foodItems.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _isOwner ? () => _editFoodName(i) : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLemonLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _foodItems[i].name,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_isOwner)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeFood(i),
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.textLight,
                        ),
                        tooltip: 'Remove',
                      ),
                  ],
                ),
              ),
          if (_isOwner)
            TextButton.icon(
              onPressed: _addFood,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a food'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentOrange,
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
            ),
        ],
      ),
    );
  }

  // ─── Done button ────────────────────────────────────────────────────

  Widget _buildDoneButton() {
    // Re-analyze mode: when the user has edited any food item, the button
    // changes label so it's clear tapping it re-runs the structuring layer.
    final reanalyzeMode = _hasFoodEdits();
    final label = reanalyzeMode ? 'Re-analyze' : 'Done';
    final loadingLabel = reanalyzeMode ? 'Re-analyzing your meal…' : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _saving ? null : _onDone,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryLemonDark,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _saving
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                    if (loadingLabel != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        loadingLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  // ─── Nutrition breakdown ────────────────────────────────────────────

  Widget _buildBreakdownCard() {
    // All six rows share the meal's nutrition-level colour so the card visually
    // aligns with the overall tier (vivid gold = Nutritious, calm grey-beige
    // = Limited). Bars are READ-ONLY — the only way to change them is to edit
    // foods or portions and tap Re-analyze.
    final fill = (_meal?.nutritionLevel ?? NutritionLevel.fair).color;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MacroSegmentedBar(
            label: 'Protein',
            level: _macroRatio.protein,
            fillColor: fill,
          ),
          const SizedBox(height: 16),
          MacroSegmentedBar(
            label: 'Carbs',
            level: _macroRatio.carbs,
            fillColor: fill,
          ),
          const SizedBox(height: 16),
          MacroSegmentedBar(
            label: 'Fat',
            level: _macroRatio.fat,
            fillColor: fill,
          ),
          const SizedBox(height: 16),
          MacroSegmentedBar(
            label: 'Fiber',
            level: _macroRatio.fiber,
            fillColor: fill,
          ),
          const SizedBox(height: 16),
          MacroSegmentedBar(
            label: 'Processing Level',
            level: _processingLevel,
            fillColor: fill,
          ),
          const SizedBox(height: 16),
          MacroSegmentedBar(
            label: 'Added Sugar',
            level: _addedSugar,
            fillColor: fill,
          ),
        ],
      ),
    );
  }

  Widget _buildPortionBarSection() {
    if (_foodItems.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'PORTIONS  ·  DRAG TO ADJUST',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.cardShadow,
            ),
            child: PortionRatioBar(
              names: _foodItems.map((f) => f.name).toList(),
              weights: _foodItems.map((f) => f.portionWeight).toList(),
              onChanged: _isOwner ? _onPortionsChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Sharing card (owner-only) ──────────────────────────────────────

  Widget _buildSharingCard() {
    final teams = context.watch<TeamsProvider>().teams;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _visibilityChoice(
                  label: 'Private',
                  selected: _visibility == MealVisibility.private,
                  onTap: () => setState(() {
                    _visibility = MealVisibility.private;
                    _selectedTeamId = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _visibilityChoice(
                  label: 'Share with team',
                  selected: _visibility == MealVisibility.team,
                  onTap: teams.isEmpty
                      ? null
                      : () => setState(() {
                          _visibility = MealVisibility.team;
                          _selectedTeamId ??= teams.first.teamId;
                        }),
                ),
              ),
            ],
          ),
          if (_visibility == MealVisibility.team && teams.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedTeamId,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: teams
                  .map(
                    (t) =>
                        DropdownMenuItem(value: t.teamId, child: Text(t.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedTeamId = v),
            ),
          ],
          if (teams.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Join a team to share meals with others.',
                style: TextStyle(fontSize: 12, color: AppColors.textLight),
              ),
            ),
        ],
      ),
    );
  }

  Widget _visibilityChoice({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLemon : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primaryLemonDark
                : AppColors.surfaceLight,
            width: 1.2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: disabled
                  ? AppColors.textLight
                  : (selected
                        ? AppColors.textOnYellow
                        : AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Equality helpers (correction tracking) ─────────────────────────

  static bool _macroRatiosEqual(MacroRatio a, MacroRatio b) {
    return a.protein == b.protein &&
        a.carbs == b.carbs &&
        a.fat == b.fat &&
        a.fiber == b.fiber;
  }

  static bool _foodItemsEqual(List<FoodItem> a, List<FoodItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name) return false;
    }
    return true;
  }

  static bool _foodNameSetsEqual(List<FoodItem> a, List<FoodItem> b) {
    if (a.length != b.length) return false;
    final setA = a.map((f) => f.name.trim().toLowerCase()).toSet();
    final setB = b.map((f) => f.name.trim().toLowerCase()).toSet();
    return setA.length == setB.length && setA.containsAll(setB);
  }
}

// _PillField was extracted to widgets/meal_pill_field.dart so the Log Meal
// screen and Detail screen share a single source of truth.
