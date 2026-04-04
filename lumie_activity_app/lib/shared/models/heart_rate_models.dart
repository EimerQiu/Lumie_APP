class HrDataPoint {
  final DateTime time;
  final int bpm;

  const HrDataPoint({required this.time, required this.bpm});
}

class HrBackfillRange {
  final DateTime start;
  final DateTime end;

  const HrBackfillRange({required this.start, required this.end});
}

enum HrSessionPointSource { realtime, backfillDetail, backfillHistory }

/// A single measurement during a live HR session with adaptive EMA smoothing.
class HrSessionPoint {
  final DateTime time;
  final int rawBpm;
  final double smoothedBpm; // Adaptive EMA-smoothed value
  final HrSessionPointSource source;

  const HrSessionPoint({
    required this.time,
    required this.rawBpm,
    required this.smoothedBpm,
    this.source = HrSessionPointSource.realtime,
  });
}
