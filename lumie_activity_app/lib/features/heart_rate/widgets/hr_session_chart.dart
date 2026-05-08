import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/heart_rate_models.dart';

/// Reusable line chart for a list of HR session readings.
///
/// Used by the live measurement screen and the saved-session detail screen.
/// [backfillRanges] is optional — only the live screen passes them to shade
/// the reconnection gap segments in amber.
class HrSessionChart extends StatelessWidget {
  final List<HrSessionPoint> readings;
  final List<HrBackfillRange> backfillRanges;

  const HrSessionChart({
    super.key,
    required this.readings,
    this.backfillRanges = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (readings.length < 2) return const SizedBox.shrink();

    final origin = readings.first.time;
    final spots = readings.map((p) {
      final secs = p.time.difference(origin).inSeconds.toDouble();
      return FlSpot(secs, p.smoothedBpm);
    }).toList();

    final bpms = readings.map((e) => e.smoothedBpm);
    final minBpm = bpms.reduce((a, b) => a < b ? a : b);
    final maxBpm = bpms.reduce((a, b) => a > b ? a : b);
    final yMin = ((minBpm - 10).clamp(30, 200)).toDouble();
    final yMax = ((maxBpm + 10).clamp(50, 250)).toDouble();
    final totalSecs = spots.last.x;
    double maxGapSec = 0;
    for (var i = 1; i < spots.length; i++) {
      final gap = spots[i].x - spots[i - 1].x;
      if (gap > maxGapSec) maxGapSec = gap;
    }
    final hasLargeTimeGap = maxGapSec >= 20;

    final verticalAnnotations = backfillRanges
        .map((range) {
          final x1 = range.start.difference(origin).inMilliseconds / 1000.0;
          final x2 = range.end.difference(origin).inMilliseconds / 1000.0;
          return VerticalRangeAnnotation(
            x1: x1.clamp(0, totalSecs > 0 ? totalSecs : 1),
            x2: x2.clamp(0, totalSecs > 0 ? totalSecs : 1),
            color: Colors.amber.withValues(alpha: 0.12),
          );
        })
        .where((r) => r.x2 > r.x1)
        .toList();

    return LineChart(
      LineChartData(
        minY: yMin,
        maxY: yMax,
        minX: 0,
        maxX: totalSecs > 0 ? totalSecs : 1,
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: verticalAnnotations,
        ),
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (yMax - yMin) / 3,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.textLight.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: (yMax - yMin) / 3,
              getTitlesWidget: (value, _) => Text(
                '${value.toInt()}',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: _xInterval(totalSecs),
              getTitlesWidget: (value, meta) {
                final interval = _xInterval(totalSecs);
                // Prevent crowded right-edge labels like "6:00" and "6:06".
                if (value < totalSecs &&
                    (totalSecs - value) < (interval * 0.6)) {
                  return const SizedBox.shrink();
                }
                final m = (value ~/ 60).toString();
                final s = (value.toInt() % 60).toString().padLeft(2, '0');
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    '$m:$s',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            // Cubic curve can overshoot on sparse/uneven points (looks like loops).
            // Fall back to polyline when large gaps exist.
            isCurved: !hasLargeTimeGap,
            curveSmoothness: 0.3,
            preventCurveOverShooting: true,
            preventCurveOvershootingThreshold: 8,
            color: Colors.redAccent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.redAccent.withValues(alpha: 0.25),
                  Colors.redAccent.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItems: (spots) => spots.map((spot) {
              final m = spot.x.toInt() ~/ 60;
              final s = spot.x.toInt() % 60;
              return LineTooltipItem(
                '${spot.y.toInt()} BPM\n$m:${s.toString().padLeft(2, '0')}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  double _xInterval(double totalSecs) {
    if (totalSecs <= 120) return 30;
    if (totalSecs <= 600) return 120;
    if (totalSecs <= 1800) return 300;
    return 600;
  }
}
