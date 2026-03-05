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
  int? _liveHr;
  int? _finalHr;
  StreamSubscription<int>? _hrSub;

  // ─── ProxyProvider bridge ─────────────────────────────────────────────────

  void updateRingProvider(RingProvider ring) {
    final wasPaired = _ringProvider?.isPaired ?? false;
    _ringProvider = ring;
    // Fetch history once when ring first becomes paired
    if (!wasPaired && ring.isPaired) {
      fetchDailyHistory();
    }
  }

  // ─── Public getters ───────────────────────────────────────────────────────

  List<HrDataPoint> get dailyReadings => _dailyReadings;
  bool get loadingHistory => _loadingHistory;
  HrMeasureState get measureState => _measureState;
  int? get liveHr => _liveHr;
  int? get finalHr => _finalHr;

  int? get latestHr =>
      _dailyReadings.isEmpty ? null : _dailyReadings.last.bpm;

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
    if (_ringProvider == null || !_ringProvider!.isPaired) return;
    if (_measureState == HrMeasureState.measuring) return;

    _measureState = HrMeasureState.measuring;
    _liveHr = null;
    _finalHr = null;
    notifyListeners();

    final stream = _ringProvider!.startHrStreaming();
    _hrSub = stream.listen((hr) {
      _liveHr = hr;
      notifyListeners();
    });

  }

  Future<void> stopMeasurement() async {
    if (_measureState != HrMeasureState.measuring) return;

    await _hrSub?.cancel();
    _hrSub = null;
    await _ringProvider?.stopHrStreaming();

    _finalHr = _liveHr;
    _measureState = HrMeasureState.done;

    // Append the measurement to today's readings
    if (_finalHr != null) {
      _dailyReadings = [
        ..._dailyReadings,
        HrDataPoint(time: DateTime.now(), bpm: _finalHr!),
      ];
    }
    notifyListeners();
  }

  void resetMeasurement() {
    _measureState = HrMeasureState.idle;
    _liveHr = null;
    _finalHr = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _hrSub?.cancel();
    super.dispose();
  }
}
