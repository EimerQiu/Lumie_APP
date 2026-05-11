import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/debug_log_service.dart';
import '../../../core/services/hr_session_service.dart';
import '../../../shared/models/heart_rate_models.dart';
import '../../ring/providers/ring_provider.dart';

enum HrMeasureState { idle, measuring, paused, done }

class _HrRange {
  final DateTime start;
  final DateTime end;

  const _HrRange({required this.start, required this.end});

  bool get isValid => !end.isBefore(start);

  bool overlaps(_HrRange other) =>
      !end.isBefore(other.start) && !other.end.isBefore(start);

  bool contains(DateTime t) =>
      (t.isAtSameMomentAs(start) || t.isAfter(start)) &&
      (t.isAtSameMomentAs(end) || t.isBefore(end));
}

class HeartRateProvider extends ChangeNotifier {
  RingProvider? _ringProvider;
  List<HrDataPoint> _dailyReadings = [];
  bool _loadingHistory = false;
  HrMeasureState _measureState = HrMeasureState.idle;

  // ─── Live session state ───────────────────────────────────────────────────
  final List<HrSessionPoint> _sessionReadings = [];
  StreamSubscription<int>? _hrSub;
  Timer? _elapsedTimer;
  Timer? _autoStopTimer;
  Timer? _pauseCleanupTimer;
  Duration _elapsed = Duration.zero;
  int? _currentBpm; // latest filtered reading

  static const Duration _maxDuration = Duration(hours: 1, minutes: 30);
  static const Duration _gapDetectThreshold = Duration(seconds: 5);
  static const Duration _gapEdgeTrim = Duration(seconds: 1);
  static const Duration _backfillQueryLookback = Duration(seconds: 90);
  static const Duration _backfillMinInterval = Duration(seconds: 20);
  static const Duration _backfillRealtimeGuard = Duration(seconds: 8);
  static const Duration _backfillMaxWindow = Duration(seconds: 20);
  static const Duration _backfillCatchupMaxWindow = Duration(seconds: 120);

  /// How many consecutive realtime readings we need after (re)connect before
  /// allowing a backfill query. Prevents slamming the ring with 0x54/0x55
  /// fetches while the live 0x18 stream is still re-establishing.
  static const int _stableReadingsBeforeBackfill = 3;

  final List<_HrRange> _pendingBackfillRanges = [];
  final List<_HrRange> _attemptedBackfillRanges = [];
  bool _backfillInProgress = false;
  DateTime? _lastBackfillStartedAt;
  DateTime? _lastRealtimePointTime;
  DateTime? _measurementStartedAt;
  bool _lastRingConnected = false;
  int _stableReadingsCount = 0;
  bool _autoPausedByDisconnect = false;
  bool _restoreChecked = false;
  bool _restoreInFlight = false;
  bool _restoreCatchupMode = false;

  static const String _persistActiveKey = 'hr_measure_active';
  static const String _persistStartedAtKey = 'hr_measure_started_at';
  static const String _persistElapsedSecsKey = 'hr_measure_elapsed_secs';

  // Diagnostic counters: emit a periodic summary line so we can detect a
  // ramping rebuild rate, leaked stream subscriptions, or stuck backfill.
  int _readingsSinceLastSummary = 0;
  int _notifyListenersSinceLastSummary = 0;
  Timer? _diagSummaryTimer;

  // Adaptive EMA smoothing parameters
  static const double _minAlpha = 0.15; // smooth during stable periods
  static const double _maxAlpha = 0.6; // responsive during rapid changes
  double _emaValue = 0.0;
  int _previousRaw = 0;
  int _stabilityCounter = 0;

  // ─── Diagnostics ──────────────────────────────────────────────────────────

  void _startDiagSummaryTimer() {
    _diagSummaryTimer?.cancel();
    _diagSummaryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      dlog(
        'HR_PROV',
        'diag readings=$_readingsSinceLastSummary '
            'notify=$_notifyListenersSinceLastSummary '
            'session=${_sessionReadings.length} '
            'pendingGaps=${_pendingBackfillRanges.length} '
            'attemptedGaps=${_attemptedBackfillRanges.length} '
            'backfillInProgress=$_backfillInProgress '
            'state=$_measureState '
            'connected=$_lastRingConnected',
      );
      _readingsSinceLastSummary = 0;
      _notifyListenersSinceLastSummary = 0;
    });
  }

  void _stopDiagSummaryTimer() {
    _diagSummaryTimer?.cancel();
    _diagSummaryTimer = null;
  }

  // ─── ProxyProvider bridge ─────────────────────────────────────────────────

  void updateRingProvider(RingProvider ring) {
    final previousRing = _ringProvider;
    final wasPaired = _ringProvider?.isPaired ?? false;
    previousRing?.removeListener(_onRingStateChanged);
    _ringProvider = ring;
    _ringProvider!.addListener(_onRingStateChanged);
    _lastRingConnected = ring.isConnected;
    unawaited(_restoreMeasurementAfterColdStartIfNeeded());
    if (!wasPaired && ring.isPaired) {
      fetchDailyHistory();
    }
  }

  Future<void> _restoreMeasurementAfterColdStartIfNeeded() async {
    if (_restoreChecked || _restoreInFlight) return;
    _restoreInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasActive = prefs.getBool(_persistActiveKey) ?? false;
      _restoreChecked = true;
      if (!wasActive) return;

      final startedAtRaw = prefs.getString(_persistStartedAtKey);
      final startedAt = startedAtRaw == null
          ? null
          : DateTime.tryParse(startedAtRaw);
      if (startedAt == null) {
        await _clearPersistedMeasurementState();
        return;
      }

      final savedElapsedSecs = prefs.getInt(_persistElapsedSecsKey) ?? 0;
      final wallElapsed = DateTime.now().difference(startedAt);
      final restoredElapsed = wallElapsed > Duration(seconds: savedElapsedSecs)
          ? wallElapsed
          : Duration(seconds: savedElapsedSecs);

      _measurementStartedAt = startedAt;
      _elapsed = restoredElapsed > _maxDuration
          ? _maxDuration
          : restoredElapsed;
      _measureState = HrMeasureState.paused;
      _autoPausedByDisconnect = true;
      _currentBpm = null;
      _pendingBackfillRanges.clear();
      _attemptedBackfillRanges.clear();
      _backfillInProgress = false;
      _lastRealtimePointTime = null;
      _stableReadingsCount = 0;
      _restoreCatchupMode = false;

      // Cold start loses in-memory session samples. Queue one reconstruction
      // gap so after realtime resumes we can backfill this missing window.
      final gapStart = startedAt.add(_gapEdgeTrim);
      final gapEnd = DateTime.now().subtract(_gapEdgeTrim);
      if (!gapEnd.isBefore(gapStart)) {
        _enqueueGap(_HrRange(start: gapStart, end: gapEnd));
        _restoreCatchupMode = true;
      }
      notifyListeners();
      dlog(
        'HR_PROV',
        'cold-start restore candidate: startedAt=${startedAt.toIso8601String()} elapsed=${_elapsed.inSeconds}s pendingGaps=${_pendingBackfillRanges.length}',
      );

      final ring = _ringProvider;
      if (ring != null && ring.isConnected) {
        await _autoResumeAfterReconnect(ring);
      }
    } catch (e) {
      dlog('HR_PROV', 'cold-start restore failed: $e');
    } finally {
      _restoreInFlight = false;
    }
  }

  Future<void> _persistMeasurementState({required bool active}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_persistActiveKey, active);
      if (active) {
        final startedAt = _measurementStartedAt ?? DateTime.now();
        await prefs.setString(
          _persistStartedAtKey,
          startedAt.toIso8601String(),
        );
        await prefs.setInt(_persistElapsedSecsKey, _elapsed.inSeconds);
      }
    } catch (_) {}
  }

  Future<void> _clearPersistedMeasurementState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_persistActiveKey);
      await prefs.remove(_persistStartedAtKey);
      await prefs.remove(_persistElapsedSecsKey);
    } catch (_) {}
  }

  void _onRingStateChanged() {
    final ring = _ringProvider;
    if (ring == null) return;
    final connected = ring.isConnected;
    final wasConnected = _lastRingConnected;
    final justReconnected = !wasConnected && connected;
    final justDisconnected = wasConnected && !connected;
    _lastRingConnected = connected;

    if (justDisconnected) {
      dlog(
        'HR_PROV',
        'ring DISCONNECTED while state=$_measureState '
            'session=${_sessionReadings.length} '
            'lastReading=${_lastRealtimePointTime?.toIso8601String() ?? "null"}',
      );
      if (_measureState == HrMeasureState.measuring) {
        _autoPauseForDisconnect();
      }
    }
    if (justReconnected) {
      dlog(
        'HR_PROV',
        'ring RECONNECTED while state=$_measureState '
            'session=${_sessionReadings.length}',
      );
    }

    if (!justReconnected) return;

    // Reload daily history when ring reconnects
    fetchDailyHistory();

    if (_measureState == HrMeasureState.paused && _autoPausedByDisconnect) {
      unawaited(_autoResumeAfterReconnect(ring));
      return;
    }

    if (_measureState == HrMeasureState.measuring) {
      // Re-subscribe to the new characteristic so the stream stays live.
      // startHrStreaming() re-enables 0x19 exercise push mode as needed.
      dlog(
        'HR_PROV',
        'reconnect resub: cancelling old _hrSub (was=${_hrSub == null ? "null" : "alive"})',
      );
      _hrSub?.cancel();
      final stream = ring.startHrStreaming();
      _hrSub = stream.listen(
        _onRawReading,
        onError: (e) {
          debugPrint('[HR] stream error after reconnect: $e');
          dlog('HR_PROV', 'stream error after reconnect: $e');
        },
      );
      // Backfill is deferred until the realtime stream is producing readings
      // again — see _onRawReading. Just enqueue the gap so we don't lose it.
      _stableReadingsCount = 0;
      _enqueueGapsFromSession();
    } else if (_measureState == HrMeasureState.done) {
      // Stop was tapped while disconnected — send stop commands to the ring now.
      ring.stopHrStreaming().catchError(
        (e) => debugPrint('[HR] delayed stop error: $e'),
      );
    }
  }

  void _autoPauseForDisconnect() {
    dlog('HR_PROV', 'auto-pause measurement due to disconnect');
    _autoPausedByDisconnect = true;
    _pauseCleanupTimer?.cancel();
    _pauseCleanupTimer = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _measureState = HrMeasureState.paused;
    notifyListeners();
    unawaited(_persistMeasurementState(active: true));
  }

  Future<void> _autoResumeAfterReconnect(RingProvider ring) async {
    dlog('HR_PROV', 'auto-resume measurement after reconnect');
    await _hrSub?.cancel();
    _hrSub = null;

    final stream = ring.startHrStreaming();
    _hrSub = stream.listen(
      _onRawReading,
      onError: (e) => debugPrint('[HR] stream error after auto-resume: $e'),
    );
    _lastRingConnected = ring.isConnected;
    _stableReadingsCount = 0;

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      _notifyListenersSinceLastSummary++;
      notifyListeners();
      if (_elapsed.inSeconds % 15 == 0) {
        unawaited(_persistMeasurementState(active: true));
      }
    });

    final remaining = _maxDuration - _elapsed;
    if (remaining > Duration.zero) {
      _autoStopTimer = Timer(remaining, () => stopMeasurement());
      _measureState = HrMeasureState.measuring;
      _autoPausedByDisconnect = false;
      notifyListeners();
      unawaited(_persistMeasurementState(active: true));
      _kickBackfillIfNeeded(force: true);
      return;
    }

    _autoPausedByDisconnect = false;
    unawaited(_clearPersistedMeasurementState());
    await stopMeasurement();
  }

  // ─── Public getters ───────────────────────────────────────────────────────

  List<HrDataPoint> get dailyReadings => _dailyReadings;
  bool get loadingHistory => _loadingHistory;
  HrMeasureState get measureState => _measureState;

  /// True until EMA has stabilized — BPM should not be shown yet (first ~2 seconds).
  bool get isWarmingUp => _stabilityCounter < 3;

  int? get liveHr => isWarmingUp ? null : _currentBpm;
  int? get finalHr => _currentBpm;
  Duration get elapsed => _elapsed;
  Duration get timelineElapsed {
    if (_sessionReadings.length < 2) return _elapsed;
    final span = _sessionReadings.last.time.difference(
      _sessionReadings.first.time,
    );
    if (span.isNegative) return _elapsed;
    // After cold-start restore, _elapsed represents known session runtime even
    // before backfilled points are merged. Never let timeline go backwards.
    return span > _elapsed ? span : _elapsed;
  }

  double get chartTimeOffsetSeconds {
    if (_sessionReadings.length < 2) return 0;
    final span = _sessionReadings.last.time
        .difference(_sessionReadings.first.time)
        .inSeconds;
    if (span <= 0) return 0;
    final offset = timelineElapsed.inSeconds - span;
    return offset > 0 ? offset.toDouble() : 0;
  }

  List<HrSessionPoint> get sessionReadings =>
      List.unmodifiable(_sessionReadings);

  int? get sessionMin => _sessionReadings.isEmpty
      ? null
      : _sessionReadings.map((e) => e.smoothedBpm.round()).reduce(min);

  int? get sessionMax => _sessionReadings.isEmpty
      ? null
      : _sessionReadings.map((e) => e.smoothedBpm.round()).reduce(max);

  int? get sessionAvg => _sessionReadings.isEmpty
      ? null
      : (_sessionReadings.map((e) => e.smoothedBpm).reduce((a, b) => a + b) /
                _sessionReadings.length)
            .round();

  DateTime? get measurementStartedAt => _measurementStartedAt;

  int? get latestHr => _dailyReadings.isEmpty ? null : _dailyReadings.last.bpm;

  int? get todayMin => _dailyReadings.isEmpty
      ? null
      : _dailyReadings.map((e) => e.bpm).reduce(min);

  int? get todayMax => _dailyReadings.isEmpty
      ? null
      : _dailyReadings.map((e) => e.bpm).reduce(max);

  int? get todayAvg => _dailyReadings.isEmpty
      ? null
      : (_dailyReadings.map((e) => e.bpm).reduce((a, b) => a + b) /
                _dailyReadings.length)
            .round();

  List<HrBackfillRange> get attemptedBackfillRanges => _attemptedBackfillRanges
      .map((e) => HrBackfillRange(start: e.start, end: e.end))
      .toList(growable: false);

  int estimateMaxHeartRate({int? age}) {
    final safeAge = age ?? 20;
    final estimated = (208 - 0.7 * safeAge).round();
    return estimated.clamp(130, 210);
  }

  List<Duration> zoneDurations({int? age}) {
    final zones = List<Duration>.filled(6, Duration.zero);
    if (_sessionReadings.isEmpty) return zones;

    final maxHr = estimateMaxHeartRate(age: age);
    final sorted = [..._sessionReadings]
      ..sort((a, b) => a.time.compareTo(b.time));

    int zoneForBpm(int bpm) {
      final ratio = bpm / maxHr;
      if (ratio < 0.5) return 0;
      if (ratio < 0.6) return 1;
      if (ratio < 0.7) return 2;
      if (ratio < 0.8) return 3;
      if (ratio < 0.9) return 4;
      return 5;
    }

    for (var i = 0; i < sorted.length; i++) {
      final current = sorted[i];
      final bpm = current.smoothedBpm.round();
      final zone = zoneForBpm(bpm);

      Duration span;
      switch (current.source) {
        case HrSessionPointSource.realtime:
          if (i < sorted.length - 1) {
            final delta = sorted[i + 1].time.difference(current.time);
            if (delta > Duration.zero && delta <= const Duration(seconds: 5)) {
              span = delta;
              break;
            }
          }
          span = const Duration(seconds: 1);
          break;
        case HrSessionPointSource.backfillDetail:
          // 0x54 detailed HR is one point per 5 seconds.
          span = const Duration(seconds: 5);
          break;
        case HrSessionPointSource.backfillHistory:
          // 0x55 single-point history has coarser/unknown interval.
          span = const Duration(seconds: 1);
          break;
      }

      zones[zone] += span;
    }

    return zones;
  }

  // ─── Adaptive EMA Smoothing ───────────────────────────────────────────────

  /// Adaptive EMA: adjusts smoothing based on signal volatility.
  /// Fast changes → responsive (high alpha), stable → smooth (low alpha).
  double _adaptiveEMA(int raw) {
    if (_stabilityCounter == 0) {
      // First reading: initialize
      _emaValue = raw.toDouble();
      _previousRaw = raw;
      _stabilityCounter = 1;
      return _emaValue;
    }

    // Detect stable vs. changing conditions
    final delta = (raw - _previousRaw).abs();
    final isStable = delta <= 5; // 5 BPM = threshold for stability

    // Adaptive alpha: low for smooth, high for responsive
    final alpha = isStable ? _minAlpha : _maxAlpha;

    // EMA: new = alpha * raw + (1-alpha) * old
    _emaValue = alpha * raw + (1 - alpha) * _emaValue;
    _previousRaw = raw;

    // Stability counter: ramps up to 10 (used for warming-up detection)
    if (_stabilityCounter < 10) _stabilityCounter++;

    return _emaValue;
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> fetchDailyHistory() async {
    if (_ringProvider == null || !_ringProvider!.isPaired) return;
    _loadingHistory = true;
    notifyListeners();
    _dailyReadings = await _ringProvider!.fetchHrHistory();
    _loadingHistory = false;
    notifyListeners();
  }

  Future<void> startMeasurement() async {
    if (_ringProvider == null ||
        !_ringProvider!.isPaired ||
        !_ringProvider!.isConnected) {
      return;
    }
    if (_measureState == HrMeasureState.measuring) return;

    _sessionReadings.clear();
    _emaValue = 0.0;
    _previousRaw = 0;
    _stabilityCounter = 0;
    _currentBpm = null;
    _elapsed = Duration.zero;
    _pendingBackfillRanges.clear();
    _attemptedBackfillRanges.clear();
    _backfillInProgress = false;
    _measurementStartedAt = DateTime.now();
    _lastRealtimePointTime = null;
    _lastRingConnected = _ringProvider?.isConnected ?? false;
    _stableReadingsCount = 0;
    _measureState = HrMeasureState.measuring;
    notifyListeners();
    unawaited(_persistMeasurementState(active: true));

    dlog('HR_PROV', 'startMeasurement (max=${_maxDuration.inMinutes} min)');
    _startDiagSummaryTimer();

    final stream = _ringProvider!.startHrStreaming();
    _hrSub = stream.listen(
      _onRawReading,
      onError: (e) {
        debugPrint('[HR] stream error: $e');
        dlog('HR_PROV', 'stream error: $e');
      },
    );

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      _notifyListenersSinceLastSummary++;
      notifyListeners();
      if (_elapsed.inSeconds % 15 == 0) {
        unawaited(_persistMeasurementState(active: true));
      }
    });

    _autoStopTimer = Timer(_maxDuration, () {
      stopMeasurement();
    });
  }

  void _onRawReading(int raw) {
    if (raw < 30 || raw > 220) {
      dlog('HR_PROV', 'reading $raw rejected (out of range 30-220)');
      return;
    }
    final now = DateTime.now();
    final smoothed = _adaptiveEMA(raw);
    _currentBpm = smoothed.round();
    _readingsSinceLastSummary++;
    // Only record to session once the warmup phase is complete
    if (!isWarmingUp) {
      if (_lastRealtimePointTime != null) {
        final gap = now.difference(_lastRealtimePointTime!);
        if (gap > _gapDetectThreshold) {
          dlog(
            'HR_PROV',
            'gap detected ${gap.inSeconds}s — enqueueing backfill range',
          );
          _enqueueGap(
            _HrRange(
              start: _lastRealtimePointTime!.add(_gapEdgeTrim),
              end: now.subtract(_gapEdgeTrim),
            ),
          );
          _kickBackfillIfNeeded();
        }
      }
      _sessionReadings.add(
        HrSessionPoint(
          time: now,
          rawBpm: raw,
          smoothedBpm: smoothed,
          source: HrSessionPointSource.realtime,
        ),
      );
      _lastRealtimePointTime = now;

      // Track post-(re)connect stability. Once the live stream has produced a
      // few readings in a row we let backfill run — earlier than that, the BLE
      // link is too fragile to handle the extra 0x54/0x55 query traffic.
      if (_stableReadingsCount < _stableReadingsBeforeBackfill) {
        _stableReadingsCount++;
        if (_stableReadingsCount == _stableReadingsBeforeBackfill &&
            _pendingBackfillRanges.isNotEmpty) {
          dlog('HR_PROV', 'stream stable — draining deferred backfill');
          _kickBackfillIfNeeded();
        }
      }
    }
    _notifyListenersSinceLastSummary++;
    notifyListeners();
  }

  void _enqueueGapsFromSession() {
    if (_sessionReadings.length < 2) return;
    final sorted = [..._sessionReadings]
      ..sort((a, b) => a.time.compareTo(b.time));
    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1].time;
      final next = sorted[i].time;
      if (next.difference(prev) <= _gapDetectThreshold) continue;
      _enqueueGap(
        _HrRange(
          start: prev.add(_gapEdgeTrim),
          end: next.subtract(_gapEdgeTrim),
        ),
      );
    }
  }

  void _enqueueGap(_HrRange gap) {
    if (!gap.isValid) return;
    if (_isCoveredByRanges(gap, _attemptedBackfillRanges)) return;
    if (_isCoveredByRanges(gap, _pendingBackfillRanges)) return;
    _pendingBackfillRanges.add(gap);
    _mergeRangesInPlace(_pendingBackfillRanges);
  }

  bool _isCoveredByRanges(_HrRange range, List<_HrRange> ranges) {
    for (final r in ranges) {
      if (r.overlaps(range)) return true;
    }
    return false;
  }

  void _mergeRangesInPlace(List<_HrRange> ranges) {
    if (ranges.length < 2) return;
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final merged = <_HrRange>[ranges.first];
    for (var i = 1; i < ranges.length; i++) {
      final last = merged.last;
      final current = ranges[i];
      if (!last.end.isBefore(current.start)) {
        final mergedEnd = last.end.isAfter(current.end)
            ? last.end
            : current.end;
        merged[merged.length - 1] = _HrRange(start: last.start, end: mergedEnd);
      } else {
        merged.add(current);
      }
    }
    ranges
      ..clear()
      ..addAll(merged);
  }

  void _markBackfillAttempted(_HrRange range) {
    _attemptedBackfillRanges.add(range);
    _mergeRangesInPlace(_attemptedBackfillRanges);
  }

  void _kickBackfillIfNeeded({bool force = false}) {
    if (_backfillInProgress || _measureState != HrMeasureState.measuring) {
      return;
    }
    final ring = _ringProvider;
    if (ring == null || !ring.isConnected) return;
    if (_pendingBackfillRanges.isEmpty) return;
    final aggressive = force || _restoreCatchupMode;
    if (!aggressive && _stableReadingsCount < _stableReadingsBeforeBackfill) {
      // Defer until the realtime stream has stabilized — see _onRawReading.
      return;
    }
    final now = DateTime.now();
    final lastStarted = _lastBackfillStartedAt;
    if (!aggressive &&
        lastStarted != null &&
        now.difference(lastStarted) < _backfillMinInterval) {
      return;
    }
    final lastRealtime = _lastRealtimePointTime;
    if (!aggressive &&
        lastRealtime != null &&
        now.difference(lastRealtime) < _backfillRealtimeGuard) {
      return;
    }
    _runBackfill();
  }

  Future<void> _runBackfill() async {
    if (_backfillInProgress) return;
    _backfillInProgress = true;
    _lastBackfillStartedAt = DateTime.now();
    dlog(
      'HR_PROV',
      'backfill begin (pending=${_pendingBackfillRanges.length})',
    );
    try {
      while (_measureState == HrMeasureState.measuring &&
          _pendingBackfillRanges.isNotEmpty &&
          (_ringProvider?.isConnected ?? false)) {
        final gap = _pendingBackfillRanges.removeAt(0);
        final cappedGap = _capGapWindow(gap);
        _markBackfillAttempted(cappedGap);
        if (cappedGap.end.isBefore(gap.end)) {
          _enqueueGap(_HrRange(start: cappedGap.end, end: gap.end));
        }

        final measurementStart = _measurementStartedAt ?? cappedGap.start;
        var queryStart = cappedGap.start.subtract(_backfillQueryLookback);
        if (queryStart.isBefore(measurementStart)) {
          queryStart = measurementStart;
        }

        final ring = _ringProvider;
        if (ring == null || !ring.isConnected) break;

        final t0 = DateTime.now();
        final results = await Future.wait([
          ring.fetchHrDetailsRange(start: queryStart, end: cappedGap.end),
          ring.fetchHrHistoryRange(start: queryStart, end: cappedGap.end),
        ]);
        final fetchMs = DateTime.now().difference(t0).inMilliseconds;
        dlog(
          'HR_PROV',
          'backfill fetch ok in ${fetchMs}ms — '
              'detail=${results[0].length} history=${results[1].length}',
        );

        if (_measureState != HrMeasureState.measuring) break;
        _mergeBackfilledPoints(
          detailPoints: results[0],
          historyPoints: results[1],
          gap: cappedGap,
        );
      }
      if (_pendingBackfillRanges.isEmpty) {
        _restoreCatchupMode = false;
      }
    } catch (e) {
      debugPrint('[HR] backfill error: $e');
      dlog('HR_PROV', 'backfill error: $e');
    } finally {
      _backfillInProgress = false;
      _notifyListenersSinceLastSummary++;
      notifyListeners();
      dlog('HR_PROV', 'backfill end');
    }
  }

  _HrRange _capGapWindow(_HrRange gap) {
    final window = _restoreCatchupMode
        ? _backfillCatchupMaxWindow
        : _backfillMaxWindow;
    final maxEnd = gap.start.add(window);
    if (!maxEnd.isBefore(gap.end)) return gap;
    return _HrRange(start: gap.start, end: maxEnd);
  }

  void _mergeBackfilledPoints({
    required List<HrDataPoint> detailPoints,
    required List<HrDataPoint> historyPoints,
    required _HrRange gap,
  }) {
    final windowStart = (_measurementStartedAt ?? DateTime.now()).subtract(
      const Duration(seconds: 30),
    );
    final windowEnd = DateTime.now().add(const Duration(seconds: 5));

    final bySecond = <int, HrSessionPoint>{};
    for (final p in _sessionReadings) {
      final key = p.time.millisecondsSinceEpoch ~/ 1000;
      bySecond[key] = p;
    }

    void addPoints(List<HrDataPoint> points, HrSessionPointSource source) {
      for (final p in points) {
        if (!gap.contains(p.time)) continue;
        if (p.time.isBefore(windowStart) || p.time.isAfter(windowEnd)) continue;
        final key = p.time.millisecondsSinceEpoch ~/ 1000;
        final existing = bySecond[key];
        if (existing == null) {
          bySecond[key] = HrSessionPoint(
            time: p.time,
            rawBpm: p.bpm,
            smoothedBpm: p.bpm.toDouble(),
            source: source,
          );
          continue;
        }
        if (existing.source == HrSessionPointSource.realtime) continue;
        if (existing.source == HrSessionPointSource.backfillDetail &&
            source == HrSessionPointSource.backfillHistory) {
          continue;
        }
        bySecond[key] = HrSessionPoint(
          time: p.time,
          rawBpm: p.bpm,
          smoothedBpm: p.bpm.toDouble(),
          source: source,
        );
      }
    }

    addPoints(detailPoints, HrSessionPointSource.backfillDetail);
    addPoints(historyPoints, HrSessionPointSource.backfillHistory);

    final mergeT0 = DateTime.now();
    final beforeCount = _sessionReadings.length;
    final merged = bySecond.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    _sessionReadings
      ..clear()
      ..addAll(merged);
    final mergeMs = DateTime.now().difference(mergeT0).inMilliseconds;
    dlog(
      'HR_PROV',
      'merge backfill: $beforeCount → ${_sessionReadings.length} '
          '(detail=${detailPoints.length} history=${historyPoints.length}) '
          'in ${mergeMs}ms',
    );
  }

  Future<void> pauseMeasurement() async {
    if (_measureState != HrMeasureState.measuring) return;
    dlog('HR_PROV', 'pauseMeasurement (session=${_sessionReadings.length})');

    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    // Send stop command to ring — keeps BLE notifications flowing briefly.
    await _ringProvider?.stopHrStreaming();

    _measureState = HrMeasureState.paused;
    _autoPausedByDisconnect = false;
    notifyListeners();
    unawaited(_persistMeasurementState(active: true));

    // Keep stream alive for 30 s to catch any late readings, then cancel.
    _pauseCleanupTimer = Timer(const Duration(seconds: 30), () async {
      await _hrSub?.cancel();
      _hrSub = null;
    });
  }

  Future<void> resumeMeasurement() async {
    if (_measureState != HrMeasureState.paused) return;
    if (_ringProvider == null || !_ringProvider!.isConnected) return;
    dlog('HR_PROV', 'resumeMeasurement (session=${_sessionReadings.length})');

    _pauseCleanupTimer?.cancel();
    _pauseCleanupTimer = null;

    await _hrSub?.cancel();
    _hrSub = null;

    final stream = _ringProvider!.startHrStreaming();
    _hrSub = stream.listen(
      _onRawReading,
      onError: (e) => debugPrint('[HR] stream error after resume: $e'),
    );
    _lastRingConnected = _ringProvider?.isConnected ?? false;
    _stableReadingsCount = 0;

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      _notifyListenersSinceLastSummary++;
      notifyListeners();
      if (_elapsed.inSeconds % 15 == 0) {
        unawaited(_persistMeasurementState(active: true));
      }
    });

    final remaining = _maxDuration - _elapsed;
    if (remaining > Duration.zero) {
      _autoStopTimer = Timer(remaining, () => stopMeasurement());
    } else {
      stopMeasurement();
      return;
    }

    _measureState = HrMeasureState.measuring;
    _autoPausedByDisconnect = false;
    notifyListeners();
    unawaited(_persistMeasurementState(active: true));
    _kickBackfillIfNeeded(force: true);
  }

  Future<void> stopMeasurement() async {
    if (_measureState != HrMeasureState.measuring &&
        _measureState != HrMeasureState.paused) {
      return;
    }
    dlog(
      'HR_PROV',
      'stopMeasurement (state=$_measureState, '
          'session=${_sessionReadings.length}, '
          'pendingGaps=${_pendingBackfillRanges.length}, '
          'attemptedGaps=${_attemptedBackfillRanges.length})',
    );
    _stopDiagSummaryTimer();

    _pauseCleanupTimer?.cancel();
    _pauseCleanupTimer = null;

    // Snapshot before teardown — _sessionReadings is not cleared here,
    // but capture startedAt and endedAt while they are still meaningful.
    final startedAt = _measurementStartedAt;
    final endedAt = DateTime.now();
    final snapshotReadings = List<HrSessionPoint>.unmodifiable(
      _sessionReadings,
    );

    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    await _hrSub?.cancel();
    _hrSub = null;
    await _ringProvider?.stopHrStreaming();

    // Append session avg to daily history (in-memory, for this session)
    final avg = sessionAvg;
    if (avg != null) {
      _dailyReadings = [
        ..._dailyReadings,
        HrDataPoint(time: endedAt, bpm: avg),
      ];
    }

    _measureState = HrMeasureState.done;
    _autoPausedByDisconnect = false;
    _restoreCatchupMode = false;
    notifyListeners();
    unawaited(_clearPersistedMeasurementState());

    // Persist session to backend — fire-and-forget, never block the UI.
    // Requires at least a few readings to be worth saving.
    if (startedAt != null && snapshotReadings.length >= 5 && avg != null) {
      HrSessionService()
          .saveSession(
            startedAt: startedAt,
            endedAt: endedAt,
            avgBpm: avg,
            minBpm: sessionMin ?? avg,
            maxBpm: sessionMax ?? avg,
            readings: snapshotReadings,
          )
          .catchError((e) {
            debugPrint('[HR] session save error: $e');
            return null;
          });
    }
  }

  void resetMeasurement() {
    _measureState = HrMeasureState.idle;
    _autoPausedByDisconnect = false;
    _restoreCatchupMode = false;
    _currentBpm = null;
    _sessionReadings.clear();
    _pendingBackfillRanges.clear();
    _attemptedBackfillRanges.clear();
    _backfillInProgress = false;
    _lastRealtimePointTime = null;
    _measurementStartedAt = null;
    _emaValue = 0.0;
    _previousRaw = 0;
    _stabilityCounter = 0;
    _stableReadingsCount = 0;
    _elapsed = Duration.zero;
    notifyListeners();
    unawaited(_clearPersistedMeasurementState());
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _autoStopTimer?.cancel();
    _pauseCleanupTimer?.cancel();
    _diagSummaryTimer?.cancel();
    _hrSub?.cancel();
    _ringProvider?.removeListener(_onRingStateChanged);
    super.dispose();
  }
}
