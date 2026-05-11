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

enum RingSyncDataType { sleep, hr, steps, hrv, hrDetails, temperature, spo2 }

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
  static const _cursorPrefix = 'ring_sync_cursor_';
  static const _incompletePrefix = 'ring_sync_incomplete_';

  /// Skip a major sync if the last successful one finished within this window.
  /// Prevents reconnect storms from slamming the ring with 7+ fetches each time.
  static const Duration _minSyncInterval = Duration(minutes: 30);

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
    Function(DateTime? since)
    fetchSleep,
    required Future<List<HrDataPoint>> Function(DateTime? since) fetchHr,
    Future<List<RingRawDailySteps>> Function(DateTime? since)? fetchSteps,
    Future<List<RingRawHrvRecord>> Function(DateTime? since)? fetchHrv,
    Future<List<HrDataPoint>> Function(DateTime? since)? fetchHrDetails,
    Future<List<RingRawTemperatureRecord>> Function(DateTime? since)?
    fetchTemperature,
    Future<List<RingRawSpo2Record>> Function(DateTime? since)? fetchSpo2,
    bool Function()? shouldPause,
    bool force = false,
  }) {
    if (_syncing) return;
    final hasIncomplete = _status.lastWasIncomplete;
    if (!force && !hasIncomplete) {
      final lastSync = _status.lastSyncAt;
      if (lastSync != null &&
          DateTime.now().difference(lastSync) < _minSyncInterval) {
        debugPrint(
          '[RingSync] ⏭ Skipping sync — last completed ${DateTime.now().difference(lastSync).inMinutes}m ago '
          '(min interval ${_minSyncInterval.inMinutes}m)',
        );
        return;
      }
    }
    _runSync(
      fetchSleep: fetchSleep,
      fetchHr: fetchHr,
      fetchSteps: fetchSteps,
      fetchHrv: fetchHrv,
      fetchHrDetails: fetchHrDetails,
      fetchTemperature: fetchTemperature,
      fetchSpo2: fetchSpo2,
      shouldPause: shouldPause,
    );
  }

  Future<void> _runSync({
    required Future<({List<RingRawSleepRecord> records, bool isComplete})>
    Function(DateTime? since)
    fetchSleep,
    required Future<List<HrDataPoint>> Function(DateTime? since) fetchHr,
    Future<List<RingRawDailySteps>> Function(DateTime? since)? fetchSteps,
    Future<List<RingRawHrvRecord>> Function(DateTime? since)? fetchHrv,
    Future<List<HrDataPoint>> Function(DateTime? since)? fetchHrDetails,
    Future<List<RingRawTemperatureRecord>> Function(DateTime? since)?
    fetchTemperature,
    Future<List<RingRawSpo2Record>> Function(DateTime? since)? fetchSpo2,
    bool Function()? shouldPause,
  }) async {
    debugPrint('[RingSync] ⟳ Starting ring data sync...');
    _syncing = true;
    _status = RingSyncStatus(
      phase: RingSyncPhase.syncing,
      lastSyncAt: _status.lastSyncAt,
      lastWasIncomplete: _status.lastWasIncomplete,
    );
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    bool anyIncomplete = false;
    final hadPreviousIncomplete = prefs.getBool(_lastIncompleteKey) ?? false;

    try {
      _throwIfPaused(shouldPause);

      // ── Sleep ───────────────────────────────────────────────────────────────
      final sleepCursor = _effectiveCursor(prefs, RingSyncDataType.sleep);
      final sleepFetchSince = sleepCursor?.subtract(const Duration(hours: 24));
      final (:records, :isComplete) = await fetchSleep(sleepFetchSince);
      final sleepToSync = sleepCursor == null
          ? records
          : records
                .where((r) => r.sessionStart.isAfter(sleepFetchSince!))
                .toList();

      final hrCursor = _effectiveCursor(prefs, RingSyncDataType.hr);
      final hrFetchSince = hrCursor?.subtract(const Duration(hours: 24));
      final hrPoints = await fetchHr(hrFetchSince);
      final hrToSync = hrCursor == null
          ? hrPoints
          : hrPoints.where((p) => p.time.isAfter(hrFetchSince!)).toList();

      if (sleepToSync.isNotEmpty) {
        await SleepService().syncFromRingRecords(
          sleepToSync,
          isComplete: true,
          hrHistory: hrPoints,
        );
        final latestSleep = sleepToSync
            .map((r) => r.sessionEnd)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        await _saveCursor(prefs, RingSyncDataType.sleep, latestSleep);
      }
      await _setIncomplete(prefs, RingSyncDataType.sleep, !isComplete);
      anyIncomplete = anyIncomplete || !isComplete;

      _throwIfPaused(shouldPause);

      // ── HR ─────────────────────────────────────────────────────────────────
      if (hrToSync.isNotEmpty) {
        await _uploadHrReadings(hrToSync);
        final latestHr = hrToSync
            .map((p) => p.time)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        await _saveCursor(prefs, RingSyncDataType.hr, latestHr);
      }
      await _setIncomplete(prefs, RingSyncDataType.hr, false);

      // ── Steps ──────────────────────────────────────────────────────────────
      _throwIfPaused(shouldPause);
      if (fetchSteps != null) {
        final stepCursor = _effectiveCursor(prefs, RingSyncDataType.steps);
        final now = DateTime.now();
        final isFreshToday =
            stepCursor != null &&
            stepCursor.year == now.year &&
            stepCursor.month == now.month &&
            stepCursor.day == now.day;
        if (!isFreshToday) {
          final stepRecords = await fetchSteps(stepCursor);
          if (stepRecords.isNotEmpty) {
            await StepsService().syncFromRingRecords(stepRecords);
            final latestStepDate = stepRecords
                .map((r) => r.date)
                .reduce((a, b) => a.isAfter(b) ? a : b);
            await _saveCursor(
              prefs,
              RingSyncDataType.steps,
              DateTime(
                latestStepDate.year,
                latestStepDate.month,
                latestStepDate.day,
                23,
                59,
                59,
              ),
            );
          }
        }
        await _setIncomplete(prefs, RingSyncDataType.steps, false);
      }

      // ── HRV / Stress / Blood Pressure ──────────────────────────────────────
      _throwIfPaused(shouldPause);
      if (fetchHrv != null) {
        final hrvCursor = _effectiveCursor(prefs, RingSyncDataType.hrv);
        final hrvFetchSince = hrvCursor?.subtract(const Duration(hours: 24));
        final hrvRecords = await fetchHrv(hrvFetchSince);
        final hrvToSync = hrvCursor == null
            ? hrvRecords
            : hrvRecords
                  .where((r) => r.timestamp.isAfter(hrvFetchSince!))
                  .toList();
        if (hrvToSync.isNotEmpty) {
          await _uploadHrvReadings(hrvToSync);
          final latestHrv = hrvToSync
              .map((r) => r.timestamp)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          await _saveCursor(prefs, RingSyncDataType.hrv, latestHrv);
        }
        await _setIncomplete(prefs, RingSyncDataType.hrv, false);
      }

      // ── HR Details (0x54) ─────────────────────────────────────────────────
      _throwIfPaused(shouldPause);
      if (fetchHrDetails != null) {
        final detailCursor = _effectiveCursor(
          prefs,
          RingSyncDataType.hrDetails,
        );
        final detailFetchSince = detailCursor?.subtract(
          const Duration(hours: 24),
        );
        final hrDetailPoints = await fetchHrDetails(detailFetchSince);
        final hrDetailToSync = detailCursor == null
            ? hrDetailPoints
            : hrDetailPoints
                  .where((p) => p.time.isAfter(detailFetchSince!))
                  .toList();
        if (hrDetailToSync.isNotEmpty) {
          await _uploadHrReadings(hrDetailToSync);
          final latestDetail = hrDetailToSync
              .map((p) => p.time)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          await _saveCursor(prefs, RingSyncDataType.hrDetails, latestDetail);
        }
        await _setIncomplete(prefs, RingSyncDataType.hrDetails, false);
      }

      // ── Temperature (0x62) ────────────────────────────────────────────────
      _throwIfPaused(shouldPause);
      if (fetchTemperature != null) {
        final tempCursor = _effectiveCursor(
          prefs,
          RingSyncDataType.temperature,
        );
        final tempFetchSince = tempCursor?.subtract(const Duration(hours: 24));
        final tempRecords = await fetchTemperature(tempFetchSince);
        final tempToSync = tempCursor == null
            ? tempRecords
            : tempRecords
                  .where((r) => r.timestamp.isAfter(tempFetchSince!))
                  .toList();
        if (tempToSync.isNotEmpty) {
          await _uploadTemperatureReadings(tempToSync);
          final latestTemp = tempToSync
              .map((r) => r.timestamp)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          await _saveCursor(prefs, RingSyncDataType.temperature, latestTemp);
        }
        await _setIncomplete(prefs, RingSyncDataType.temperature, false);
      }

      // ── SpO2 (0x66) ───────────────────────────────────────────────────────
      _throwIfPaused(shouldPause);
      if (fetchSpo2 != null) {
        final spo2Cursor = _effectiveCursor(prefs, RingSyncDataType.spo2);
        final spo2FetchSince = spo2Cursor?.subtract(const Duration(hours: 24));
        final spo2Records = await fetchSpo2(spo2FetchSince);
        final spo2ToSync = spo2Cursor == null
            ? spo2Records
            : spo2Records
                  .where((r) => r.timestamp.isAfter(spo2FetchSince!))
                  .toList();
        if (spo2ToSync.isNotEmpty) {
          await _uploadSpo2Readings(spo2ToSync);
          final latestSpo2 = spo2ToSync
              .map((r) => r.timestamp)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          await _saveCursor(prefs, RingSyncDataType.spo2, latestSpo2);
        }
        await _setIncomplete(prefs, RingSyncDataType.spo2, false);
      }

      // ── Persist sync timestamp ─────────────────────────────────────────────
      final now = DateTime.now();
      await prefs.setString(_lastSyncKey, now.toIso8601String());
      await prefs.setBool(_lastIncompleteKey, anyIncomplete);

      _status = RingSyncStatus(
        phase: RingSyncPhase.done,
        lastSyncAt: now,
        lastWasIncomplete: anyIncomplete,
      );
      debugPrint(
        '[RingSync] ✓ All ring data sync completed (incomplete=$anyIncomplete, at=$now)',
      );
    } on _SyncPausedException {
      anyIncomplete = true;
      await prefs.setBool(_lastIncompleteKey, true);
      _status = RingSyncStatus(
        phase: RingSyncPhase.idle,
        lastSyncAt: _status.lastSyncAt,
        lastWasIncomplete: true,
      );
      debugPrint('[RingSync] ⏸ Paused due to active real-time stream');
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
      if (!anyIncomplete && hadPreviousIncomplete) {
        await _clearAllIncompleteFlags();
      }
      notifyListeners();
    }
  }

  void _throwIfPaused(bool Function()? shouldPause) {
    if (shouldPause != null && shouldPause()) {
      throw _SyncPausedException();
    }
  }

  String _cursorKey(RingSyncDataType type) => '$_cursorPrefix${type.name}';
  String _incompleteKey(RingSyncDataType type) =>
      '$_incompletePrefix${type.name}';

  DateTime? _loadCursor(SharedPreferences prefs, RingSyncDataType type) {
    final raw = prefs.getString(_cursorKey(type));
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  DateTime? _effectiveCursor(SharedPreferences prefs, RingSyncDataType type) {
    final typed = _loadCursor(prefs, type);
    if (typed != null) return typed;
    final globalRaw = prefs.getString(_lastSyncKey);
    if (globalRaw == null || globalRaw.isEmpty) return null;
    try {
      return DateTime.parse(globalRaw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCursor(
    SharedPreferences prefs,
    RingSyncDataType type,
    DateTime ts,
  ) async {
    await prefs.setString(_cursorKey(type), ts.toIso8601String());
  }

  Future<void> _setIncomplete(
    SharedPreferences prefs,
    RingSyncDataType type,
    bool value,
  ) async {
    await prefs.setBool(_incompleteKey(type), value);
  }

  Future<void> _clearAllIncompleteFlags() async {
    final prefs = await SharedPreferences.getInstance();
    for (final type in RingSyncDataType.values) {
      await prefs.setBool(_incompleteKey(type), false);
    }
  }

  Future<void> _uploadHrReadings(List<HrDataPoint> points) async {
    final token = AuthService().token;
    if (token == null) return;

    final payload = {
      'readings': points
          .map(
            (p) => {
              'timestamp': p.time.toUtc().toIso8601String(),
              'bpm': p.bpm,
            },
          )
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
          .map(
            (r) => {
              'timestamp': r.timestamp.toUtc().toIso8601String(),
              'hrv_ms': r.hrvMs,
              'heart_rate_bpm': r.heartRateBpm,
              'fatigue': r.fatigue,
              'systolic_mmhg': r.systolicMmhg,
              'diastolic_mmhg': r.diastolicMmhg,
            },
          )
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

  Future<void> _uploadTemperatureReadings(
    List<RingRawTemperatureRecord> records,
  ) async {
    final token = AuthService().token;
    if (token == null) return;

    final payload = {
      'readings': records
          .map(
            (r) => {
              'timestamp': r.timestamp.toUtc().toIso8601String(),
              'temp1_c': r.temp1C,
              'temp2_c': r.temp2C,
              'temp3_c': r.temp3C,
            },
          )
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
          .map(
            (r) => {
              'timestamp': r.timestamp.toUtc().toIso8601String(),
              'spo2_percent': r.spo2Percent,
            },
          )
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

class _SyncPausedException implements Exception {}
