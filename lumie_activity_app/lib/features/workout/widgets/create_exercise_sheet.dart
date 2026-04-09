import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/subscription_error.dart';
import '../../teams/widgets/upgrade_prompt_sheet.dart';
import '../providers/exercise_library_provider.dart';

/// Bottom sheet for creating a custom exercise.
class CreateExerciseSheet extends StatefulWidget {
  const CreateExerciseSheet({super.key});

  @override
  State<CreateExerciseSheet> createState() => _CreateExerciseSheetState();
}

class _CreateExerciseSheetState extends State<CreateExerciseSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _equipmentType = 'bodyweight';
  final String _movementType = 'isolation';
  final List<String> _primaryMuscles = [];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
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
      child: SingleChildScrollView(
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
            const Text('Create Custom Exercise',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            // Name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Exercise Name',
                filled: true,
                fillColor: AppColors.backgroundLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Equipment type
            const Text('Equipment',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: ExerciseLibraryProvider.equipmentTypes.map((eq) {
                final sel = _equipmentType == eq;
                return ChoiceChip(
                  label: Text(ExerciseLibraryProvider.equipmentLabel(eq)),
                  selected: sel,
                  selectedColor: AppColors.primaryLemon,
                  backgroundColor: AppColors.backgroundLight,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: sel ? AppColors.textOnYellow : AppColors.textSecondary,
                  ),
                  onSelected: (_) => setState(() => _equipmentType = eq),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Muscle groups
            const Text('Primary Muscle Groups',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ExerciseLibraryProvider.muscleGroups.map((mg) {
                final sel = _primaryMuscles.contains(mg);
                return FilterChip(
                  label: Text(ExerciseLibraryProvider.muscleLabel(mg)),
                  selected: sel,
                  selectedColor: AppColors.primaryLemon,
                  backgroundColor: AppColors.backgroundLight,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: sel ? AppColors.textOnYellow : AppColors.textSecondary,
                  ),
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _primaryMuscles.add(mg);
                      } else {
                        _primaryMuscles.remove(mg);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Description
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Form Description (optional)',
                filled: true,
                fillColor: AppColors.backgroundLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLemon,
                  foregroundColor: AppColors.textOnYellow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Exercise',
                        style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      await context.read<ExerciseLibraryProvider>().createCustomExercise(
            name: name,
            description: _descController.text.trim(),
            primaryMuscles: _primaryMuscles,
            equipmentType: _equipmentType,
            movementType: _movementType,
            formDescription: _descController.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } on SubscriptionLimitException {
      if (mounted) {
        UpgradePromptBottomSheet.showCustom(
          context: context,
          title: 'Custom Exercises',
          message: 'Custom exercise creation requires a Pro subscription.',
          detail: 'Upgrade to create unlimited custom exercises.',
          actionLabel: 'Upgrade to Pro',
          onUpgrade: () {},
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
