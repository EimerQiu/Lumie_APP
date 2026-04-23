import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../providers/exercise_library_provider.dart';
import '../widgets/create_exercise_sheet.dart';

/// Searchable exercise library screen with filters for muscle group,
/// equipment type, and text search. Used standalone or as a picker.
class ExerciseLibraryScreen extends StatefulWidget {
  /// If true, tapping an exercise returns it via Navigator.pop.
  final bool pickerMode;

  const ExerciseLibraryScreen({super.key, this.pickerMode = false});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _searchController = TextEditingController();

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
    final provider = context.watch<ExerciseLibraryProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.pickerMode ? 'Add Exercise' : 'Exercise Library',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create Custom Exercise',
            onPressed: () => _showCreateSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: provider.setSearchQuery,
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                hintStyle: TextStyle(color: AppColors.textLight),
                prefixIcon:
                    Icon(Icons.search, color: AppColors.textLight, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          provider.setSearchQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.backgroundLight,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Filter chips
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FilterChip(
                  label: provider.muscleGroupFilter != null
                      ? ExerciseLibraryProvider.muscleLabel(
                          provider.muscleGroupFilter!)
                      : 'Muscle Group',
                  isActive: provider.muscleGroupFilter != null,
                  onTap: () => _showMuscleFilter(context, provider),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: provider.equipmentFilter != null
                      ? ExerciseLibraryProvider.equipmentLabel(
                          provider.equipmentFilter!)
                      : 'Equipment',
                  isActive: provider.equipmentFilter != null,
                  onTap: () => _showEquipmentFilter(context, provider),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: provider.movementTypeFilter != null
                      ? ExerciseLibraryProvider.movementTypeLabel(
                          provider.movementTypeFilter!)
                      : 'Movement',
                  isActive: provider.movementTypeFilter != null,
                  onTap: () => _showMovementFilter(context, provider),
                ),
                if (provider.hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Clear',
                    isActive: false,
                    onTap: provider.clearFilters,
                    icon: Icons.close,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Exercise list
          Expanded(
            child: provider.loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryLemon))
                : provider.exercises.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fitness_center,
                                size: 48, color: AppColors.textLight),
                            const SizedBox(height: 12),
                            Text(
                              'No exercises found',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: provider.exercises.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final ex = provider.exercises[i];
                          return _ExerciseCard(
                            exercise: ex,
                            onTap: () {
                              if (widget.pickerMode) {
                                Navigator.pop(context, ex);
                              } else {
                                _showExerciseDetail(context, ex);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showMuscleFilter(
      BuildContext context, ExerciseLibraryProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _FilterList(
        title: 'Muscle Group',
        options: ExerciseLibraryProvider.muscleGroups,
        labelBuilder: ExerciseLibraryProvider.muscleLabel,
        selected: provider.muscleGroupFilter,
        onSelected: (v) {
          provider.setMuscleGroupFilter(v);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showEquipmentFilter(
      BuildContext context, ExerciseLibraryProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _FilterList(
        title: 'Equipment',
        options: ExerciseLibraryProvider.equipmentTypes,
        labelBuilder: ExerciseLibraryProvider.equipmentLabel,
        selected: provider.equipmentFilter,
        onSelected: (v) {
          provider.setEquipmentFilter(v);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showMovementFilter(
      BuildContext context, ExerciseLibraryProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _FilterList(
        title: 'Movement Type',
        options: ExerciseLibraryProvider.movementTypes,
        labelBuilder: ExerciseLibraryProvider.movementTypeLabel,
        selected: provider.movementTypeFilter,
        onSelected: (v) {
          provider.setMovementTypeFilter(v);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showExerciseDetail(BuildContext context, ExerciseDefinition ex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseDetailSheet(exercise: ex),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateExerciseSheet(),
    );
  }
}

// ── Exercise Card ─────────────────────────────────────────────────────────────

class _ExerciseCard extends StatelessWidget {
  final ExerciseDefinition exercise;
  final VoidCallback onTap;

  const _ExerciseCard({required this.exercise, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(14),
          border: exercise.icd10Caution
              ? Border.all(color: Colors.orange.shade300, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            // Equipment icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _equipmentColor(exercise.equipmentType).withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  _equipmentEmoji(exercise.equipmentType),
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          exercise.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (exercise.icd10Caution)
                        Tooltip(
                          message:
                              'This exercise may not be recommended for your condition',
                          child: Icon(Icons.warning_amber_rounded,
                              size: 18, color: Colors.orange.shade600),
                        ),
                      if (!exercise.isSystem)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLemon.withAlpha(60),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CUSTOM',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textOnYellow),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      ...exercise.primaryMuscles
                          .map(ExerciseLibraryProvider.muscleLabel),
                      ExerciseLibraryProvider.equipmentLabel(
                          exercise.equipmentType.name),
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 20, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  static Color _equipmentColor(EquipmentType type) {
    switch (type) {
      case EquipmentType.bodyweight:
        return Colors.green;
      case EquipmentType.dumbbell:
        return Colors.blue;
      case EquipmentType.barbell:
        return Colors.deepPurple;
      case EquipmentType.machine:
        return Colors.grey;
      case EquipmentType.cable:
        return Colors.teal;
      case EquipmentType.band:
        return Colors.orange;
    }
  }

  static String _equipmentEmoji(EquipmentType type) {
    switch (type) {
      case EquipmentType.bodyweight:
        return '🏃';
      case EquipmentType.dumbbell:
        return '🏋️';
      case EquipmentType.barbell:
        return '🏋️‍♂️';
      case EquipmentType.machine:
        return '⚙️';
      case EquipmentType.cable:
        return '🔗';
      case EquipmentType.band:
        return '🟡';
    }
  }
}

// ── Filter Chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final IconData? icon;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryLemon : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppColors.primaryLemonDark : AppColors.surfaceLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14,
                  color: isActive ? AppColors.textOnYellow : AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isActive ? AppColors.textOnYellow : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter Selection List ─────────────────────────────────────────────────────

class _FilterList extends StatelessWidget {
  final String title;
  final List<String> options;
  final String Function(String) labelBuilder;
  final String? selected;
  final void Function(String?) onSelected;

  const _FilterList({
    required this.title,
    required this.options,
    required this.labelBuilder,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          // "All" option
          ListTile(
            title: const Text('All'),
            trailing:
                selected == null ? const Icon(Icons.check, size: 20) : null,
            onTap: () => onSelected(null),
          ),
          ...options.map((opt) => ListTile(
                title: Text(labelBuilder(opt)),
                trailing: selected == opt
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () => onSelected(opt),
              )),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Exercise Detail Sheet ─────────────────────────────────────────────────────

class _ExerciseDetailSheet extends StatelessWidget {
  final ExerciseDefinition exercise;

  const _ExerciseDetailSheet({required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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
          // Name + equipment badge
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ExerciseLibraryProvider.equipmentLabel(
                      exercise.equipmentType.name),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ICD-10 caution banner
          if (exercise.icd10Caution) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This exercise may require caution based on your health condition. Consult your care team if unsure.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Primary muscles
          if (exercise.primaryMuscles.isNotEmpty) ...[
            Text('Primary Muscles',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: exercise.primaryMuscles.map((m) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLemon.withAlpha(50),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ExerciseLibraryProvider.muscleLabel(m),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textOnYellow,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          // Secondary muscles
          if (exercise.secondaryMuscles.isNotEmpty) ...[
            Text('Secondary Muscles',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: exercise.secondaryMuscles.map((m) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ExerciseLibraryProvider.muscleLabel(m),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          // Movement type
          Row(
            children: [
              Text('Movement: ',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              Text(
                ExerciseLibraryProvider.movementTypeLabel(
                    exercise.movementType),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Form description
          if (exercise.formDescription.isNotEmpty) ...[
            Text('Correct Form',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                exercise.formDescription,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          ],
          // Description (if different from form)
          if (exercise.description.isNotEmpty &&
              exercise.description != exercise.formDescription) ...[
            const SizedBox(height: 10),
            Text(
              exercise.description,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
