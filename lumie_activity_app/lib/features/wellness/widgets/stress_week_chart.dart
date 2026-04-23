import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/stress_models.dart';

/// 7-day bar chart showing daily stress scores (0–100, higher = better).
///
/// Each bar's height represents the score, colored by the day's average zone.
/// A reference line at 65 marks the "Relaxed and above" threshold.
/// Tapping a bar shows that day's zone time breakdown.
class StressWeekChart extends StatefulWidget {
  final List<StressDaySummary> days;
  final void Function(StressDaySummary day)? onDayTap;
  final double height;

  const StressWeekChart({
    super.key,
    required this.days,
    this.onDayTap,
    this.height = 160,
  });

  @override
  State<StressWeekChart> createState() => _StressWeekChartState();
}

class _StressWeekChartState extends State<StressWeekChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) {
      return SizedBox(height: widget.height);
    }

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barAreaHeight = constraints.maxHeight - 20; // 20 for day labels
          return Stack(
            children: [
              // Reference line at score 65
              Positioned(
                left: 0,
                right: 0,
                top: barAreaHeight * (1 - 65 / 100),
                child: Row(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        size: Size(double.infinity, 1),
                        painter: _DashedLinePainter(
                          color: AppColors.textLight.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Bars
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(widget.days.length, (i) {
                  final day = widget.days[i];
                  final isSelected = _selectedIndex == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() =>
                            _selectedIndex = _selectedIndex == i ? null : i);
                        widget.onDayTap?.call(day);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Score label above bar when selected
                            if (isSelected && day.hasData) ...[
                              _buildDayTooltip(day),
                              const SizedBox(height: 2),
                            ],
                            // Score bar
                            day.hasData
                                ? _buildScoreBar(day, barAreaHeight, isSelected)
                                : _buildEmptyBar(barAreaHeight),
                            const SizedBox(height: 4),
                            // Day label
                            Text(
                              _dayLabel(day.date),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight:
                                    isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.textPrimary
                                    : AppColors.textLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScoreBar(
      StressDaySummary day, double maxHeight, bool selected) {
    final barHeight = (day.score / 100 * maxHeight).clamp(4.0, maxHeight);
    final zoneColor = day.averageZone.chartColor;
    final borderColor = day.averageZone == StressZone.restored
        ? AppColors.surfaceLight
        : zoneColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: barHeight,
      decoration: BoxDecoration(
        color: zoneColor,
        borderRadius: BorderRadius.circular(6),
        border: selected
            ? Border.all(color: AppColors.primaryLemonDark, width: 2)
            : day.averageZone == StressZone.restored
                ? Border.all(color: borderColor, width: 0.5)
                : null,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: zoneColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildEmptyBar(double maxHeight) {
    return Container(
      height: maxHeight * 0.15,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Center(
        child: Icon(Icons.remove, size: 12, color: AppColors.textLight),
      ),
    );
  }

  Widget _buildDayTooltip(StressDaySummary day) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.score}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          _tooltipRow('Stressed', day.stressedTime, StressZone.stressed),
          _tooltipRow('Engaged', day.engagedTime, StressZone.engaged),
          _tooltipRow('Relaxed', day.relaxedTime, StressZone.relaxed),
          _tooltipRow('Restored', day.restoredTime, StressZone.restored),
        ],
      ),
    );
  }

  Widget _tooltipRow(String label, Duration duration, StressZone zone) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: zone.chartColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          _formatDuration(duration),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return 'Today';
    final diff = today.difference(d).inDays;
    if (diff == 1) return 'Yest';

    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }
}

/// Draws a dashed horizontal line.
class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const gap = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
