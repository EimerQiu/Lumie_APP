import 'package:flutter/material.dart';
import '../../../shared/models/stress_models.dart';
import '../../../core/theme/app_colors.dart';

/// Continuous area chart showing stress zones throughout the day.
///
/// Colors fill under a smooth curve based on the zone at each 15-min reading.
/// Exercise gaps are grey; no-data gaps are empty.
/// Set [compact] to true for the dashboard mini version (no labels/interaction).
class StressTimelineChart extends StatefulWidget {
  final List<StressReading> readings;
  final double height;
  final bool compact;

  const StressTimelineChart({
    super.key,
    required this.readings,
    this.height = 180,
    this.compact = false,
  });

  @override
  State<StressTimelineChart> createState() => _StressTimelineChartState();
}

class _StressTimelineChartState extends State<StressTimelineChart> {
  int? _tooltipIndex;
  Offset? _tooltipPosition;

  @override
  Widget build(BuildContext context) {
    if (widget.readings.isEmpty) {
      return SizedBox(height: widget.height);
    }

    final chart = CustomPaint(
      size: Size(double.infinity, widget.height),
      painter: _TimelinePainter(
        readings: widget.readings,
        compact: widget.compact,
      ),
    );

    if (widget.compact) return chart;

    // Interactive version with long-press tooltip
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onLongPressStart: (d) => _showTooltip(d.localPosition),
          onLongPressMoveUpdate: (d) => _showTooltip(d.localPosition),
          onLongPressEnd: (_) => _hideTooltip(),
          child: chart,
        ),
        if (_tooltipIndex != null && _tooltipPosition != null)
          _buildTooltip(),
      ],
    );
  }

  void _showTooltip(Offset position) {
    if (widget.readings.isEmpty) return;
    final chartWidth = context.size?.width ?? 300;
    final labelHeight = widget.compact ? 0.0 : 24.0;
    final effectiveWidth = chartWidth;

    final startTime = widget.readings.first.time;
    final endTime = widget.readings.last.time;
    final totalMin = endTime.difference(startTime).inMinutes;
    if (totalMin <= 0) return;

    // Map position to reading index
    final fraction = (position.dx / effectiveWidth).clamp(0.0, 1.0);
    final targetMin = (fraction * totalMin).round();
    int closest = 0;
    int closestDist = 999999;
    for (int i = 0; i < widget.readings.length; i++) {
      final dist = (widget.readings[i].time.difference(startTime).inMinutes - targetMin).abs();
      if (dist < closestDist) {
        closestDist = dist;
        closest = i;
      }
    }

    setState(() {
      _tooltipIndex = closest;
      _tooltipPosition = Offset(
        position.dx.clamp(60, chartWidth - 60),
        widget.height - labelHeight - 50,
      );
    });
  }

  void _hideTooltip() {
    setState(() {
      _tooltipIndex = null;
      _tooltipPosition = null;
    });
  }

  Widget _buildTooltip() {
    final reading = widget.readings[_tooltipIndex!];
    final time = reading.time.toLocal();
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final timeStr = '$h12:$minute $amPm';

    String label;
    Color color;
    if (reading.type == StressSlotType.exercise) {
      label = 'Exercise';
      color = AppColors.textSecondary;
    } else if (reading.type == StressSlotType.noData) {
      label = 'No data';
      color = AppColors.textLight;
    } else {
      label = reading.zone?.label ?? '—';
      color = reading.zone?.displayColor ?? AppColors.textSecondary;
    }

    return Positioned(
      left: _tooltipPosition!.dx - 52,
      top: _tooltipPosition!.dy - 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeStr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color == AppColors.textSecondary ? Colors.white70 : color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Custom painter ──────────────────────────────────────────────────────────

class _TimelinePainter extends CustomPainter {
  final List<StressReading> readings;
  final bool compact;

  _TimelinePainter({required this.readings, required this.compact});

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.length < 2) return;

    final labelHeight = compact ? 0.0 : 24.0;
    final chartRect = Rect.fromLTWH(0, 0, size.width, size.height - labelHeight);

    final startTime = readings.first.time;
    final endTime = readings.last.time;
    final totalMin = endTime.difference(startTime).inMinutes;
    if (totalMin <= 0) return;

    // Build (x, y, zone, type) for each reading
    final points = <_ChartPoint>[];
    for (final r in readings) {
      final elapsed = r.time.difference(startTime).inMinutes;
      final x = (elapsed / totalMin) * chartRect.width;

      double y;
      if (r.type == StressSlotType.zone && r.zone != null) {
        // Add slight deterministic jitter for organic feel
        final jitter = (r.time.minute * 7 + r.time.hour * 13) % 20 / 100.0 - 0.1;
        final value = (r.zone!.chartValue + jitter * 0.15).clamp(0.05, 1.0);
        y = chartRect.bottom - value * chartRect.height;
      } else {
        y = chartRect.bottom;
      }
      points.add(_ChartPoint(x: x, y: y, reading: r));
    }

    // Draw filled segments
    for (int i = 0; i < points.length - 1; i++) {
      final p = points[i];
      final pNext = points[i + 1];
      final r = p.reading;

      if (r.type == StressSlotType.noData) continue;

      Color fillColor;
      if (r.type == StressSlotType.exercise) {
        fillColor = const Color(0xFFE0E0E0);
      } else {
        fillColor = r.zone!.chartColor.withValues(alpha: 0.55);
      }

      // Smooth area segment using cubic bezier
      final midX = (p.x + pNext.x) / 2;
      final areaPath = Path()
        ..moveTo(p.x, chartRect.bottom)
        ..lineTo(p.x, p.y)
        ..cubicTo(midX, p.y, midX, pNext.y, pNext.x, pNext.y)
        ..lineTo(pNext.x, chartRect.bottom)
        ..close();

      canvas.drawPath(areaPath, Paint()..color = fillColor);
    }

    // Draw smooth curve line on top
    final curvePath = Path();
    bool started = false;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.reading.type == StressSlotType.noData) {
        started = false;
        continue;
      }
      if (!started) {
        curvePath.moveTo(p.x, p.y);
        started = true;
      } else {
        final prev = points[i - 1];
        final midX = (prev.x + p.x) / 2;
        curvePath.cubicTo(midX, prev.y, midX, p.y, p.x, p.y);
      }
    }
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 1.5 : 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Draw baseline
    canvas.drawLine(
      Offset(0, chartRect.bottom),
      Offset(chartRect.width, chartRect.bottom),
      Paint()..color = AppColors.surfaceLight,
    );

    // Draw time labels
    if (!compact) {
      _drawTimeLabels(canvas, size, chartRect, startTime, totalMin);
    }
  }

  void _drawTimeLabels(
    Canvas canvas,
    Size size,
    Rect chartRect,
    DateTime startTime,
    int totalMin,
  ) {
    final labelY = chartRect.bottom + 8;

    // Determine hour interval based on total duration
    final totalHours = totalMin / 60;
    final hourStep = totalHours > 12 ? 3 : (totalHours > 6 ? 2 : 1);

    // Find first whole hour after start
    var cursor = DateTime(
      startTime.year,
      startTime.month,
      startTime.day,
      startTime.hour + 1,
    );

    while (cursor.difference(startTime).inMinutes < totalMin) {
      if (cursor.hour % hourStep == 0) {
        final elapsed = cursor.difference(startTime).inMinutes;
        final x = (elapsed / totalMin) * chartRect.width;

        // Draw tick
        canvas.drawLine(
          Offset(x, chartRect.bottom),
          Offset(x, chartRect.bottom + 3),
          Paint()..color = AppColors.textLight,
        );

        // Draw label
        final hour = cursor.toLocal().hour;
        final amPm = hour >= 12 ? 'PM' : 'AM';
        final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        final text = '$h12 $amPm';

        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(
              color: AppColors.textLight,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        tp.paint(canvas, Offset(x - tp.width / 2, labelY));
      }
      cursor = cursor.add(const Duration(hours: 1));
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.readings != readings || old.compact != compact;
}

class _ChartPoint {
  final double x;
  final double y;
  final StressReading reading;

  const _ChartPoint({required this.x, required this.y, required this.reading});
}
