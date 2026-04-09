class HrDataPoint {
  final DateTime time;
  final int bpm;

  const HrDataPoint({required this.time, required this.bpm});
}

// ── Saved session models (from backend) ───────────────────────────────────────

class HrSessionSummary {
  final String sessionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final int avgBpm;
  final int minBpm;
  final int maxBpm;
  final int readingCount;
  final DateTime createdAt;

  const HrSessionSummary({
    required this.sessionId,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.avgBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.readingCount,
    required this.createdAt,
  });

  static DateTime _parseTs(String s) {
    if (!s.endsWith('Z') && !s.contains('+')) s += 'Z';
    return DateTime.parse(s);
  }

  factory HrSessionSummary.fromJson(Map<String, dynamic> j) => HrSessionSummary(
        sessionId: j['session_id'] as String,
        startedAt: _parseTs(j['started_at'] as String),
        endedAt: _parseTs(j['ended_at'] as String),
        durationSeconds: j['duration_seconds'] as int,
        avgBpm: j['avg_bpm'] as int,
        minBpm: j['min_bpm'] as int,
        maxBpm: j['max_bpm'] as int,
        readingCount: j['reading_count'] as int,
        createdAt: _parseTs(j['created_at'] as String),
      );
}

class HrSessionTimeseries {
  final String sessionId;
  final List<HrSessionPoint> readings; // flattened + sorted by time

  const HrSessionTimeseries({required this.sessionId, required this.readings});

  static DateTime _parseTs(String s) {
    if (!s.endsWith('Z') && !s.contains('+')) s += 'Z';
    return DateTime.parse(s);
  }

  factory HrSessionTimeseries.fromJson(Map<String, dynamic> j) {
    final points = <HrSessionPoint>[];
    for (final bucket in (j['buckets'] as List<dynamic>)) {
      final bucketStart = _parseTs(bucket['bucket_start'] as String);
      for (final r in (bucket['readings'] as List<dynamic>)) {
        final t = r['t'] as int;
        final bpm = r['bpm'] as int;
        points.add(HrSessionPoint(
          time: bucketStart.add(Duration(seconds: t)),
          rawBpm: bpm,
          smoothedBpm: bpm.toDouble(),
          source: HrSessionPointSource.backfillDetail,
        ));
      }
    }
    points.sort((a, b) => a.time.compareTo(b.time));
    return HrSessionTimeseries(
      sessionId: j['session_id'] as String,
      readings: points,
    );
  }
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
