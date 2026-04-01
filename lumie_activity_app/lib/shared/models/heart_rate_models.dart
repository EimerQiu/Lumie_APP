class HrDataPoint {
  final DateTime time;
  final int bpm;

  const HrDataPoint({required this.time, required this.bpm});
}

/// A single measurement during a live HR session with adaptive EMA smoothing.
class HrSessionPoint {
  final DateTime time;
  final int rawBpm;
  final double smoothedBpm; // Adaptive EMA-smoothed value

  const HrSessionPoint({
    required this.time,
    required this.rawBpm,
    required this.smoothedBpm,
  });
}
