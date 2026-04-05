import 'package:flutter/material.dart';
import '../../../shared/models/sleep_models.dart';

/// Colors for each sleep stage (amber/yellow palette, lightest → deepest).
class SleepStageColors {
  SleepStageColors._();

  static const Color awake = Color(0xFFFFFFFF);
  static const Color light = Color(0xFFFFF9C4);
  static const Color rem   = Color(0xFFF9A825);
  static const Color deep  = Color(0xFFE65100);

  static Color forStage(SleepStage stage) {
    switch (stage) {
      case SleepStage.awake: return awake;
      case SleepStage.light: return light;
      case SleepStage.rem:   return rem;
      case SleepStage.deep:  return deep;
    }
  }
}

/// Oura-style horizontal sleep timeline.
///
/// Shows proportional colored blocks for each stage segment.  Tapping a block
/// reveals an inline tooltip with the stage name and duration.  Falls back to
/// synthesising segments from aggregate stage totals when [session] has no
/// [SleepSession.timelineSegments].
class SleepTimelineChart extends StatefulWidget {
  final SleepSession session;

  const SleepTimelineChart({super.key, required this.session});

  @override
  State<SleepTimelineChart> createState() => _SleepTimelineChartState();
}

class _SleepTimelineChartState extends State<SleepTimelineChart> {
  int? _tappedIndex;

  List<SleepTimelineSegment> get _segments {
    if (widget.session.timelineSegments.isNotEmpty) {
      return widget.session.timelineSegments;
    }
    // Fallback: synthesise from aggregate stage totals.
    // Order: awake → light → deep → rem (conventional sleep architecture).
    final result = <SleepTimelineSegment>[];
    int offset = 0;

    final stageOrder = [
      SleepStage.awake,
      SleepStage.light,
      SleepStage.deep,
      SleepStage.rem,
    ];

    for (final stage in stageOrder) {
      int mins;
      if (stage == SleepStage.awake) {
        mins = widget.session.timeAwake.inMinutes;
      } else {
        mins = widget.session.getStageDuration(stage).inMinutes;
      }
      if (mins > 0) {
        result.add(SleepTimelineSegment(
          stage: stage,
          startOffsetMinutes: offset,
          durationMinutes: mins,
        ));
        offset += mins;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _segments;
    final totalMinutes = segments.fold(0, (sum, s) => sum + s.durationMinutes);
    if (totalMinutes == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Timeline bar ──────────────────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 44,
            child: Row(
              children: segments.asMap().entries.map((entry) {
                final idx = entry.key;
                final seg = entry.value;
                final isFirst = idx == 0;
                final isLast  = idx == segments.length - 1;
                final isTapped = _tappedIndex == idx;

                return Expanded(
                  flex: seg.durationMinutes,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(
                      () => _tappedIndex = isTapped ? null : idx,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: SleepStageColors.forStage(seg.stage),
                        border: seg.stage == SleepStage.awake
                            ? Border.all(color: const Color(0xFFE0E0E0), width: 0.5)
                            : null,
                        borderRadius: BorderRadius.horizontal(
                          left:  isFirst ? const Radius.circular(8) : Radius.zero,
                          right: isLast  ? const Radius.circular(8) : Radius.zero,
                        ),
                        boxShadow: isTapped
                            ? [BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )]
                            : null,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── Tooltip ───────────────────────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _tappedIndex != null && _tappedIndex! < segments.length
              ? _TooltipBubble(segment: segments[_tappedIndex!])
              : const SizedBox.shrink(),
        ),

        const SizedBox(height: 8),

        // ── Start / end time labels ───────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _timeLabel(_formatTime(widget.session.bedtime)),
            _timeLabel(_formatTime(widget.session.wakeTime)),
          ],
        ),
      ],
    );
  }

  Widget _timeLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 11, color: Color(0xFFA8A29E)),
      );

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }
}

class _TooltipBubble extends StatelessWidget {
  final SleepTimelineSegment segment;

  const _TooltipBubble({required this.segment});

  @override
  Widget build(BuildContext context) {
    final color = SleepStageColors.forStage(segment.stage);
    final label = _stageLabel(segment.stage);
    final duration = _formatDuration(segment.durationMinutes);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1917),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: segment.stage == SleepStage.awake
                    ? Border.all(color: Colors.white38, width: 1)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$label · $duration',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stageLabel(SleepStage stage) {
    switch (stage) {
      case SleepStage.awake: return 'Awake';
      case SleepStage.light: return 'Light Sleep';
      case SleepStage.rem:   return 'REM Sleep';
      case SleepStage.deep:  return 'Deep Sleep';
    }
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
