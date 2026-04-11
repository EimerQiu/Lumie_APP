import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Top bar for the active workout session showing workout name, block,
/// elapsed duration timer, rest countdown timer, session goal, and end button.
class SessionHeader extends StatelessWidget {
  final String workoutName;
  final String blockName;
  final int elapsedSeconds;
  final bool isResting;
  final int restSecondsRemaining;
  final String? sessionGoal;
  final VoidCallback? onEndWorkout;

  const SessionHeader({
    super.key,
    required this.workoutName,
    required this.blockName,
    required this.elapsedSeconds,
    required this.isResting,
    required this.restSecondsRemaining,
    this.sessionGoal,
    this.onEndWorkout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(
          bottom: BorderSide(color: Colors.white.withAlpha(15)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Workout name + block + timers
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workoutName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (blockName.isNotEmpty)
                      Text(
                        blockName,
                        style: TextStyle(
                          color: Colors.white.withAlpha(150),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // Duration timer
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 14, color: Colors.white.withAlpha(180)),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(elapsedSeconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (isResting) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLemon.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pause_circle_filled,
                          size: 14, color: AppColors.primaryLemon),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(restSecondsRemaining),
                        style: const TextStyle(
                          color: AppColors.primaryLemon,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (onEndWorkout != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onEndWorkout,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withAlpha(60)),
                    ),
                    child: Text(
                      'End',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Session goal label
          if (sessionGoal != null && sessionGoal!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryLemon.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Goal: $sessionGoal',
                style: TextStyle(
                  color: AppColors.primaryLemon.withAlpha(200),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
