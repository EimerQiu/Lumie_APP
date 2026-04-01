import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../../../shared/models/heart_rate_models.dart';
import '../../ring/providers/ring_provider.dart';

enum HrMeasureState { idle, measuring, done }

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
  Duration _elapsed = Duration.zero;
  int? _currentBpm; // latest filtered reading

  static const Duration _maxDuration = Duration(hours: 1, minutes: 30);

  // Adaptive EMA smoothing parameters
  static const double _minAlpha = 0.15; // smooth during stable periods
  static const double _maxAlpha = 0.6;  // responsive during rapid changes
  double _emaValue = 0.0;
  int _previousRaw = 0;
  int _stabilityCounter = 0;

  // ─── ProxyProvider bridge ─────────────────────────────────────────────────

  void updateRingProvider(RingProvider ring) {
    final wasPaired = _ringProvider?.isPaired ?? false;
    _ringProvider = ring;
    if (!wasPaired && ring.isPaired) {
      fetchDailyHistory();
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
  List<HrSessionPoint> get sessionReadings => List.unmodifiable(_sessionReadings);

  int? get sessionMin => _sessionReadings.isEmpty
      ? null
      : _sessionReadings.map((e) => e.smoothedBpm.toInt()).reduce(min);

  int? get sessionMax => _sessionReadings.isEmpty
      ? null
      : _sessionReadings.map((e) => e.smoothedBpm.toInt()).reduce(max);

  int? get sessionAvg => _sessionReadings.isEmpty
      ? null
      : (_sessionReadings.map((e) => e.smoothedBpm).reduce((a, b) => a + b) /
                _sessionReadings.length)
            .round();

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
    _measureState = HrMeasureState.measuring;
    notifyListeners();

    final stream = _ringProvider!.startHrStreaming();
    _hrSub = stream.listen(_onRawReading, onError: (e) {
      debugPrint('[HR] stream error: $e');
    });

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });

    _autoStopTimer = Timer(_maxDuration, () {
      stopMeasurement();
    });
  }

  void _onRawReading(int raw) {
    if (raw < 30 || raw > 220) return; // reject implausible values
    final smoothed = _adaptiveEMA(raw);
    _currentBpm = smoothed.toInt();
    // Only record to session once the warmup phase is complete
    if (!isWarmingUp) {
      _sessionReadings.add(HrSessionPoint(
        time: DateTime.now(),
        rawBpm: raw,
        smoothedBpm: smoothed,
      ));
    }
    notifyListeners();
  }

  Future<void> stopMeasurement() async {
    if (_measureState != HrMeasureState.measuring) return;

    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    await _hrSub?.cancel();
    _hrSub = null;
    await _ringProvider?.stopHrStreaming();

    // Append session avg to daily history
    final avg = sessionAvg;
    if (avg != null) {
      _dailyReadings = [
        ..._dailyReadings,
        HrDataPoint(time: DateTime.now(), bpm: avg),
      ];
    }

    _measureState = HrMeasureState.done;
    notifyListeners();
  }

  void resetMeasurement() {
    _measureState = HrMeasureState.idle;
    _currentBpm = null;
    _sessionReadings.clear();
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
    _hrSub?.cancel();
    super.dispose();
  }
}
