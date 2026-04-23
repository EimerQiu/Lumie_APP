import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Full-screen rest timer displayed between sets.
/// When the timer reaches zero, shows a "Ready? Start Next Set" button
/// instead of automatically starting the next set.
class RestTimerWidget extends StatelessWidget {
  final int secondsRemaining;
  final int totalRestDuration;
  final bool timerExpired;
  final VoidCallback onSkip;
  final void Function(int delta) onAdjust;
  final String nextExerciseName;
  final int nextSetIndex;
  final int totalSets;

  const RestTimerWidget({
    super.key,
    required this.secondsRemaining,
    this.totalRestDuration = 60,
    this.timerExpired = false,
    required this.onSkip,
    required this.onAdjust,
    required this.nextExerciseName,
    required this.nextSetIndex,
    required this.totalSets,
  });

  @override
  Widget build(BuildContext context) {
    final denom = totalRestDuration > 0 ? totalRestDuration.toDouble() : 60.0;
    final progress = secondsRemaining > 0 ? secondsRemaining / denom : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              timerExpired ? 'REST COMPLETE' : 'REST',
              style: TextStyle(
                color: timerExpired
                    ? AppColors.primaryLemon
                    : Colors.white.withAlpha(120),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 16),
            // Circular countdown
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CircularProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      strokeWidth: 6,
                      backgroundColor: Colors.white.withAlpha(20),
                      valueColor: AlwaysStoppedAnimation(
                        timerExpired
                            ? AppColors.primaryLemon
                            : AppColors.primaryLemon,
                      ),
                    ),
                  ),
                  if (timerExpired)
                    Icon(
                      Icons.check_circle_outline,
                      color: AppColors.primaryLemon,
                      size: 56,
                    )
                  else
                    Text(
                      _format(secondsRemaining),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // +/- 10s buttons (only while timer is counting)
            if (!timerExpired)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AdjustButton(label: '-10s', onTap: () => onAdjust(-10)),
                  const SizedBox(width: 16),
                  _AdjustButton(label: '+10s', onTap: () => onAdjust(10)),
                ],
              ),
            if (!timerExpired) const SizedBox(height: 24),
            // Next exercise info
            if (nextExerciseName.isNotEmpty) ...[
              Text(
                'UP NEXT',
                style: TextStyle(
                  color: Colors.white.withAlpha(100),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                nextExerciseName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                'Set $nextSetIndex of $totalSets',
                style: TextStyle(
                  color: Colors.white.withAlpha(150),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 32),
            // Primary action button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onSkip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLemon,
                    foregroundColor: AppColors.textOnYellow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    timerExpired ? 'Ready? Start Next Set' : 'Skip Rest',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _format(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    if (m > 0) {
      return '$m:${sec.toString().padLeft(2, '0')}';
    }
    return '$sec';
  }
}

class _AdjustButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AdjustButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
