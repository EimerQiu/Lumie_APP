import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'auth_service.dart';
import 'sleep_service.dart';
import 'steps_service.dart';
import '../../shared/models/ring_models.dart';
import '../../shared/models/heart_rate_models.dart';

enum RingSyncPhase { idle, syncing, done, failed }

class RingSyncStatus {
  final RingSyncPhase phase;
  final DateTime? lastSyncAt;
  final bool lastWasIncomplete;
  final String? error;

  const RingSyncStatus({
    this.phase = RingSyncPhase.idle,
    this.lastSyncAt,
    this.lastWasIncomplete = false,
    this.error,
  });

  bool get isSyncing => phase == RingSyncPhase.syncing;
}

/// Orchestrates a full ring data sync (sleep + HR) whenever the ring connects.
///
/// Singleton ChangeNotifier — add to MultiProvider so widgets can observe it.
/// Call [triggerSync] with BLE-fetch callbacks to start a background sync.
class RingSyncService extends ChangeNotifier {
  static final RingSyncService _instance = RingSyncService._internal();
  factory RingSyncService() => _instance;
  RingSyncService._internal();

  RingSyncStatus _status = const RingSyncStatus();
  bool _syncing = false;

  RingSyncStatus get status => _status;

  static const _lastSyncKey = 'ring_last_sync_at';
  static const _lastIncompleteKey = 'ring_last_sync_incomplete';

  /// Load persisted sync timestamp from SharedPreferences on app start.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_lastSyncKey);
    final incomplete = prefs.getBool(_lastIncompleteKey) ?? false;
    if (ts != null) {
      _status = RingSyncStatus(
        phase: RingSyncPhase.done,
        lastSyncAt: DateTime.parse(ts),
        lastWasIncomplete: incomplete,
      );
      notifyListeners();
    }
  }

  /// Trigger a background sync from the ring.
  ///
  /// Callbacks avoid a circular import with RingProvider.
  /// [fetchSteps] and [fetchHrv] are optional.
  /// Returns immediately — sync runs asynchronously.
  void triggerSync({
    required Future<({List<RingRawSleepRecord> records, bool isComplete})>
        Function() fetchSleep,
    required Future<List<HrDataPoint>> Function() fetchHr,
    Future<List<RingRawDailySteps>> Function()? fetchSteps,
    Future<List<RingRawHrvRecord>> Function()? fetchHrv,
    Future<List<HrDataPoint>> Function()? fetchHrDetails,
    Future<List<RingRawTemperatureRecord>> Function()? fetchTemperature,
    Future<List<RingRawSpo2Record>> Function()? fetchSpo2,
  }) {
    if (_syncing) return;
    _runSync(
      fetchSleep: fetchSleep,
      fetchHr: fetchHr,
      fetchSteps: fetchSteps,
      fetchHrv: fetchHrv,
      fetchHrDetails: fetchHrDetails,
      fetchTemperature: fetchTemperature,
      fetchSpo2: fetchSpo2,
    );
  }

  Future<void> _runSync({
    required Future<({List<RingRawSleepRecord> records, bool isComplete})>
        Function() fetchSleep,
    required Future<List<HrDataPoint>> Function() fetchHr,
    Future<List<RingRawDailySteps>> Function()? fetchSteps,
    Future<List<RingRawHrvRecord>> Function()? fetchHrv,
    Future<List<HrDataPoint>> Function()? fetchHrDetails,
    Future<List<RingRawTemperatureRecord>> Function()? fetchTemperature,
    Future<List<RingRawSpo2Record>> Function()? fetchSpo2,
  }) async {
    _syncing = true;
    _status = RingSyncStatus(
      phase: RingSyncPhase.syncing,
      lastSyncAt: _status.lastSyncAt,
      lastWasIncomplete: _status.lastWasIncomplete,
    );
    notifyListeners();

    // Only send records newer than 24 h before the previous sync (buffer for
    // sessions that may have spanned midnight during last sync).
    final cutoff = _status.lastSyncAt?.subtract(const Duration(hours: 24));
    bool anyIncomplete = false;

    try {
      // ── Sleep + HR (fetched together so HR can be passed to sleep for resting HR) ──
      final (:records, :isComplete) = await fetchSleep();
      if (!isComplete) anyIncomplete = true;
      final sleepToSync = cutoff == null
          ? records
          : records.where((r) => r.sessionStart.isAfter(cutoff)).toList();

      final hrPoints = await fetchHr();
      final hrToSync = cutoff == null
          ? hrPoints
          : hrPoints.where((p) => p.time.isAfter(cutoff)).toList();

      if (sleepToSync.isNotEmpty) {
        await SleepService().syncFromRingRecords(
          sleepToSync,
          isComplete: isComplete,
          hrHistory: hrPoints,
        );
      }

      if (hrToSync.isNotEmpty) {
        await _uploadHrReadings(hrToSync);
      }

      // ── Steps ──────────────────────────────────────────────────────────────
      if (fetchSteps != null) {
        final stepRecords = await fetchSteps();
        if (stepRecords.isNotEmpty) {
          await StepsService().syncFromRingRecords(stepRecords);
        }
      }

      // ── HRV / Stress / Blood Pressure ──────────────────────────────────────
      if (fetchHrv != null) {
        final hrvRecords = await fetchHrv();
        final hrvToSync = cutoff == null
            ? hrvRecords
            : hrvRecords.where((r) => r.timestamp.isAfter(cutoff)).toList();
        if (hrvToSync.isNotEmpty) {
          await _uploadHrvReadings(hrvToSync);
        }
      }

      // ── HR Details (0x54) ─────────────────────────────────────────────────
      if (fetchHrDetails != null) {
        final hrDetailPoints = await fetchHrDetails();
        final hrDetailToSync = cutoff == null
            ? hrDetailPoints
            : hrDetailPoints.where((p) => p.time.isAfter(cutoff)).toList();
        if (hrDetailToSync.isNotEmpty) {
          await _uploadHrReadings(hrDetailToSync);
        }
      }

      // ── Temperature (0x62) ────────────────────────────────────────────────
      if (fetchTemperature != null) {
        final tempRecords = await fetchTemperature();
        final tempToSync = cutoff == null
            ? tempRecords
            : tempRecords.where((r) => r.timestamp.isAfter(cutoff)).toList();
        if (tempToSync.isNotEmpty) {
          await _uploadTemperatureReadings(tempToSync);
        }
      }

      // ── SpO2 (0x66) ───────────────────────────────────────────────────────
      if (fetchSpo2 != null) {
        final spo2Records = await fetchSpo2();
        final spo2ToSync = cutoff == null
            ? spo2Records
            : spo2Records.where((r) => r.timestamp.isAfter(cutoff)).toList();
        if (spo2ToSync.isNotEmpty) {
          await _uploadSpo2Readings(spo2ToSync);
        }
      }

      // ── Persist sync timestamp ─────────────────────────────────────────────
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncKey, now.toIso8601String());
      await prefs.setBool(_lastIncompleteKey, anyIncomplete);

      _status = RingSyncStatus(
        phase: RingSyncPhase.done,
        lastSyncAt: now,
        lastWasIncomplete: anyIncomplete,
      );
    } catch (e) {
      debugPrint('[RingSync] Sync failed: $e');
      _status = RingSyncStatus(
        phase: RingSyncPhase.failed,
        lastSyncAt: _status.lastSyncAt,
        lastWasIncomplete: _status.lastWasIncomplete,
        error: e.toString(),
      );
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _uploadHrReadings(List<HrDataPoint> points) async {
    final token = AuthService().token;
    if (token == null) return;

    final payload = {
      'readings': points
          .map((p) => {
                'timestamp': p.time.toUtc().toIso8601String(),
                'bpm': p.bpm,
              })
          .toList(),
    };

    await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}/hr/sync'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(payload),
        )
        .timeout(ApiConstants.receiveTimeout);
  }

  Future<void> _uploadHrvReadings(List<RingRawHrvRecord> records) async {
    final token = AuthService().token;
    if (token == null) return;

    final payload = {
      'readings': records
          .map((r) => {
                'timestamp': r.timestamp.toUtc().toIso8601String(),
                'hrv_ms': r.hrvMs,
                'heart_rate_bpm': r.heartRateBpm,
                'fatigue': r.fatigue,
                'systolic_mmhg': r.systolicMmhg,
                'diastolic_mmhg': r.diastolicMmhg,
              })
          .toList(),
    };

    await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}/hrv/sync'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(payload),
        )
        .timeout(ApiConstants.receiveTimeout);
  }

  Future<void> _uploadTemperatureReadings(List<RingRawTemperatureRecord> records) async {
    final token = AuthService().token;
    if (token == null) return;

    final payload = {
      'readings': records
          .map((r) => {
                'timestamp': r.timestamp.toUtc().toIso8601String(),
                'temp1_c': r.temp1C,
                'temp2_c': r.temp2C,
                'temp3_c': r.temp3C,
              })
          .toList(),
    };

    await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}/temperature/sync'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(payload),
        )
        .timeout(ApiConstants.receiveTimeout);
  }

  Future<void> _uploadSpo2Readings(List<RingRawSpo2Record> records) async {
    final token = AuthService().token;
    if (token == null) return;

    final payload = {
      'readings': records
          .map((r) => {
                'timestamp': r.timestamp.toUtc().toIso8601String(),
                'spo2_percent': r.spo2Percent,
              })
          .toList(),
    };

    await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}/spo2/sync'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(payload),
        )
        .timeout(ApiConstants.receiveTimeout);
  }
}
