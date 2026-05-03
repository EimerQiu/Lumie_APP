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
import '../widgets/macro_ratio_widget.dart';

class MealLogScreen extends StatefulWidget {
  const MealLogScreen({super.key});

  @override
  State<MealLogScreen> createState() => _MealLogScreenState();
}

class _MealLogScreenState extends State<MealLogScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _noteController = TextEditingController();

  File? _selectedImage;

  // Editable working copy of the analysis result.
  List<FoodItem> _foodItems = [];
  MacroRatio _macroRatio = const MacroRatio(
    protein: MacroLevel.moderate,
    carbs: MacroLevel.moderate,
    fat: MacroLevel.moderate,
    fiber: MacroLevel.low,
  );

  // Snapshot of the AI's original prediction, captured the moment analysis
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

  // Default to team sharing when the user has any teams (Lumie social-first
  // default); falls back to private when they're not in any team.
  MealVisibility _visibility = MealVisibility.private;
  String? _selectedTeamId;

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
    // Auto-open the photo picker on entry — the screen exists ONLY to
    // capture/upload one photo and edit the analyzed result.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pickPhoto();
    });
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
        _foodItems = List.of(result.foodItems);
        _macroRatio = result.macroRatio;
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

  // ─── Phase 3: edit ──────────────────────────────────────────────────

  Future<void> _editFoodName(int index) async {
    final controller = TextEditingController(text: _foodItems[index].name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit food'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Food name'),
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
      setState(() {
        _foodItems[index] = _foodItems[index].copyWith(name: result);
      });
    }
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
          decoration: const InputDecoration(hintText: 'e.g. Steamed broccoli'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        _foodItems = [..._foodItems, FoodItem(name: result, macroRatio: _macroRatio)];
      });
    }
  }

  void _removeFood(int index) {
    setState(() => _foodItems = [..._foodItems]..removeAt(index));
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
                  else if (_hasDraft) ...[
                    const SizedBox(height: 8),
                    _buildFoodsSection(),
                    const SizedBox(height: 20),
                    _buildMacroSection(),
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

  Widget _buildMacroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('COMPOSITION  ·  TAP TO ADJUST'),
        _card(
          child: MacroRatioEditor(
            ratio: _macroRatio,
            onChanged: (r) => setState(() => _macroRatio = r),
          ),
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
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isConfirming ? null : _confirm,
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
            : const Text('Save meal'),
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
