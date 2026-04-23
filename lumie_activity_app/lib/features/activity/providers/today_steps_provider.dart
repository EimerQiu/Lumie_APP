import 'package:flutter/foundation.dart';
import '../../../core/services/steps_service.dart';
import '../../../shared/models/steps_models.dart';
import '../../ring/providers/ring_provider.dart';

/// Single source of truth for today's step and active-time data.
///
/// Both the dashboard (Today page) and the Activity History screen read from
/// this provider, so it is impossible for them to show different counts.
///
/// Data flow:
///   1. On first load (or when ring connects), syncs ring BLE step history
///      to the backend via [StepsService.syncFromRingRecords].
///   2. Fetches today's [DailyStepData] from the backend.
///   3. Notifies all listeners — every widget watching this rebuilds at once.
class TodayStepsProvider extends ChangeNotifier {
  final StepsService _service = StepsService();

  DailyStepData? _today;
  bool _isLoading = false;

  RingProvider? _ringProvider;
  bool _lastRingConnected = false;

  // ─── Getters ──────────────────────────────────────────────────────────────

  DailyStepData? get today => _today;
  bool get isLoading => _isLoading;
  bool get hasData => _today != null;

  /// Today's ring-synced step count. Zero when data is not yet available.
  int get todaySteps => _today?.steps ?? 0;

  /// Today's active minutes (ring exercise_time_seconds ÷ 60). Zero when
  /// data is not yet available.
  int get todayActiveMinutes => _today?.activeMinutes ?? 0;

  // ─── Ring provider wiring ─────────────────────────────────────────────────

  /// Called by the [ChangeNotifierProxyProvider] in main.dart whenever
  /// [RingProvider] changes.  Sets up the ring-connect listener and triggers
  /// an initial load if data has not been fetched yet.
  void updateRingProvider(RingProvider ring) {
    if (_ringProvider == ring) return;
    _ringProvider?.removeListener(_onRingStateChanged);
    _ringProvider = ring;
    _lastRingConnected = ring.isConnected;
    ring.addListener(_onRingStateChanged);
    // Trigger an initial fetch if we have no data yet.
    if (_today == null && !_isLoading) load();
  }

  void _onRingStateChanged() {
    final ring = _ringProvider;
    if (ring == null) return;
    final nowConnected = ring.isConnected;
    if (nowConnected && !_lastRingConnected) {
      // Ring just connected — sync fresh data.
      load();
    }
    _lastRingConnected = nowConnected;
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  /// Sync ring data (if connected) then fetch today from the backend.
  /// Re-entrant safe: if a load is already in progress, this is a no-op.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Sync ring → backend if connected.
      final ring = _ringProvider;
      if (ring != null && ring.isConnected) {
        final records = await ring.fetchStepHistory();
        if (records.isNotEmpty) {
          await _service.syncFromRingRecords(records);
        }
      }

      // 2. Fetch today's record from the backend.
      final now = DateTime.now();
      final history = await _service.getHistory(
        start: DateTime(now.year, now.month, now.day),
        end: now,
      );
      final todayStr = _fmtDate(now);
      _today = history.where((h) => h.dateStr == todayStr).firstOrNull;
    } catch (e) {
      debugPrint('[TodaySteps] load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  void clearOnLogout() {
    _ringProvider?.removeListener(_onRingStateChanged);
    _ringProvider = null;
    _lastRingConnected = false;
    _today = null;
    _isLoading = false;
    notifyListeners();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
