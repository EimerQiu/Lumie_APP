import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/sleep_models.dart';
import '../../shared/models/ring_models.dart';

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
  /// [isComplete] indicates whether the BLE fetch received the end-of-data
  /// marker; if false, records are still uploaded (they're individually valid)
  /// but [lastSyncWasComplete] is set to false so the UI can warn the user.
  Future<void> syncFromRingRecords(
    List<RingRawSleepRecord> records, {
    required bool isComplete,
  }) async {
    lastSyncWasComplete = isComplete;

    if (records.isEmpty) {
      lastSyncedAt = DateTime.now();
      return;
    }

    final sessions = records
        .where((r) => r.totalSleepMinutes > 0)
        .map((r) => _ringRecordToPayload(r))
        .toList();

    if (sessions.isEmpty) {
      lastSyncedAt = DateTime.now();
      return;
    }

    try {
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/sleep/sync'),
        headers: _headers,
        body: json.encode({'sessions': sessions}),
      ).timeout(const Duration(seconds: 10));
      lastSyncedAt = DateTime.now();
    } catch (e) {
      // Best-effort — data will be re-uploaded on next sync
    }
  }

  Map<String, dynamic> _ringRecordToPayload(RingRawSleepRecord r) {
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

    return {
      'session_id': '${r.sessionStart.millisecondsSinceEpoch}',
      'bedtime': r.sessionStart.toIso8601String(),
      'wake_time': r.sessionEnd.toIso8601String(),
      'total_sleep_minutes': total,
      'time_awake_minutes': r.awakeMinutes,
      'stages': stages,
      'resting_heart_rate': 0,
      'sleep_quality_score': quality,
    };
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
