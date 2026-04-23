import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Timer widget for the 6-minute walk test
class WalkTestTimer extends StatelessWidget {
  final int elapsedSeconds;
  final int totalSeconds;

  const WalkTestTimer({
    super.key,
    required this.elapsedSeconds,
    required this.totalSeconds,
  });

  String get _timeDisplay {
    final remaining = totalSeconds - elapsedSeconds;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double get _progress => elapsedSeconds / totalSeconds;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background glow
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryLemon.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Progress ring
            CustomPaint(
              size: const Size(180, 180),
              painter: _TimerPainter(
                progress: _progress,
              ),
            ),
            // Time display
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _timeDisplay,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Text(
                  'remaining',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerPainter extends CustomPainter {
  final double progress;

  _TimerPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 12.0;

    // Background track
    final trackPaint = Paint()
      ..color = AppColors.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - strokeWidth / 2, trackPaint);

    // Progress arc
    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

      // Create gradient shader
      final gradient = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: const [
          Color(0xFFFFEB3B),
          Color(0xFFFFC107),
          Color(0xFFFF9800),
          Color(0xFFFF5722),
        ],
        stops: const [0.0, 0.33, 0.66, 1.0],
      );

      final progressPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TimerPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
