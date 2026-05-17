import 'package:flutter/foundation.dart';
import '../../../core/services/workout_service.dart';
import '../../../shared/models/workout_plan_models.dart';

enum WorkoutHistoryState { initial, loading, loaded, error }

class WorkoutHistoryProvider extends ChangeNotifier {
  final WorkoutApiService _api = WorkoutApiService();

  WorkoutHistoryState _state = WorkoutHistoryState.initial;
  WorkoutHistoryState get state => _state;

  List<WorkoutSession> _sessions = [];
  List<WorkoutSession> get sessions => _sessions;

  String? _error;
  String? get error => _error;

  void setToken(String token) => _api.setToken(token);
  void clearToken() => _api.clearToken();

  Future<void> loadSessions({int limit = 20, bool force = false}) async {
    if (_state == WorkoutHistoryState.loaded && !force) return;
    _state = WorkoutHistoryState.loading;
    _error = null;
    notifyListeners();

    try {
      _sessions = await _api.listSessions(limit: limit);
      _state = WorkoutHistoryState.loaded;
    } catch (e) {
      _error = e.toString();
      _state = WorkoutHistoryState.error;
    }

    notifyListeners();
  }

  void addSession(WorkoutSession session) {
    _sessions.insert(0, session);
    notifyListeners();
  }

  void reset() {
    _sessions = [];
    _state = WorkoutHistoryState.initial;
    _error = null;
    notifyListeners();
  }
}
