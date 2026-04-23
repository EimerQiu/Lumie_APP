import 'package:flutter/foundation.dart';
import '../../../core/services/stress_service.dart';
import '../../../shared/models/stress_models.dart';

class StressProvider extends ChangeNotifier {
  final StressService _service = StressService();

  StressDaySummary? _today;
  StressWeekData? _weekData;
  bool _isLoading = false;

  StressDaySummary? get today => _today;
  StressWeekData? get weekData => _weekData;
  bool get isLoading => _isLoading;

  /// Current stress zone (last reading from today's timeline).
  StressZone? get currentZone => _today?.currentZone;

  /// Daily stress score (0–100, higher = better).
  int get score => _today?.score ?? 0;

  /// Human-readable score label (e.g. "Balanced").
  String get scoreLabel => _today?.scoreLabel ?? '';

  /// Whether enough baseline data exists to show stress zones.
  bool get hasBaseline => (_today?.baselineDaysCollected ?? 0) >= 5;

  /// Whether today has any data at all.
  bool get hasData => _today?.hasData ?? false;

  /// Baseline days collected so far (for calibration UI).
  int get baselineDays => _today?.baselineDaysCollected ?? 0;

  /// Load today's stress data and 7-day history.
  /// Safe to call multiple times — debounced if already loading.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.getTodayStress(),
        _service.getWeekStress(),
      ]);
      _today = results[0] as StressDaySummary;
      _weekData = results[1] as StressWeekData;
    } catch (e) {
      debugPrint('[Stress] Failed to load: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearOnLogout() {
    _today = null;
    _weekData = null;
    _isLoading = false;
    notifyListeners();
  }
}
