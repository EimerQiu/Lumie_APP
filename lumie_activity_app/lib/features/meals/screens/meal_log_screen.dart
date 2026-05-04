// MealLogScreen — single-photo, auto-pick log flow.
//
// Flow:
//   1. Screen mounts → action sheet asks Camera or Library
//   2. User picks ONE photo (multi-image not allowed; cancelling pops the screen)
//   3. Vision analysis runs immediately
//   4. User reviews + edits the result, then taps Save
//
// Per PRD §10: visual-first, no judgment. Default visibility = team when the
// user has any team; falls back to private otherwise.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';
import '../../teams/providers/teams_provider.dart';
import '../providers/meal_provider.dart';
import '../utils/food_input_split.dart';
import '../widgets/drum_time_picker.dart';
import '../widgets/macro_segmented_bar.dart';
import '../widgets/meal_pill_field.dart';
import '../widgets/nutrition_level_slider.dart';
import '../widgets/portion_ratio_bar.dart';

class MealLogScreen extends StatefulWidget {
  const MealLogScreen({super.key});

  @override
  State<MealLogScreen> createState() => _MealLogScreenState();
}

class _MealLogScreenState extends State<MealLogScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _noteController = TextEditingController();

  File? _selectedImage;

  // Editable working copy of the analysis result. Per spec, only foods,
  // portions, meal type/time, and meal name are user-editable on this screen
  // — the macro/level breakdown is read-only and refreshed via re-analysis.
  List<FoodItem> _foodItems = [];
  MacroRatio _macroRatio = const MacroRatio(
    protein: MacroLevel.moderate,
    carbs: MacroLevel.moderate,
    fat: MacroLevel.moderate,
    fiber: MacroLevel.low,
  );
  NutritionLevel _nutritionLevel = NutritionLevel.fair;
  MacroLevel _processingLevel = MacroLevel.moderate;
  MacroLevel _addedSugar = MacroLevel.low;
  String? _advisorInsight;
  String? _mealName;

  // Foods captured at the last successful analysis. Used to drive the
  // Done → Re-analyze button: any food edit (rename/add/remove/portion)
  // since the last analysis flips the label.
  List<FoodItem> _analyzedFoods = const [];

  // Snapshot of the AI's first prediction, captured the moment analysis
  // returns. Used after confirm to detect whether the user edited foods/macros
  // — if so, we fire POST /meals/{id}/correction so the backend's personal-bias
  // learning loop (PRD §6) sees the correction.
  List<FoodItem> _originalAiFoods = const [];
  MacroRatio _originalAiMacros = const MacroRatio(
    protein: MacroLevel.moderate,
    carbs: MacroLevel.moderate,
    fat: MacroLevel.moderate,
    fiber: MacroLevel.low,
  );

  bool _isReanalyzing = false;

  // Default to team sharing when the user has any teams (Lumie social-first
  // default); falls back to private when they're not in any team.
  MealVisibility _visibility = MealVisibility.private;
  String? _selectedTeamId;

  // Slice 7A §4: pre-filled meal type + time, both editable on this screen.
  late MealType _mealType;
  late DateTime _mealTime;

  bool _isAnalyzing = false;
  bool _isConfirming = false;
  bool _hasDraft = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final teams = context.read<TeamsProvider>().teams;
    if (teams.isNotEmpty) {
      _visibility = MealVisibility.team;
      _selectedTeamId = teams.first.teamId;
    }
    // Auto-suggest meal type from current local time (Slice 7A §4).
    _mealTime = DateTime.now();
    _mealType = _suggestMealTypeFromTime(_mealTime);
    // Auto-open the photo picker on entry — the screen exists ONLY to
    // capture/upload one photo and edit the analyzed result.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pickPhoto();
    });
  }

  /// Mirror of the backend's `_derive_meal_type_from_local_dt` so the
  /// auto-prefill matches whatever the server would have picked.
  static MealType _suggestMealTypeFromTime(DateTime dt) {
    final h = dt.hour + dt.minute / 60.0;
    if (h >= 4.0 && h < 10.5) return MealType.breakfast;
    if (h >= 10.5 && h < 14.5) return MealType.lunch;
    if (h >= 17.0 && h < 22.0) return MealType.dinner;
    return MealType.snack;
  }

  static IconData _iconForMealType(MealType t) {
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

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // ─── Phase 1: pick one photo ────────────────────────────────────────

  Future<ImageSource?> _showSourcePicker() {
    return showModalBottomSheet<ImageSource>(
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
                'Add a meal photo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.primaryLemonDark),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primaryLemonDark),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final source = await _showSourcePicker();
    if (!mounted) return;
    if (source == null) {
      // User dismissed the source sheet → abort the entire log flow.
      Navigator.of(context).pop();
      return;
    }
    final XFile? picked;
    try {
      picked = await _imagePicker.pickImage(source: source);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    if (picked == null) {
      // User backed out of camera/library without selecting.
      Navigator.of(context).pop();
      return;
    }
    // Promote out of the closure — Dart's flow analysis can't track
    // non-null promotion of a captured local across a setState callback.
    final imagePath = picked.path;
    setState(() {
      _selectedImage = File(imagePath);
    });
    await _analyze();
  }

  // ─── Phase 2: analyze ───────────────────────────────────────────────

  Future<void> _analyze() async {
    final image = _selectedImage;
    if (image == null) return;
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });
    try {
      final provider = context.read<MealProvider>();
      final result = await provider.analyzeImages([image]);
      setState(() {
        _applyAnalysisResult(result);
        _originalAiFoods = List.of(result.foodItems);
        _originalAiMacros = result.macroRatio;
        _hasDraft = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _applyAnalysisResult(MealAnalyzeResult result) {
    _foodItems = List.of(result.foodItems);
    _analyzedFoods = List.of(result.foodItems);
    _macroRatio = result.macroRatio;
    _nutritionLevel = result.nutritionLevel ?? NutritionLevel.fair;
    _processingLevel = result.processingLevel ?? MacroLevel.moderate;
    _addedSugar = result.addedSugar ?? MacroLevel.low;
    _advisorInsight = result.advisorInsight;
    _mealName = result.mealName;
  }

  /// Re-run the structuring analysis using the user's current food items +
  /// portion weights, without re-uploading the image. Triggered by the
  /// Re-analyze button when the food list has been edited since the last
  /// analysis.
  Future<void> _reanalyze() async {
    if (_isReanalyzing || _isAnalyzing) return;
    setState(() {
      _isReanalyzing = true;
      _errorMessage = null;
    });
    try {
      final provider = context.read<MealProvider>();
      // Submit the current draft as a meal first so update_meal can re-run
      // structuring with the new foods + portion weights — then immediately
      // pull the refreshed analysis back into the local state. We do this
      // pre-confirm by routing through the provider's update flow on the
      // existing draft meal_id.
      final draft = provider.draft;
      if (draft == null) {
        throw Exception('Draft expired. Please reanalyze the photo.');
      }
      // Hand the new foods (with portion hints) back through the structuring
      // layer via the dedicated re-analyze entry point. Re-using analyzeImages
      // would force another vision call; instead we patch through update_meal
      // semantics by going through the dedicated reanalyzeDraft path. Until
      // that exists, fall back to issuing a fresh analyze on the image so the
      // user always sees a refreshed result.
      final result = await provider.reanalyzeDraft(
        foodItems: _foodItems,
      );
      if (!mounted) return;
      setState(() {
        _applyAnalysisResult(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isReanalyzing = false);
    }
  }

  /// True when the food list (names or portion weights) has changed since
  /// the last analysis. Drives the Done → Re-analyze button label.
  bool _hasFoodEdits() {
    if (_foodItems.length != _analyzedFoods.length) return true;
    for (var i = 0; i < _foodItems.length; i++) {
      if (_foodItems[i].name.trim() !=
          _analyzedFoods[i].name.trim()) {
        return true;
      }
      if (_foodItems[i].portionWeight !=
          _analyzedFoods[i].portionWeight) {
        return true;
      }
    }
    return false;
  }

  // ─── Phase 3: edit ──────────────────────────────────────────────────

  Future<void> _editMealType() async {
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
                    fontWeight:
                        t == _mealType ? FontWeight.w700 : FontWeight.w500,
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

  Future<void> _editMealTime() async {
    final initial = _mealTime.toLocal();
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
        );
      });
    }
  }

  Future<void> _editFoodName(int index) async {
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
      // If the user typed a comma-separated list while editing, the extras
      // become new items inserted right after this position so the list
      // grows in the order they typed.
      for (var i = 1; i < pieces.length; i++) {
        next.insert(index + i, FoodItem(name: pieces[i]));
      }
      _foodItems = next;
    });
  }

  Future<void> _addFood() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add food'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. "Salmon, Rice, Cabbage"',
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
    setState(() => _foodItems = [..._foodItems]..removeAt(index));
  }

  void _onPortionsChanged(List<int> weights) {
    if (weights.length != _foodItems.length) return;
    setState(() {
      _foodItems = [
        for (var i = 0; i < _foodItems.length; i++)
          _foodItems[i].copyWith(portionWeight: weights[i]),
      ];
    });
  }

  // ─── Confirm ────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    if (_foodItems.isEmpty) {
      _showSnack('Add at least one food before confirming.');
      return;
    }
    if (_visibility == MealVisibility.team && _selectedTeamId == null) {
      _showSnack('Pick a team to share with, or switch to Private.');
      return;
    }
    setState(() {
      _isConfirming = true;
      _errorMessage = null;
    });
    try {
      final provider = context.read<MealProvider>();
      final created = await provider.confirmDraft(
        foodItems: _foodItems,
        macroRatio: _macroRatio,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        visibility: _visibility,
        teamId: _visibility == MealVisibility.team ? _selectedTeamId : null,
        // Slice 7A §4: meal type + time captured directly on this screen so
        // the saved meal already has the user's chosen values from the start.
        mealType: _mealType,
        mealTime: _mealTime,
        mealName: _mealName,
        nutritionLevel: _nutritionLevel,
        advisorInsight: _advisorInsight,
        processingLevel: _processingLevel,
        addedSugar: _addedSugar,
      );
      // Capture user's edits to the AI prediction so the backend can bias
      // future analyses (PRD §6). Fire-and-forget — failures don't block save.
      if (_predictionWasCorrected()) {
        unawaited(
          provider.submitCorrection(
            mealId: created.mealId,
            originalFoodItems: _originalAiFoods,
            correctedFoodItems: _foodItems,
            originalMacroRatio: _originalAiMacros,
            correctedMacroRatio: _macroRatio,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _predictionWasCorrected() {
    if (!_macroRatiosEqual(_originalAiMacros, _macroRatio)) return true;
    return !_foodNameSetsEqual(_originalAiFoods, _foodItems);
  }

  static bool _macroRatiosEqual(MacroRatio a, MacroRatio b) {
    return a.protein == b.protein &&
        a.carbs == b.carbs &&
        a.fat == b.fat &&
        a.fiber == b.fiber;
  }

  static bool _foodNameSetsEqual(List<FoodItem> a, List<FoodItem> b) {
    if (a.length != b.length) return false;
    final setA = a.map((f) => f.name.trim().toLowerCase()).toSet();
    final setB = b.map((f) => f.name.trim().toLowerCase()).toSet();
    return setA.length == setB.length && setA.containsAll(setB);
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Log Meal',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _selectedImage == null
            ? const _PickerLoadingState()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _buildPhotoHero(),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) _errorBanner(_errorMessage!),
                  if (_isAnalyzing)
                    _buildAnalyzingState()
                  else if (_isReanalyzing)
                    _buildReanalyzingState()
                  else if (_hasDraft) ...[
                    const SizedBox(height: 8),
                    _buildFoodsSection(),
                    const SizedBox(height: 16),
                    _buildPortionSection(),
                    const SizedBox(height: 20),
                    _buildTypeAndTimeSection(),
                    const SizedBox(height: 20),
                    _buildLevelSection(),
                    const SizedBox(height: 12),
                    _buildAdvisorInsightSection(),
                    const SizedBox(height: 20),
                    _buildBreakdownSection(),
                    const SizedBox(height: 20),
                    _buildNoteSection(),
                    const SizedBox(height: 20),
                    _buildVisibilitySection(),
                    const SizedBox(height: 24),
                    _buildConfirmButton(),
                  ],
                ],
              ),
      ),
    );
  }

  // ─── Sections ───────────────────────────────────────────────────────

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildPhotoHero() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.file(_selectedImage!, fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildAnalyzingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.primaryLemonDark),
          const SizedBox(height: 16),
          Text(
            'Reading your plate…',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontFamily: 'Playfair Display',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReanalyzingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.primaryLemonDark),
          const SizedBox(height: 16),
          Text(
            'Re-analyzing your meal…',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontFamily: 'Playfair Display',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('WHAT WE SAW'),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _foodItems.length; i++)
                _buildFoodChip(i, _foodItems[i]),
              const SizedBox(height: 4),
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
        ),
      ],
    );
  }

  Widget _buildFoodChip(int index, FoodItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _editFoodName(index),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLemonLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _removeFood(index),
            icon: const Icon(Icons.close, size: 18, color: AppColors.textLight),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }

  Widget _buildLevelSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('NUTRITION LEVEL'),
        _card(
          child: NutritionLevelSlider(level: _nutritionLevel),
        ),
      ],
    );
  }

  Widget _buildBreakdownSection() {
    final fill = _nutritionLevel.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('NUTRITION BREAKDOWN'),
        _card(
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
        ),
      ],
    );
  }

  Widget _buildPortionSection() {
    if (_foodItems.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('PORTIONS  ·  DRAG TO ADJUST'),
        _card(
          child: PortionRatioBar(
            names: _foodItems.map((f) => f.name).toList(),
            weights:
                _foodItems.map((f) => f.portionWeight).toList(),
            onChanged: _onPortionsChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildAdvisorInsightSection() {
    final text = _advisorInsight?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          height: 1.45,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildTypeAndTimeSection() {
    final localTime = _mealTime.toLocal();
    final hh = localTime.hour.toString().padLeft(2, '0');
    final mm = localTime.minute.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('MEAL TYPE  ·  TIME'),
        Row(
          children: [
            Expanded(
              child: MealPillField(
                label: 'MEAL TYPE',
                value: _mealType.displayName,
                icon: _iconForMealType(_mealType),
                onTap: _editMealType,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MealPillField(
                label: 'TIME',
                value: '$hh:$mm',
                icon: Icons.schedule_outlined,
                onTap: _editMealTime,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('NOTE  ·  OPTIONAL'),
        _card(
          child: TextField(
            controller: _noteController,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: 'How did this meal make you feel?',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildVisibilitySection() {
    final teams = context.watch<TeamsProvider>().teams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('SHARE'),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _visibilityChoice(
                      label: 'Private',
                      selected: _visibility == MealVisibility.private,
                      onTap: () {
                        setState(() {
                          _visibility = MealVisibility.private;
                          _selectedTeamId = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _visibilityChoice(
                      label: 'Share with team',
                      selected: _visibility == MealVisibility.team,
                      onTap: teams.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _visibility = MealVisibility.team;
                                _selectedTeamId ??= teams.first.teamId;
                              });
                            },
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
                        horizontal: 12, vertical: 8),
                  ),
                  items: teams
                      .map((t) => DropdownMenuItem(
                            value: t.teamId,
                            child: Text(t.name),
                          ))
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
        ),
      ],
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

  Widget _buildConfirmButton() {
    final reanalyzeMode = _hasFoodEdits();
    final label = reanalyzeMode ? 'Re-analyze' : 'Save meal';
    final disabled = _isConfirming || _isReanalyzing;
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: disabled
            ? null
            : (reanalyzeMode ? _reanalyze : _confirm),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLemonDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: _isConfirming
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : Text(label),
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AF87171),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brief loading state shown while the picker action sheet is up — keeps the
/// screen from looking empty in the gap between mount and pick.
class _PickerLoadingState extends StatelessWidget {
  const _PickerLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primaryLemonDark),
    );
  }
}
