import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/workout_service.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../../workout/providers/exercise_library_provider.dart';
import '../providers/workout_history_provider.dart';

/// Manual workout logger — user picks exercises, then enters sets/reps/weight.
/// No template required. Saves directly as a WorkoutSession.
class QuickLogScreen extends StatefulWidget {
  const QuickLogScreen({super.key});

  @override
  State<QuickLogScreen> createState() => _QuickLogScreenState();
}

class _QuickLogScreenState extends State<QuickLogScreen> {
  final _titleController = TextEditingController(text: 'My Workout');
  final List<_LoggedExercise> _exercises = [];
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _addExercise(ExerciseDefinition def) {
    setState(() {
      _exercises.add(_LoggedExercise(definition: def));
    });
  }

  void _removeExercise(int index) {
    setState(() => _exercises.removeAt(index));
  }

  Future<void> _save() async {
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise')),
      );
      return;
    }

    setState(() => _saving = true);

    final now = DateTime.now().toUtc();
    final exercises = _exercises.map((ex) {
      final sets = ex.sets.asMap().entries.map((entry) {
        final i = entry.key;
        final s = entry.value;
        return CompletedSet(
          setIndex: i,
          targetReps: s.reps,
          targetWeight: s.weight,
          actualReps: s.reps,
          actualWeight: s.weight,
          status: SetCompletionStatus.completed,
        );
      }).toList();

      return CompletedExercise(
        exerciseId: ex.definition.exerciseId,
        exerciseName: ex.definition.name,
        equipmentType: ex.definition.equipmentType.name,
        poseType: ex.definition.poseType,
        sets: sets,
      );
    }).toList();

    try {
      final api = WorkoutApiService();
      final session = await api.createSession(sessionData: {
        'template_name': _titleController.text.trim().isEmpty
            ? 'My Workout'
            : _titleController.text.trim(),
        'started_at': now.toIso8601String(),
        'ended_at': now.toIso8601String(),
        'duration_seconds': 0,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'source': 'user_manual',
      });

      if (!mounted) return;

      // Push to history provider so it appears immediately
      context.read<WorkoutHistoryProvider>().addSession(session);

      Navigator.pop(context, session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close,
              color: AppColors.textPrimary, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Log Workout',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryLemonDark),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryLemonDark,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Workout title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TextField(
              controller: _titleController,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'Workout title',
                hintStyle: TextStyle(color: AppColors.textLight),
                border: InputBorder.none,
              ),
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: _exercises.isEmpty
                ? _EmptyState(onAdd: () => _showExercisePicker())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _exercises.length,
                    itemBuilder: (context, i) => _ExerciseBlock(
                      exercise: _exercises[i],
                      onRemove: () => _removeExercise(i),
                      onChanged: () => setState(() {}),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _exercises.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _showExercisePicker,
              backgroundColor: AppColors.primaryLemonDark,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Exercise',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
    );
  }

  void _showExercisePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExercisePickerSheet(
        onPick: (def) {
          Navigator.pop(context);
          _addExercise(def);
        },
      ),
    );
  }
}

// ── Data model for in-progress logging ───────────────────────────────────────

class _SetEntry {
  int reps;
  double? weight;
  _SetEntry({this.reps = 10, this.weight});
}

class _LoggedExercise {
  final ExerciseDefinition definition;
  final List<_SetEntry> sets;

  _LoggedExercise({required this.definition})
      : sets = [_SetEntry()]; // Start with one set
}

// ── Exercise block widget ─────────────────────────────────────────────────────

class _ExerciseBlock extends StatelessWidget {
  final _LoggedExercise exercise;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _ExerciseBlock({
    required this.exercise,
    required this.onRemove,
    required this.onChanged,
  });

  String _equipLabel(EquipmentType e) {
    const m = {
      EquipmentType.bodyweight: 'Bodyweight',
      EquipmentType.dumbbell: 'Dumbbell',
      EquipmentType.barbell: 'Barbell',
      EquipmentType.machine: 'Machine',
      EquipmentType.cable: 'Cable',
      EquipmentType.band: 'Band',
    };
    return m[e] ?? e.name;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.definition.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLemon,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _equipLabel(exercise.definition.equipmentType),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textOnYellow,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.textLight, size: 20),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),

          // Set column headers
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text('Set',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: Text('Reps',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                ),
                SizedBox(
                  width: 100,
                  child: Text('Weight (lb)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                ),
                SizedBox(width: 36),
              ],
            ),
          ),

          // Set rows
          ...exercise.sets.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return _SetRow(
              index: i,
              set: s,
              onChanged: onChanged,
              onDelete: exercise.sets.length > 1
                  ? () {
                      exercise.sets.removeAt(i);
                      onChanged();
                    }
                  : null,
            );
          }),

          // Add set button
          TextButton.icon(
            onPressed: () {
              final last = exercise.sets.last;
              exercise.sets.add(_SetEntry(
                reps: last.reps,
                weight: last.weight,
              ));
              onChanged();
            },
            icon: const Icon(Icons.add, size: 16,
                color: AppColors.primaryLemonDark),
            label: const Text('Add Set',
                style: TextStyle(
                    color: AppColors.primaryLemonDark,
                    fontWeight: FontWeight.w500)),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12)),
          ),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final int index;
  final _SetEntry set;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  const _SetRow({
    required this.index,
    required this.set,
    required this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: _NumField(
              value: set.reps,
              hint: '0',
              onChanged: (v) {
                set.reps = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: _WeightField(
              value: set.weight,
              hint: 'BW',
              onChanged: (v) {
                set.weight = v;
                onChanged();
              },
            ),
          ),
          SizedBox(
            width: 36,
            child: onDelete != null
                ? IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 18, color: AppColors.textLight),
                    onPressed: onDelete,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatefulWidget {
  final int value;
  final String hint;
  final ValueChanged<int> onChanged;

  const _NumField(
      {required this.value, required this.hint, required this.onChanged});

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
        text: widget.value > 0 ? '${widget.value}' : '');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle:
            const TextStyle(color: AppColors.textLight, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        filled: true,
        fillColor: AppColors.backgroundPaper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) => widget.onChanged(int.tryParse(v) ?? 0),
    );
  }
}

class _WeightField extends StatefulWidget {
  final double? value;
  final String hint;
  final ValueChanged<double?> onChanged;

  const _WeightField(
      {required this.value, required this.hint, required this.onChanged});

  @override
  State<_WeightField> createState() => _WeightFieldState();
}

class _WeightFieldState extends State<_WeightField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
        text: widget.value != null ? '${widget.value}' : '');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
      ],
      textAlign: TextAlign.center,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle:
            const TextStyle(color: AppColors.textLight, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        filled: true,
        fillColor: AppColors.backgroundPaper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) => widget.onChanged(double.tryParse(v)),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center_outlined,
              size: 52, color: AppColors.textLight),
          const SizedBox(height: 16),
          const Text(
            'No exercises yet',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap below to add your first movement',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Exercise'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLemonDark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise picker sheet ─────────────────────────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  final ValueChanged<ExerciseDefinition> onPick;

  const _ExercisePickerSheet({required this.onPick});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExerciseLibraryProvider>().loadExercises();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select Exercise',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search exercises…',
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.backgroundPaper,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),

          // Exercise list
          Expanded(
            child: Consumer<ExerciseLibraryProvider>(
              builder: (context, provider, _) {
                if (provider.loading) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryLemonDark),
                  );
                }
                final filtered = _query.isEmpty
                    ? provider.exercises
                    : provider.exercises
                        .where((e) =>
                            e.name.toLowerCase().contains(_query) ||
                            e.primaryMuscles.any((m) =>
                                m.toLowerCase().contains(_query)))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No exercises found for "$_query"',
                      style: const TextStyle(
                          color: AppColors.textSecondary),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final ex = filtered[i];
                    return GestureDetector(
                      onTap: () => widget.onPick(ex),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundPaper,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ex.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (ex.primaryMuscles.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      ex.primaryMuscles.join(', '),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLemon,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                ex.equipmentType.name,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textOnYellow,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
