import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/sleep_models.dart';
import '../../shared/models/ring_models.dart';
import '../../shared/models/heart_rate_models.dart';

/// Sleep service — reads from the backend and syncs ring data.
class SleepService {
  static final SleepService _instance = SleepService._internal();
  factory SleepService() => _instance;
  SleepService._internal();

  final AuthService _authService = AuthService();

  /// When the last ring sync completed, null if never synced this session.
  DateTime? lastSyncedAt;
  /// False if the last ring fetch timed out before the end-of-data marker.
  bool lastSyncWasComplete = true;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  // ─── Ring sync ────────────────────────────────────────────────────────────

  /// Upload raw sleep records fetched from the ring to the backend.
  ///
  /// Validity gates applied before upload:
  ///   • At least 180 continuous minutes (3 hours) of sleep
  ///   • At least some non-light stage data (confirms ring was worn, not sitting
  ///     on a table — motion-only detection without PPG produces all-light)
  ///
  /// [hrHistory] — HR readings from the past 24 hours (0x55 command). Used to
  /// compute the resting heart rate for each session window.  Pass an empty
  /// list when unavailable; resting_heart_rate will be 0 in that case.
  ///
  /// [isComplete] indicates whether the BLE fetch received the end-of-data
  /// marker; if false, records are still uploaded but [lastSyncWasComplete] is
  /// set to false so the UI can warn the user.
  Future<void> syncFromRingRecords(
    List<RingRawSleepRecord> records, {
    required bool isComplete,
    List<HrDataPoint> hrHistory = const [],
  }) async {
    lastSyncWasComplete = isComplete;

    if (records.isEmpty) {
      lastSyncedAt = DateTime.now();
      debugPrint('[Sleep] syncFromRingRecords: no records to upload');
      return;
    }

    // ── Validity filter ────────────────────────────────────────────────────
    // Minimum 3 continuous hours; must have at least some deep or REM data
    // (all-light with no body stages means ring is likely not being worn).
    final valid = records.where((r) {
      if (r.totalSleepMinutes < 180) {
        debugPrint('[Sleep] Skipping record: only ${r.totalSleepMinutes} min '
            '(< 180 min minimum)');
        return false;
      }
      final hasRealStages = r.deepMinutes > 0 || r.remMinutes > 0;
      if (!hasRealStages) {
        debugPrint('[Sleep] Skipping record: all-light, no deep/REM — '
            'ring likely not worn');
        return false;
      }
      return true;
    }).toList();

    if (valid.isEmpty) {
      lastSyncedAt = DateTime.now();
      debugPrint('[Sleep] syncFromRingRecords: all records failed validity '
          'checks — nothing to upload');
      return;
    }

    final sessions = valid
        .map((r) => _ringRecordToPayload(r, hrHistory))
        .toList();

    try {
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/sleep/sync'),
        headers: _headers,
        body: json.encode({'sessions': sessions}),
      ).timeout(const Duration(seconds: 10));
      lastSyncedAt = DateTime.now();
      debugPrint('[Sleep] syncFromRingRecords: uploaded ${sessions.length} '
          'session(s), complete=$isComplete');
    } catch (e) {
      debugPrint('[Sleep] syncFromRingRecords: upload error: $e');
      // Best-effort — data will be re-uploaded on next sync
    }
  }

  Map<String, dynamic> _ringRecordToPayload(
    RingRawSleepRecord r,
    List<HrDataPoint> hrHistory,
  ) {
    final total = r.totalSleepMinutes;
    final stages = <Map<String, dynamic>>[];

    if (r.lightMinutes > 0) {
      stages.add({
        'stage': 'light',
        'duration_minutes': r.lightMinutes,
        'percentage': r.lightMinutes / total * 100,
      });
    }
    if (r.deepMinutes > 0) {
      stages.add({
        'stage': 'deep',
        'duration_minutes': r.deepMinutes,
        'percentage': r.deepMinutes / total * 100,
      });
    }
    if (r.remMinutes > 0) {
      stages.add({
        'stage': 'rem',
        'duration_minutes': r.remMinutes,
        'percentage': r.remMinutes / total * 100,
      });
    }

    // Quality score: weighted by healthy stage ratios
    //   Deep target 25% → 40 pts max
    //   REM target 25%  → 35 pts max
    //   Duration 8 hrs  → 25 pts max
    final deepPct = r.deepMinutes / total * 100;
    final remPct = r.remMinutes / total * 100;
    final quality = (deepPct / 25.0).clamp(0.0, 1.0) * 40 +
        (remPct / 25.0).clamp(0.0, 1.0) * 35 +
        (total / 480.0).clamp(0.0, 1.0) * 25;

    // Resting HR: median of 10-minute windowed averages within the sleep window
    final rhr = _computeRestingHr(hrHistory, r.sessionStart, r.sessionEnd);

    return {
      'session_id': '${r.sessionStart.millisecondsSinceEpoch}',
      'bedtime': r.sessionStart.toIso8601String(),
      'wake_time': r.sessionEnd.toIso8601String(),
      'total_sleep_minutes': total,
      'time_awake_minutes': r.awakeMinutes,
      'stages': stages,
      'resting_heart_rate': rhr,
      'sleep_quality_score': quality,
    };
  }

  /// Compute resting heart rate from HR readings that fall within [start, end].
  ///
  /// Algorithm:
  ///   1. Filter readings to the sleep session window.
  ///   2. Group into 10-minute buckets and average each bucket.
  ///   3. Return the median of the bucket averages.
  ///
  /// Returns 0 if there are fewer than 2 readings (not enough to be meaningful).
  int _computeRestingHr(
    List<HrDataPoint> hrHistory,
    DateTime start,
    DateTime end,
  ) {
    // Readings within the session window with plausible sleep-range HR (35–120)
    final readings = hrHistory
        .where((p) =>
            !p.time.isBefore(start) &&
            !p.time.isAfter(end) &&
            p.bpm >= 35 &&
            p.bpm <= 120)
        .toList();

    if (readings.length < 2) return 0;

    // Bucket readings into 10-minute windows from session start
    final buckets = <int, List<int>>{}; // bucket index → list of bpm values
    for (final p in readings) {
      final minutesIn = p.time.difference(start).inMinutes;
      final bucket = minutesIn ~/ 10;
      buckets.putIfAbsent(bucket, () => []).add(p.bpm);
    }

    if (buckets.isEmpty) return 0;

    // Average each bucket, then take the median of bucket averages
    final bucketAverages = buckets.values
        .map((bpms) => bpms.reduce((a, b) => a + b) / bpms.length)
        .toList()
      ..sort();

    final n = bucketAverages.length;
    final median = n.isOdd
        ? bucketAverages[n ~/ 2]
        : (bucketAverages[n ~/ 2 - 1] + bucketAverages[n ~/ 2]) / 2;

    // Suppress invalid values
    if (median < 35 || median > 120) return 0;

    debugPrint('[Sleep] Resting HR for session $start: '
        '${median.round()} bpm (${readings.length} readings, '
        '${buckets.length} windows)');
    return median.round();
  }


  // ─── Read endpoints ───────────────────────────────────────────────────────

  /// Get the most recent sleep session.
  Future<SleepSession?> getLatestSleep() async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/sleep/latest'),
      headers: _headers,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data != null ? SleepSession.fromJson(data) : null;
    }
    return null;
  }

  /// Get sleep sessions for a date range.
  Future<List<SleepSession>> getSleepHistory({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.baseUrl}/sleep/history'
        '?start=${startDate.toIso8601String()}&end=${endDate.toIso8601String()}',
      ),
      headers: _headers,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;
      return data.map((s) => SleepSession.fromJson(s)).toList();
    }
    return [];
  }

  /// Get sleep summary for a date range.
  Future<SleepSummary?> getSleepSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.baseUrl}/sleep/summary'
        '?start=${startDate.toIso8601String()}&end=${endDate.toIso8601String()}',
      ),
      headers: _headers,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      return SleepSummary.fromJson(json.decode(response.body));
    }
    return null;
  }

  /// Get sleep target based on user age.
  Future<SleepTarget> getSleepTarget() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/sleep/target'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return SleepTarget.fromJson(json.decode(response.body));
      }
    } catch (_) {}

    // Sensible default for teens if backend is unreachable
    return const SleepTarget(
      minDuration: Duration(hours: 8),
      maxDuration: Duration(hours: 10),
      targetDuration: Duration(hours: 9),
      targetStagePercentages: {
        SleepStage.light: 45.0,
        SleepStage.deep: 25.0,
        SleepStage.rem: 25.0,
      },
    );
  }
}
