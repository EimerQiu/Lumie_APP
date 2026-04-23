import 'package:flutter/foundation.dart';
import '../../../core/services/sleep_service.dart';
import '../../../shared/models/sleep_models.dart';

class SleepProvider extends ChangeNotifier {
  final SleepService _sleepService = SleepService();

  SleepSession? _latestSleep;
  SleepTarget? _sleepTarget;
  bool _isLoading = false;

  SleepSession? get latestSleep => _latestSleep;
  SleepTarget? get sleepTarget => _sleepTarget;
  bool get isLoading => _isLoading;

  /// Mirrors SleepService tracking so the sleep screen can show sync status.
  DateTime? get lastSyncedAt => _sleepService.lastSyncedAt;
  bool get lastSyncWasComplete => _sleepService.lastSyncWasComplete;

  /// Sleep quality score as an integer 0–100, or -1 when no data is available.
  /// The dashboard score card uses -1 to render a "No data" state rather than
  /// a misleading number.
  int get sleepScore {
    if (_latestSleep == null) return -1;
    return _latestSleep!.sleepQualityScore.round().clamp(0, 100);
  }

  /// Fetch latest sleep session + target from the backend.
  /// Safe to call multiple times — debounced if already loading.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _sleepService.getLatestSleep(),
        _sleepService.getSleepTarget(),
      ]);

      final session = results[0] as SleepSession?;
      // Guard: only surface ring-sourced sessions with actual sleep time.
      // If the backend returns something synthetic or empty, treat as no data.
      // Only show data if the ring was worn last night (wake time within 36 h).
      // If the most recent session is older, the user didn't wear the ring last
      // night and we should show the no-data state rather than stale data.
      final isRecent = session != null &&
          DateTime.now().toUtc().difference(session.wakeTime.toUtc()).inHours <=
              36;
      if (session != null &&
          session.source == 'ring' &&
          session.totalSleepTime.inMinutes > 0 &&
          isRecent) {
        _latestSleep = session;
      } else {
        _latestSleep = null;
      }
      _sleepTarget = results[1] as SleepTarget;
    } catch (e) {
      debugPrint('[SleepProvider] load error: $e');
      // Keep previous data on error rather than clearing it.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearOnLogout() {
    _latestSleep = null;
    _sleepTarget = null;
    notifyListeners();
  }
}
