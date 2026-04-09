import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/workout_service.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../providers/workout_template_provider.dart';
import 'exercise_library_screen.dart';

/// Screen for building / editing a single workout template.
/// Supports blocks, reordering, set types (superset/circuit grouping),
/// and per-exercise defaults.
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
  final _nameController = TextEditingController();

  // Grouping mode
  bool _groupingMode = false;
  final Set<String> _selectedForGrouping = {};

  @override
  void initState() {
    super.initState();
    _loadTemplate();
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
      // Fetch from API
      try {
        final fetched = await WorkoutApiService().getTemplate(widget.templateId);
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
          if (_groupingMode)
            TextButton(
              onPressed: _applyGrouping,
              child: const Text('Done',
                  style: TextStyle(
                      color: AppColors.primaryLemonDark,
                      fontWeight: FontWeight.w600)),
            )
          else ...[
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
                  child: Text('Delete Template',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Name field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Workout name',
                border: InputBorder.none,
                suffixIcon: Text(template.emoji,
                    style: const TextStyle(fontSize: 24)),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
              ),
            ),
          ),
          // Blocks and exercises
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: _allItems.length,
              onReorder: _onReorder,
              proxyDecorator: (child, _, _) => Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
              itemBuilder: (ctx, i) {
                final item = _allItems[i];
                if (item.isBlockHeader) {
                  return _BlockHeaderWidget(
                    key: ValueKey('block_${item.blockIndex}'),
                    block: template.blocks[item.blockIndex],
                    onRename: (name) => _renameBlock(item.blockIndex, name),
                    onDelete: () => _deleteBlock(item.blockIndex),
                  );
                }
                final ex = template
                    .blocks[item.blockIndex].exercises[item.exerciseIndex];
                return _ExerciseRowWidget(
                  key: ValueKey(
                      'ex_${item.blockIndex}_${item.exerciseIndex}_${ex.exerciseId}'),
                  exercise: ex,
                  setIndex: item.exerciseIndex,
                  isGroupingMode: _groupingMode,
                  isSelectedForGrouping: _selectedForGrouping.contains(
                      '${item.blockIndex}_${item.exerciseIndex}'),
                  groupColor: _groupColor(ex.groupId),
                  onTap: () {
                    if (_groupingMode) {
                      setState(() {
                        final key =
                            '${item.blockIndex}_${item.exerciseIndex}';
                        if (_selectedForGrouping.contains(key)) {
                          _selectedForGrouping.remove(key);
                        } else {
                          _selectedForGrouping.add(key);
                        }
                      });
                    }
                  },
                  onEditDefaults: () =>
                      _editExerciseDefaults(item.blockIndex, item.exerciseIndex),
                  onRemove: () =>
                      _removeExercise(item.blockIndex, item.exerciseIndex),
                );
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
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.link,
                color: _groupingMode
                    ? AppColors.primaryLemonDark
                    : AppColors.textSecondary,
              ),
              tooltip: 'Superset / Circuit',
              onPressed: () {
                setState(() {
                  _groupingMode = !_groupingMode;
                  if (!_groupingMode) _selectedForGrouping.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  /// Flat list of block headers + exercise rows for ReorderableListView.
  List<_ListItem> get _allItems {
    final items = <_ListItem>[];
    final template = _template!;
    for (int b = 0; b < template.blocks.length; b++) {
      items.add(_ListItem(blockIndex: b, exerciseIndex: -1));
      for (int e = 0; e < template.blocks[b].exercises.length; e++) {
        items.add(_ListItem(blockIndex: b, exerciseIndex: e));
      }
    }
    return items;
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final items = _allItems;
    if (oldIndex < 0 || oldIndex >= items.length) return;
    final moved = items[oldIndex];
    // Only reorder exercise rows (not block headers)
    if (moved.isBlockHeader) return;

    // Determine destination block + position
    final dest = newIndex < items.length ? items[newIndex] : items.last;
    final destBlock = dest.isBlockHeader ? dest.blockIndex : dest.blockIndex;
    // Remove from source block
    final srcBlock = moved.blockIndex;
    final srcEx = moved.exerciseIndex;
    if (srcBlock >= _template!.blocks.length) return;
    if (srcEx >= _template!.blocks[srcBlock].exercises.length) return;

    setState(() {
      final exercise = _template!.blocks[srcBlock].exercises.removeAt(srcEx);
      // Insert into destination block
      if (destBlock < _template!.blocks.length) {
        final destIdx = dest.isBlockHeader
            ? 0
            : (dest.exerciseIndex).clamp(0, _template!.blocks[destBlock].exercises.length);
        _template!.blocks[destBlock].exercises.insert(destIdx, exercise);
      }
      // Renumber orders
      for (final block in _template!.blocks) {
        for (int i = 0; i < block.exercises.length; i++) {
          block.exercises[i].order = i;
        }
      }
    });
  }

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

  void _renameBlock(int blockIdx, String name) {
    setState(() => _template!.blocks[blockIdx].name = name);
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
    // Ensure at least one block exists
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
        onSave: (updated) {
          setState(() =>
              _template!.blocks[blockIdx].exercises[exIdx] = updated);
        },
      ),
    );
  }

  void _applyGrouping() {
    if (_selectedForGrouping.length < 2) {
      setState(() {
        _groupingMode = false;
        _selectedForGrouping.clear();
      });
      return;
    }

    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final setType = _selectedForGrouping.length == 2
        ? SetType.superset
        : SetType.circuit;

    setState(() {
      for (final key in _selectedForGrouping) {
        final parts = key.split('_');
        final b = int.parse(parts[0]);
        final e = int.parse(parts[1]);
        _template!.blocks[b].exercises[e].groupId = groupId;
        _template!.blocks[b].exercises[e].setType = setType;
      }
      _groupingMode = false;
      _selectedForGrouping.clear();
    });
  }

  Color? _groupColor(String? groupId) {
    if (groupId == null) return null;
    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
    ];
    return colors[groupId.hashCode.abs() % colors.length];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final template = _template!;
    template.name = _nameController.text.trim().isEmpty
        ? 'Untitled Workout'
        : _nameController.text.trim();

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

// ── List item helper ──────────────────────────────────────────────────────────

class _ListItem {
  final int blockIndex;
  final int exerciseIndex; // -1 = block header
  const _ListItem({required this.blockIndex, required this.exerciseIndex});
  bool get isBlockHeader => exerciseIndex < 0;
}

// ── Block header widget ───────────────────────────────────────────────────────

class _BlockHeaderWidget extends StatelessWidget {
  final WorkoutBlock block;
  final void Function(String) onRename;
  final VoidCallback onDelete;

  const _BlockHeaderWidget({
    super.key,
    required this.block,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final controller = TextEditingController(text: block.name);
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Rename Block'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                          hintText: 'Block name'),
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () =>
                              Navigator.pop(ctx, controller.text.trim()),
                          child: const Text('Save')),
                    ],
                  ),
                );
                if (name != null && name.isNotEmpty) onRename(name);
              },
              child: Text(
                block.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: AppColors.textLight),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Exercise row widget ───────────────────────────────────────────────────────

class _ExerciseRowWidget extends StatelessWidget {
  final TemplateExercise exercise;
  final int setIndex;
  final bool isGroupingMode;
  final bool isSelectedForGrouping;
  final Color? groupColor;
  final VoidCallback onTap;
  final VoidCallback onEditDefaults;
  final VoidCallback onRemove;

  const _ExerciseRowWidget({
    super.key,
    required this.exercise,
    required this.setIndex,
    this.isGroupingMode = false,
    this.isSelectedForGrouping = false,
    this.groupColor,
    required this.onTap,
    required this.onEditDefaults,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isSelectedForGrouping
              ? AppColors.primaryLemon.withAlpha(30)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceLight),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Group color bar
              if (groupColor != null)
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: groupColor,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(12)),
                  ),
                ),
              if (isGroupingMode)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(
                    isSelectedForGrouping
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: isSelectedForGrouping
                        ? AppColors.primaryLemonDark
                        : AppColors.textLight,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              exercise.exerciseName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (exercise.setType != SetType.straight)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    (groupColor ?? Colors.grey).withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                exercise.setType == SetType.superset
                                    ? 'SS'
                                    : exercise.setType == SetType.circuit
                                        ? 'CIR'
                                        : exercise.setType == SetType.dropSet
                                            ? 'DROP'
                                            : 'FAIL',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: groupColor ?? Colors.grey,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${exercise.defaultSets} x ${exercise.defaultReps}'
                        '${exercise.defaultWeight != null ? ' @ ${exercise.defaultWeight} lbs' : ''}'
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
              if (!isGroupingMode)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 18, color: AppColors.textLight),
                  onSelected: (v) {
                    if (v == 'edit') onEditDefaults();
                    if (v == 'remove') onRemove();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'edit', child: Text('Edit Defaults')),
                    const PopupMenuItem(
                        value: 'remove', child: Text('Remove')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Exercise defaults editor sheet ────────────────────────────────────────────

class _ExerciseDefaultsSheet extends StatefulWidget {
  final TemplateExercise exercise;
  final void Function(TemplateExercise) onSave;

  const _ExerciseDefaultsSheet({
    required this.exercise,
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
  late SetType _setType;

  @override
  void initState() {
    super.initState();
    _sets = widget.exercise.defaultSets;
    _reps = widget.exercise.defaultReps;
    _weight = widget.exercise.defaultWeight;
    _rest = widget.exercise.defaultRestSeconds;
    _setType = widget.exercise.setType;
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
              Expanded(child: _NumberField(
                label: 'Sets',
                value: _sets,
                onChanged: (v) => setState(() => _sets = v),
              )),
              const SizedBox(width: 12),
              Expanded(child: _NumberField(
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
                  label: 'Weight (lbs)',
                  value: _weight?.toInt() ?? 0,
                  onChanged: (v) =>
                      setState(() => _weight = v > 0 ? v.toDouble() : null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _NumberField(
                label: 'Rest (sec)',
                value: _rest,
                step: 15,
                onChanged: (v) => setState(() => _rest = v),
              )),
            ],
          ),
          const SizedBox(height: 12),
          // Set type
          const Text('Set Type',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: SetType.values.map((st) {
              final sel = _setType == st;
              return ChoiceChip(
                label: Text(_setTypeLabel(st)),
                selected: sel,
                selectedColor: AppColors.primaryLemon,
                backgroundColor: AppColors.backgroundLight,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: sel
                      ? AppColors.textOnYellow
                      : AppColors.textSecondary,
                ),
                onSelected: (_) => setState(() => _setType = st),
              );
            }).toList(),
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
                  setType: _setType,
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

  String _setTypeLabel(SetType st) {
    switch (st) {
      case SetType.straight:
        return 'Straight';
      case SetType.superset:
        return 'Superset';
      case SetType.circuit:
        return 'Circuit';
      case SetType.dropSet:
        return 'Drop Set';
      case SetType.failure:
        return 'Failure';
    }
  }
}

// ── Number field with +/- buttons ─────────────────────────────────────────────

class _NumberField extends StatelessWidget {
  final String label;
  final int value;
  final int step;
  final void Function(int) onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    this.step = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
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
                onPressed: () => onChanged(max(0, value - step)),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                onPressed: () => onChanged(value + step),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
