import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/workout_service.dart';
import '../../../core/services/workout_prefs_service.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../providers/workout_template_provider.dart';
import 'exercise_library_screen.dart';

/// Screen for building / editing a single workout template.
/// Set types (straight / superset / circuit) are auto-detected based on the
/// number of exercises in each block — no manual selection needed.
class TemplateBuilderScreen extends StatefulWidget {
  final String templateId;

  const TemplateBuilderScreen({super.key, required this.templateId});

  @override
  State<TemplateBuilderScreen> createState() => _TemplateBuilderScreenState();
}

class _TemplateBuilderScreenState extends State<TemplateBuilderScreen> {
  WorkoutTemplate? _template;
  bool _loading = true;
  bool _saving = false;
  String _weightUnit = 'lbs';
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTemplate();
    _loadWeightUnit();
  }

  Future<void> _loadWeightUnit() async {
    final unit = await WorkoutPrefsService.getWeightUnit();
    if (mounted) setState(() => _weightUnit = unit);
  }

  Future<void> _loadTemplate() async {
    final provider = context.read<WorkoutTemplateProvider>();
    final t = provider.getTemplateById(widget.templateId);
    if (t != null) {
      setState(() {
        _template = t;
        _nameController.text = t.name;
        _loading = false;
      });
    } else {
      try {
        final fetched =
            await WorkoutApiService().getTemplate(widget.templateId);
        // ignore: use_build_context_synchronously
        setState(() {
          _template = fetched;
          _nameController.text = fetched.name;
          _loading = false;
        });
      } catch (e) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primaryLemon)),
      );
    }

    if (_template == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: const Center(child: Text('Template not found')),
      );
    }

    final template = _template!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Edit Workout',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _saving ? null : _save,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
            onSelected: (v) {
              if (v == 'delete') _confirmDeleteTemplate();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child:
                    Text('Delete Template', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Name field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _nameController,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Workout name',
                border: InputBorder.none,
                suffixIcon:
                    Text(template.emoji, style: const TextStyle(fontSize: 24)),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
              ),
            ),
          ),
          // Blocks and exercises
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: template.blocks.length,
              itemBuilder: (ctx, blockIdx) {
                final block = template.blocks[blockIdx];
                return _buildBlockSection(block, blockIdx);
              },
            ),
          ),
        ],
      ),
      // Bottom action bar
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Exercise'),
                onPressed: () => _addExercise(
                    template.blocks.isEmpty ? -1 : template.blocks.length - 1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.surfaceLight),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Block'),
                onPressed: _addBlock,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.surfaceLight),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Block section builder ─────────────────────────────────────────────────

  Widget _buildBlockSection(WorkoutBlock block, int blockIdx) {
    final label = block.setTypeLabel;
    final groupColor = _blockColor(blockIdx);
    final isMulti = block.exercises.length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Block header
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _renameBlockDialog(blockIdx),
                  child: Row(
                    children: [
                      Text(
                        block.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (label != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: groupColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border:
                                Border.all(color: groupColor.withAlpha(80)),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: groupColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: AppColors.textLight),
                onPressed: () => _deleteBlock(blockIdx),
              ),
            ],
          ),
        ),

        // Block-level rest settings (only for multi-exercise blocks)
        if (isMulti)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BlockRestSettings(
              restBetweenExercises: block.restBetweenExercises,
              restBetweenRounds:
                  block.exercises.length >= 3 ? block.restBetweenRounds : null,
              showRoundRest: block.exercises.length >= 3,
              onRestBetweenExercisesChanged: (v) {
                setState(() => block.restBetweenExercises = v);
              },
              onRestBetweenRoundsChanged: (v) {
                setState(() => block.restBetweenRounds = v);
              },
            ),
          ),

        // Exercise rows with optional vertical connecting line
        ...block.exercises.asMap().entries.map((entry) {
          final exIdx = entry.key;
          final ex = entry.value;
          final isLast = exIdx == block.exercises.length - 1;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Vertical connecting line for multi-exercise blocks
                if (isMulti)
                  SizedBox(
                    width: 20,
                    child: Column(
                      children: [
                        // Top half of line (not for first exercise)
                        Expanded(
                          child: Container(
                            width: 3,
                            color: exIdx == 0
                                ? Colors.transparent
                                : groupColor.withAlpha(80),
                          ),
                        ),
                        // Dot
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: groupColor,
                          ),
                        ),
                        // Bottom half of line (not for last exercise)
                        Expanded(
                          child: Container(
                            width: 3,
                            color: isLast
                                ? Colors.transparent
                                : groupColor.withAlpha(80),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Exercise card
                Expanded(
                  child: _ExerciseRowWidget(
                    exercise: ex,
                    weightUnit: _weightUnit,
                    onEditDefaults: () =>
                        _editExerciseDefaults(blockIdx, exIdx),
                    onRemove: () => _removeExercise(blockIdx, exIdx),
                  ),
                ),
              ],
            ),
          );
        }),

        // Add exercise to this block button
        Padding(
          padding: EdgeInsets.only(left: isMulti ? 20.0 : 0),
          child: GestureDetector(
            onTap: () => _addExercise(blockIdx),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.surfaceLight,
                    style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 16, color: AppColors.textLight),
                  const SizedBox(width: 4),
                  Text('Add Exercise',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textLight)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _blockColor(int blockIdx) {
    const colors = [
      Colors.blue,
      Colors.purple,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
    ];
    return colors[blockIdx % colors.length];
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  void _addBlock() {
    setState(() {
      final idx = _template!.blocks.length;
      _template!.blocks.add(WorkoutBlock(
        blockId: 'block_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Block ${String.fromCharCode(65 + idx)}',
        order: idx,
      ));
    });
  }

  void _renameBlockDialog(int blockIdx) async {
    final block = _template!.blocks[blockIdx];
    final controller = TextEditingController(text: block.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Block'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Block name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => _template!.blocks[blockIdx].name = name);
    }
  }

  void _deleteBlock(int blockIdx) {
    final block = _template!.blocks[blockIdx];
    if (block.exercises.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Block?'),
          content: Text(
              '${block.name} has ${block.exercises.length} exercises. This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _template!.blocks.removeAt(blockIdx));
              },
              child:
                  const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      setState(() => _template!.blocks.removeAt(blockIdx));
    }
  }

  Future<void> _addExercise(int blockIdx) async {
    if (_template!.blocks.isEmpty) _addBlock();
    final targetBlock =
        blockIdx < 0 ? _template!.blocks.length - 1 : blockIdx;

    final exercise = await Navigator.push<ExerciseDefinition>(
      context,
      MaterialPageRoute(
        builder: (_) => const ExerciseLibraryScreen(pickerMode: true),
      ),
    );
    if (exercise == null || !mounted) return;

    setState(() {
      _template!.blocks[targetBlock].exercises.add(TemplateExercise(
        exerciseId: exercise.exerciseId,
        exerciseName: exercise.name,
        equipmentType: exercise.equipmentType.name,
        poseType: exercise.poseType,
        order: _template!.blocks[targetBlock].exercises.length,
      ));
    });
  }

  void _removeExercise(int blockIdx, int exIdx) {
    setState(() => _template!.blocks[blockIdx].exercises.removeAt(exIdx));
  }

  void _editExerciseDefaults(int blockIdx, int exIdx) {
    final ex = _template!.blocks[blockIdx].exercises[exIdx];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseDefaultsSheet(
        exercise: ex,
        weightUnit: _weightUnit,
        onSave: (updated) {
          setState(() =>
              _template!.blocks[blockIdx].exercises[exIdx] = updated);
        },
      ),
    );
  }

  /// Normalize set types from block structure before saving.
  void _normalizeSetTypes() {
    for (final block in _template!.blocks) {
      final autoType = block.autoSetType;
      final groupId =
          block.exercises.length >= 2 ? block.blockId : null;
      for (final ex in block.exercises) {
        ex.setType = autoType;
        ex.groupId = groupId;
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final template = _template!;
    template.name = _nameController.text.trim().isEmpty
        ? 'Untitled Workout'
        : _nameController.text.trim();

    _normalizeSetTypes();

    try {
      await context.read<WorkoutTemplateProvider>().updateTemplate(
            template.templateId,
            template.toJson(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
    setState(() => _saving = false);
  }

  void _confirmDeleteTemplate() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template?'),
        content: Text(
            'Are you sure you want to delete "${_template!.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final deleted = await context
                  .read<WorkoutTemplateProvider>()
                  .deleteTemplate(_template!.templateId);
              if (deleted && mounted) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Block rest settings ─────────────────────────────────────────────────────

class _BlockRestSettings extends StatelessWidget {
  final int? restBetweenExercises;
  final int? restBetweenRounds;
  final bool showRoundRest;
  final void Function(int?) onRestBetweenExercisesChanged;
  final void Function(int?) onRestBetweenRoundsChanged;

  const _BlockRestSettings({
    required this.restBetweenExercises,
    required this.restBetweenRounds,
    required this.showRoundRest,
    required this.onRestBetweenExercisesChanged,
    required this.onRestBetweenRoundsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RestRow(
            label: 'Rest between exercises',
            value: restBetweenExercises,
            hint: 'None (just confirm)',
            onChanged: onRestBetweenExercisesChanged,
          ),
          if (showRoundRest) ...[
            const SizedBox(height: 6),
            _RestRow(
              label: 'Rest between rounds',
              value: restBetweenRounds,
              hint: 'Auto',
              onChanged: onRestBetweenRoundsChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _RestRow extends StatelessWidget {
  final String label;
  final int? value;
  final String hint;
  final void Function(int?) onChanged;

  const _RestRow({
    required this.label,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
        GestureDetector(
          onTap: () => _showPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.surfaceLight),
            ),
            child: Text(
              value != null ? '${value}s' : hint,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: value != null
                    ? AppColors.textPrimary
                    : AppColors.textLight,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showPicker(BuildContext context) {
    final options = [null, 30, 45, 60, 75, 90, 120, 150, 180];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) => ListTile(
                  title: Text(
                    opt != null ? '${opt}s' : hint,
                    style: TextStyle(
                      fontWeight: opt == value
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: opt == value
                          ? AppColors.primaryLemonDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  trailing: opt == value
                      ? const Icon(Icons.check,
                          color: AppColors.primaryLemonDark, size: 18)
                      : null,
                  onTap: () {
                    onChanged(opt);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Exercise row widget ─────────────────────────────────────────────────────

class _ExerciseRowWidget extends StatelessWidget {
  final TemplateExercise exercise;
  final String weightUnit;
  final VoidCallback onEditDefaults;
  final VoidCallback onRemove;

  const _ExerciseRowWidget({
    required this.exercise,
    this.weightUnit = 'lbs',
    required this.onEditDefaults,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.exerciseName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${exercise.defaultSets} x ${exercise.defaultReps}'
                    '${exercise.defaultWeight != null ? ' @ ${exercise.defaultWeight!.toStringAsFixed(1)} $weightUnit' : ''}'
                    '  ·  ${exercise.defaultRestSeconds}s rest',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon:
                Icon(Icons.more_vert, size: 18, color: AppColors.textLight),
            onSelected: (v) {
              if (v == 'edit') onEditDefaults();
              if (v == 'remove') onRemove();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'edit', child: Text('Edit Defaults')),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Exercise defaults editor sheet ──────────────────────────────────────────
// Set type selector has been removed — set types are auto-detected from blocks.

class _ExerciseDefaultsSheet extends StatefulWidget {
  final TemplateExercise exercise;
  final String weightUnit;
  final void Function(TemplateExercise) onSave;

  const _ExerciseDefaultsSheet({
    required this.exercise,
    this.weightUnit = 'lbs',
    required this.onSave,
  });

  @override
  State<_ExerciseDefaultsSheet> createState() =>
      _ExerciseDefaultsSheetState();
}

class _ExerciseDefaultsSheetState extends State<_ExerciseDefaultsSheet> {
  late int _sets;
  late int _reps;
  late double? _weight;
  late int _rest;

  @override
  void initState() {
    super.initState();
    _sets = widget.exercise.defaultSets;
    _reps = widget.exercise.defaultReps;
    _weight = widget.exercise.defaultWeight;
    _rest = widget.exercise.defaultRestSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.exercise.exerciseName,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          // Sets / Reps row
          Row(
            children: [
              Expanded(
                  child: _NumberField(
                label: 'Sets',
                value: _sets,
                onChanged: (v) => setState(() => _sets = v),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: _NumberField(
                label: 'Reps',
                value: _reps,
                onChanged: (v) => setState(() => _reps = v),
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Weight (${widget.weightUnit})',
                  value: _weight?.toInt() ?? 0,
                  allowDecimal: true,
                  onChanged: (v) =>
                      setState(() => _weight = v > 0 ? v.toDouble() : null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: _NumberField(
                label: 'Rest (sec)',
                value: _rest,
                step: 15,
                onChanged: (v) => setState(() => _rest = v),
              )),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                widget.onSave(widget.exercise.copyWith(
                  defaultSets: _sets,
                  defaultReps: _reps,
                  defaultWeight: _weight,
                  defaultRestSeconds: _rest,
                ));
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLemon,
                foregroundColor: AppColors.textOnYellow,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Number field with +/- buttons and direct text input ─────────────────────

class _NumberField extends StatefulWidget {
  final String label;
  final int value;
  final int step;
  final bool allowDecimal;
  final void Function(int) onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    this.step = 1,
    this.allowDecimal = false,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    // Sync from parent only when the value actually changed externally
    final current = int.tryParse(_controller.text) ?? -1;
    if (current != widget.value && old.value != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final current = double.tryParse(_controller.text) ?? widget.value.toDouble();
    final next = max(0, (current + delta).toInt());
    _controller.text = '$next';
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 16),
                onPressed: () => _step(-widget.step),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: widget.allowDecimal,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      widget.allowDecimal
                          ? RegExp(r'[\d.]')
                          : RegExp(r'\d'),
                    ),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final parsed = widget.allowDecimal
                        ? (double.tryParse(v)?.toInt())
                        : int.tryParse(v);
                    if (parsed != null) widget.onChanged(parsed);
                  },
                  onTapOutside: (_) {
                    if (_controller.text.trim().isEmpty) {
                      _controller.text = '0';
                      widget.onChanged(0);
                    }
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                onPressed: () => _step(widget.step),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
