/// Habit Tracker state management.

import 'package:flutter/foundation.dart';
import '../../../core/services/habit_service.dart';
import '../../../shared/models/habit_models.dart';

enum HabitProviderState { initial, loading, loaded, saving, error }

class HabitProvider extends ChangeNotifier {
  final HabitService _service = HabitService();

  HabitProviderState _state = HabitProviderState.initial;
  HabitEntry? _todayEntry;
  String? _errorMessage;

  HabitProviderState get state => _state;
  HabitEntry? get todayEntry => _todayEntry;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == HabitProviderState.loading;
  bool get isSaving => _state == HabitProviderState.saving;
  bool get hasEntry => _todayEntry != null;

  /// Load today's entry from the backend.
  Future<void> loadToday() async {
    if (_state == HabitProviderState.loading) return;
    _state = HabitProviderState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _todayEntry = await _service.getTodayEntry();
      _state = HabitProviderState.loaded;
    } catch (e) {
      _state = HabitProviderState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Save all selected fields for today.
  Future<void> saveEntry({
    int? mood,
    String? energy,
    String? hunger,
    String? workload,
    String? fatigue,
    double? conditionMetric,
  }) async {
    _state = HabitProviderState.saving;
    _errorMessage = null;
    notifyListeners();

    try {
      _todayEntry = await _service.saveEntry(
        mood: mood,
        energy: energy,
        hunger: hunger,
        workload: workload,
        fatigue: fatigue,
        conditionMetric: conditionMetric,
      );
      _state = HabitProviderState.loaded;
    } catch (e) {
      _state = HabitProviderState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }
}
