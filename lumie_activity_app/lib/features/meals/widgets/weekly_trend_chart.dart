// WeeklyTrendChart — line graph of nutrition level over the past 7 days.
//
// Y-axis: Limited / Fair / Good / Nutritious (4 stops, no numbers)
// X-axis: day-of-week initials, oldest left, today right
// Today's point is highlighted with a larger ringed dot.
// Gaps in the line show days with zero meals.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';

class WeeklyTrendChart extends StatelessWidget {
  final List<MealTrendDay> days;
  final double height;

  const WeeklyTrendChart({
    super.key,
    required this.days,
    this.height = 200,
  });

  static const _yLabels = ['Nutritious', 'Good', 'Fair', 'Limited'];
  static const _dayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  String _initialFor(DateTime dt) =>
      _dayInitials[(dt.weekday - 1) % 7];

  @override
  Widget build(BuildContext context) {
    final todayIndex = days.length - 1; // backend orders oldest → today

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Y-axis labels (4 stops, top-to-bottom: Nutritious → Limited)
                  SizedBox(
                    width: 78,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _yLabels
                          .map(
                            (label) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textLight,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      painter: _TrendPainter(
                        days: days,
                        todayIndex: todayIndex,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // X-axis labels — one per day column, aligned with plot points.
            Row(
              children: [
                const SizedBox(width: 78),
                Expanded(
                  child: Row(
                    children: List.generate(days.length, (i) {
                      final isToday = i == todayIndex;
                      return Expanded(
                        child: Center(
                          child: Text(
                            _initialFor(days[i].dateTime),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isToday
                                  ? AppColors.textOnYellow
                                  : AppColors.textLight,
                            ),
                          ),
                        ),
                      );
                    }),
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

class _TrendPainter extends CustomPainter {
  final List<MealTrendDay> days;
  final int todayIndex;

  _TrendPainter({required this.days, required this.todayIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    final w = size.width;
    final h = size.height;
    const n = 7;

    // Grid lines (4 — one per Y-label level)
    final gridPaint = Paint()
      ..color = AppColors.surfaceLight
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = (h * i) / 3;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Compute per-column center X positions and Y positions
    final centers = <Offset?>[];
    for (var i = 0; i < days.length && i < n; i++) {
      final cx = w * (2 * i + 1) / (2 * n);
      final level = days[i].level;
      if (level == null) {
        centers.add(null);
      } else {
        final cy = h * (1.0 - level.fraction);
        centers.add(Offset(cx, cy));
      }
    }

    // Today's vertical highlight track (faint gold pillar)
    if (todayIndex >= 0 && todayIndex < n) {
      final todayX = w * (2 * todayIndex + 1) / (2 * n);
      final pillarPaint = Paint()
        ..color = AppColors.primaryLemon.withValues(alpha: 0.35);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(todayX - 14, 0, 28, h),
          const Radius.circular(12),
        ),
        pillarPaint,
      );
    }

    // Build path through non-null contiguous segments
    final linePaint = Paint()
      ..color = AppColors.primaryLemonDark
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    Path? currentPath;
    Path? currentFill;
    for (var i = 0; i < centers.length; i++) {
      final p = centers[i];
      if (p == null) {
        if (currentPath != null) {
          canvas.drawPath(currentPath, linePaint);
          if (currentFill != null) _drawFill(canvas, currentFill, h);
          currentPath = null;
          currentFill = null;
        }
        continue;
      }
      if (currentPath == null) {
        currentPath = Path()..moveTo(p.dx, p.dy);
        currentFill = Path()
          ..moveTo(p.dx, h)
          ..lineTo(p.dx, p.dy);
      } else {
        currentPath.lineTo(p.dx, p.dy);
        currentFill!.lineTo(p.dx, p.dy);
      }
      // Close at end of array
      if (i == centers.length - 1) {
        canvas.drawPath(currentPath, linePaint);
        currentFill.lineTo(p.dx, h);
        currentFill.close();
        _drawFill(canvas, currentFill, h);
      }
    }

    // Points
    for (var i = 0; i < centers.length; i++) {
      final p = centers[i];
      if (p == null) continue;
      final isToday = i == todayIndex;
      if (isToday) {
        // White halo + larger gold dot for today
        canvas.drawCircle(
          p,
          7,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          p,
          5.5,
          Paint()..color = AppColors.primaryLemonDark,
        );
      } else {
        canvas.drawCircle(
          p,
          3.5,
          Paint()..color = AppColors.primaryLemonDark,
        );
        canvas.drawCircle(
          p,
          3.5,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  void _drawFill(Canvas canvas, Path fillPath, double h) {
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.primaryLemonDark.withValues(alpha: 0.18),
        AppColors.primaryLemonDark.withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromLTWH(0, 0, 1, h));
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) {
    if (old.todayIndex != todayIndex) return true;
    if (old.days.length != days.length) return true;
    for (var i = 0; i < days.length; i++) {
      if (old.days[i].level != days[i].level) return true;
    }
    return false;
  }
}
