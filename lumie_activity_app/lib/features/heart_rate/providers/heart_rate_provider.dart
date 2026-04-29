import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

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

  final List<_HrRange> _pendingBackfillRanges = [];
  final List<_HrRange> _attemptedBackfillRanges = [];
  bool _backfillInProgress = false;
  DateTime? _lastRealtimePointTime;
  DateTime? _measurementStartedAt;
  bool _lastRingConnected = false;

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
    if (!wasPaired && ring.isPaired) {
      fetchDailyHistory();
    }
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

    if (_measureState == HrMeasureState.measuring) {
      // Re-subscribe to the new characteristic so the stream stays live.
      // Also resends 0x28/0x09/0x19 start commands in case the ring lost state.
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
      _enqueueGapsFromSession();
      _kickBackfillIfNeeded();
    } else if (_measureState == HrMeasureState.done) {
      // Stop was tapped while disconnected — send stop commands to the ring now.
      ring.stopHrStreaming().catchError(
        (e) => debugPrint('[HR] delayed stop error: $e'),
      );
    }
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
    _measureState = HrMeasureState.measuring;
    notifyListeners();

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

  void _kickBackfillIfNeeded() {
    if (_backfillInProgress || _measureState != HrMeasureState.measuring) {
      return;
    }
    final ring = _ringProvider;
    if (ring == null || !ring.isConnected) return;
    if (_pendingBackfillRanges.isEmpty) return;
    _runBackfill();
  }

  Future<void> _runBackfill() async {
    if (_backfillInProgress) return;
    _backfillInProgress = true;
    dlog(
      'HR_PROV',
      'backfill begin (pending=${_pendingBackfillRanges.length})',
    );
    try {
      while (_measureState == HrMeasureState.measuring &&
          _pendingBackfillRanges.isNotEmpty &&
          (_ringProvider?.isConnected ?? false)) {
        final gap = _pendingBackfillRanges.removeAt(0);
        _markBackfillAttempted(gap);

        final measurementStart = _measurementStartedAt ?? gap.start;
        var queryStart = gap.start.subtract(_backfillQueryLookback);
        if (queryStart.isBefore(measurementStart)) {
          queryStart = measurementStart;
        }

        final ring = _ringProvider;
        if (ring == null || !ring.isConnected) break;

        final t0 = DateTime.now();
        final results = await Future.wait([
          ring.fetchHrDetailsRange(start: queryStart, end: gap.end),
          ring.fetchHrHistoryRange(start: queryStart, end: gap.end),
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
          gap: gap,
        );
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
    notifyListeners();

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

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      _notifyListenersSinceLastSummary++;
      notifyListeners();
    });

    final remaining = _maxDuration - _elapsed;
    if (remaining > Duration.zero) {
      _autoStopTimer = Timer(remaining, () => stopMeasurement());
    } else {
      stopMeasurement();
      return;
    }

    _measureState = HrMeasureState.measuring;
    notifyListeners();
  }

  Future<void> stopMeasurement() async {
    if (_measureState != HrMeasureState.measuring &&
        _measureState != HrMeasureState.paused) return;
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
    final snapshotReadings = List<HrSessionPoint>.unmodifiable(_sessionReadings);

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
    notifyListeners();

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
    _elapsed = Duration.zero;
    notifyListeners();
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
