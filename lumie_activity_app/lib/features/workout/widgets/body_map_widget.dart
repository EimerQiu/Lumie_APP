import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../providers/exercise_library_provider.dart';

/// Simplified front/back body silhouette highlighting worked muscle groups.
class BodyMapWidget extends StatelessWidget {
  final List<CompletedExercise> exercises;

  const BodyMapWidget({super.key, required this.exercises});

  @override
  Widget build(BuildContext context) {
    // Collect all primary muscles from exercises based on known mappings
    final muscles = <String>{};
    for (final ex in exercises) {
      muscles.addAll(_musclesForExercise(ex.exerciseId));
    }

    if (muscles.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text('No muscle data available',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          // Muscle chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: muscles.map((m) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryLemon.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 12),
          // Simple body diagram using CustomPaint
          SizedBox(
            height: 200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BodySilhouette(
                  label: 'Front',
                  highlightedMuscles: muscles,
                  isFront: true,
                ),
                _BodySilhouette(
                  label: 'Back',
                  highlightedMuscles: muscles,
                  isFront: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Map exercise IDs to known primary muscle groups.
  static Set<String> _musclesForExercise(String exerciseId) {
    const map = {
      'bw_squat': {'quadriceps', 'glutes'},
      'bw_pushup': {'chest', 'shoulders', 'triceps'},
      'bw_lunge': {'quadriceps', 'glutes'},
      'db_bicep_curl': {'biceps'},
      'db_shoulder_press': {'shoulders', 'triceps'},
      'db_lateral_raise': {'shoulders'},
      'db_rdl': {'hamstrings', 'glutes'},
      'db_goblet_squat': {'quadriceps', 'glutes'},
      'db_bench_press': {'chest', 'triceps'},
      'db_row': {'lats', 'biceps'},
      'bb_back_squat': {'quadriceps', 'glutes'},
      'bb_bench_press': {'chest', 'triceps'},
      'bb_deadlift': {'hamstrings', 'lower_back'},
      'bb_row': {'lats', 'biceps'},
      'bb_overhead_press': {'shoulders', 'triceps'},
      'bb_rdl': {'hamstrings', 'glutes'},
      'm_leg_press': {'quadriceps', 'glutes'},
      'm_lat_pulldown': {'lats', 'biceps'},
      'm_chest_press': {'chest', 'triceps'},
      'm_leg_curl': {'hamstrings'},
      'm_leg_extension': {'quadriceps'},
    };
    return map[exerciseId] ?? {};
  }
}

/// Simplified body silhouette using CustomPaint with highlighted regions.
class _BodySilhouette extends StatelessWidget {
  final String label;
  final Set<String> highlightedMuscles;
  final bool isFront;

  const _BodySilhouette({
    required this.label,
    required this.highlightedMuscles,
    required this.isFront,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Expanded(
          child: CustomPaint(
            size: const Size(80, 160),
            painter: _BodyPainter(
              highlightedMuscles: highlightedMuscles,
              isFront: isFront,
            ),
          ),
        ),
      ],
    );
  }
}

class _BodyPainter extends CustomPainter {
  final Set<String> highlightedMuscles;
  final bool isFront;

  _BodyPainter({required this.highlightedMuscles, required this.isFront});

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = AppColors.primaryLemonDark.withAlpha(180)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Head
    canvas.drawCircle(Offset(w * 0.5, h * 0.08), w * 0.1, basePaint);

    // Torso
    final torsoRect =
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.25, h * 0.16, w * 0.5, h * 0.35),
          const Radius.circular(6),
        );
    final torsoMuscles = isFront
        ? {'chest', 'core', 'shoulders'}
        : {'back', 'lats', 'rhomboids', 'traps', 'lower_back'};
    final torsoActive = torsoMuscles.intersection(highlightedMuscles).isNotEmpty;
    canvas.drawRRect(torsoRect, torsoActive ? highlightPaint : basePaint);

    // Arms
    final armMuscles = {'biceps', 'triceps', 'forearms', 'shoulders'};
    final armsActive = armMuscles.intersection(highlightedMuscles).isNotEmpty;
    final armPaint = armsActive ? highlightPaint : basePaint;
    // Left arm
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.18, w * 0.14, h * 0.3),
        const Radius.circular(4),
      ),
      armPaint,
    );
    // Right arm
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.78, h * 0.18, w * 0.14, h * 0.3),
        const Radius.circular(4),
      ),
      armPaint,
    );

    // Legs
    final legMuscles = {
      'quadriceps', 'hamstrings', 'glutes', 'calves', 'legs'
    };
    final legsActive = legMuscles.intersection(highlightedMuscles).isNotEmpty;
    final legPaint = legsActive ? highlightPaint : basePaint;
    // Left leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.25, h * 0.53, w * 0.2, h * 0.42),
        const Radius.circular(4),
      ),
      legPaint,
    );
    // Right leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.55, h * 0.53, w * 0.2, h * 0.42),
        const Radius.circular(4),
      ),
      legPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BodyPainter oldDelegate) =>
      highlightedMuscles != oldDelegate.highlightedMuscles ||
      isFront != oldDelegate.isFront;
}
