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
  int? _finalHr;

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
  int? get liveHr => _finalHr;
  int? get finalHr => _finalHr;

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

    _measureState = HrMeasureState.measuring;
    _finalHr = null;
    notifyListeners();

    try {
      final result = await _ringProvider!.measureHeartRate(durationSeconds: 30);
      _finalHr = result?.avgBpm;

      if (result != null) {
        _dailyReadings = [
          ..._dailyReadings,
          HrDataPoint(time: DateTime.now(), bpm: result.avgBpm),
        ];
      }
      _measureState = HrMeasureState.done;
    } catch (e) {
      _measureState = HrMeasureState.idle;
      debugPrint('[RCMD] HeartRateProvider.startMeasurement error: $e');
    }
    notifyListeners();
  }

  Future<void> stopMeasurement() async {
    if (_measureState != HrMeasureState.measuring) return;
    // The unified measureHeartRate flow is a single awaited BLE operation.
    // We keep the Stop action as a soft reset for the UI only.
    _measureState = HrMeasureState.idle;
    _finalHr = null;
    notifyListeners();
  }

  void resetMeasurement() {
    _measureState = HrMeasureState.idle;
    _finalHr = null;
    notifyListeners();
  }
}
