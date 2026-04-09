import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';

/// Manual logging view for machine exercises or when camera detection is skipped.
/// Shows exercise name, set number, weight/reps input fields, and a complete button.
class ManualExerciseView extends StatefulWidget {
  final TemplateExercise exercise;
  final int setIndex;
  final int totalSets;
  final double? prefilledWeight;
  final void Function(int reps, double? weight, SetCompletionStatus status,
      String? notes) onSetComplete;
  final VoidCallback? onEnableCamera;

  const ManualExerciseView({
    super.key,
    required this.exercise,
    required this.setIndex,
    required this.totalSets,
    this.prefilledWeight,
    required this.onSetComplete,
    this.onEnableCamera,
  });

  @override
  State<ManualExerciseView> createState() => _ManualExerciseViewState();
}

class _ManualExerciseViewState extends State<ManualExerciseView> {
  late TextEditingController _weightController;
  late TextEditingController _repsController;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final w = widget.prefilledWeight ?? widget.exercise.defaultWeight;
    _weightController = TextEditingController(
      text: w?.toStringAsFixed(0) ?? '',
    );
    _repsController = TextEditingController(
      text: widget.exercise.defaultReps.toString(),
    );
  }

  @override
  void didUpdateWidget(ManualExerciseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setIndex != widget.setIndex ||
        oldWidget.exercise.exerciseId != widget.exercise.exerciseId) {
      _repsController.text = widget.exercise.defaultReps.toString();
      final w = widget.prefilledWeight ?? widget.exercise.defaultWeight;
      if (w != null) {
        _weightController.text = w.toStringAsFixed(0);
      }
      _notesController.clear();
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          // Exercise name
          Text(
            widget.exercise.exerciseName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Set indicator
          Text(
            'Set ${widget.setIndex + 1} of ${widget.totalSets}',
            style: TextStyle(
              color: Colors.white.withAlpha(180),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          // Equipment badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.exercise.equipmentType.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withAlpha(150),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 36),
          // Weight input
          Row(
            children: [
              Expanded(
                child: _InputField(
                  controller: _weightController,
                  label: 'Weight (lbs)',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _InputField(
                  controller: _repsController,
                  label: 'Reps',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Notes
          _InputField(
            controller: _notesController,
            label: 'Notes (optional)',
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 32),
          // Complete set button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _completeSet,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLemon,
                foregroundColor: AppColors.textOnYellow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Complete Set',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Mark as failure button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => _completeWithStatus(SetCompletionStatus.failed),
                child: Text(
                  'Mark as Failed',
                  style: TextStyle(
                      color: Colors.red.shade300, fontSize: 13),
                ),
              ),
              if (widget.onEnableCamera != null) ...[
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: widget.onEnableCamera,
                  icon: Icon(Icons.videocam,
                      size: 16, color: Colors.white.withAlpha(180)),
                  label: Text(
                    'Use Camera',
                    style: TextStyle(
                        color: Colors.white.withAlpha(180), fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }

  void _completeSet() {
    _completeWithStatus(SetCompletionStatus.completed);
  }

  void _completeWithStatus(SetCompletionStatus status) {
    final reps = int.tryParse(_repsController.text) ??
        widget.exercise.defaultReps;
    final weight = double.tryParse(_weightController.text);
    final notes = _notesController.text.trim();
    widget.onSetComplete(
      reps,
      weight,
      status,
      notes.isNotEmpty ? notes : null,
    );
  }
}

// ── Input field ─────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;

  const _InputField({
    required this.controller,
    required this.label,
    required this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withAlpha(120), fontSize: 13),
        filled: true,
        fillColor: Colors.white.withAlpha(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withAlpha(30)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withAlpha(30)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryLemon),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
