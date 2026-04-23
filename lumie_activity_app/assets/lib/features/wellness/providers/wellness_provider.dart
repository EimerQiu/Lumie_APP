import 'package:flutter/foundation.dart';
import '../../../core/services/sleep_service.dart';
import '../../../core/services/wellness_service.dart';
import '../../../shared/models/sleep_models.dart';
import '../../../shared/models/wellness_models.dart';

class WellnessProvider extends ChangeNotifier {
  final SleepService _sleepService = SleepService();
  final WellnessService _wellnessService = WellnessService();

  WellnessState _state = WellnessState.loading;
  List<SleepSession> _recentSessions = [];
  bool _isLoading = false;

  WellnessState get state => _state;
  FatigueState get fatigue => _state.fatigue;
  StressState get stress => _state.stress;
  WellnessContext? get context => _state.context;
  bool get isLoading => _isLoading;

  /// The raw sleep sessions that were used to compute the wellness state.
  /// Available to detail screens for per-night trend visualisation.
  List<SleepSession> get recentSessions => _recentSessions;

  /// Fetches the last 14 days of sleep history and recomputes wellness scores.
  /// Safe to call multiple times — debounced if already loading.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now().toUtc();
      final sessions = await _sleepService.getSleepHistory(
        startDate: now.subtract(const Duration(days: 14)),
        endDate: now,
      );

      _recentSessions = sessions;
      _state = _wellnessService.compute(sessions);
    } catch (e) {
      debugPrint('[Wellness] Failed to load: $e');
      // Keep existing state on error — don't downgrade to noData
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearOnLogout() {
    _state = WellnessState.loading;
    _recentSessions = [];
    _isLoading = false;
    notifyListeners();
  }
}
