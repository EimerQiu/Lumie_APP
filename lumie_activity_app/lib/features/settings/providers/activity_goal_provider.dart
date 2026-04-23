import 'package:flutter/foundation.dart';
import '../../../core/services/steps_service.dart';

/// Holds the user's activity goal preference (steps vs. minutes, custom override)
/// and the condition-adjusted defaults fetched from the backend.
///
/// Loaded once on startup; updated whenever the user changes their preference
/// via the Activity Goal settings screen.
class ActivityGoalProvider extends ChangeNotifier {
  final StepsService _service = StepsService();

  ActivityGoalSettings _settings = const ActivityGoalSettings(
    goalType: ActivityGoalType.minutes,
    defaultSteps: 8000,
    defaultMinutes: 60,
    conditionAdjusted: false,
  );

  bool _isLoading = false;

  ActivityGoalSettings get settings => _settings;
  bool get isLoading => _isLoading;

  ActivityGoalType get goalType => _settings.goalType;

  /// Effective goal in minutes — used by the activity ring on the dashboard.
  int get effectiveGoalMinutes => _settings.effectiveGoalMinutes;

  /// Effective goal in steps — used when user chooses steps mode.
  int get effectiveGoalSteps => _settings.effectiveGoalSteps;

  /// Human-readable goal string, e.g. "8 000 steps" or "60 min".
  String get goalLabel {
    if (_settings.goalType == ActivityGoalType.steps) {
      return '${_settings.effectiveGoalSteps} steps';
    }
    return '${_settings.effectiveGoalMinutes} min';
  }

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final fetched = await _service.getGoalSettings();
      if (fetched != null) _settings = fetched;
    } catch (e) {
      debugPrint('[ActivityGoal] load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save both goal type and custom override atomically.
  /// Called exclusively from the Activity Goal screen when the user taps Save.
  Future<void> saveSettings(ActivityGoalType type, int? customGoal) async {
    await _applyUpdate(_settings.copyWith(goalType: type, customGoal: customGoal));
  }

  /// Persist a new goal type.  Converts custom_goal to the new unit when
  /// switching between steps and minutes so the numeric value stays sensible.
  Future<void> setGoalType(ActivityGoalType type) async {
    if (type == _settings.goalType) return;

    // Convert existing custom override to new unit
    int? newCustom = _settings.customGoal;
    if (newCustom != null) {
      if (type == ActivityGoalType.steps) {
        newCustom = (newCustom * 8000 / 60).round(); // min → steps
      } else {
        newCustom = (newCustom * 60 / 8000).round(); // steps → min
      }
    }

    await _applyUpdate(_settings.copyWith(goalType: type, customGoal: newCustom));
  }

  /// Persist a manual goal override.  Pass `null` to revert to the
  /// condition-adjusted default.
  Future<void> setCustomGoal(int? value) async {
    await _applyUpdate(_settings.copyWith(customGoal: value));
  }

  Future<void> _applyUpdate(ActivityGoalSettings next) async {
    _settings = next;
    notifyListeners();
    try {
      final saved = await _service.updateGoalSettings(next);
      if (saved != null) {
        _settings = saved;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ActivityGoal] update error: $e');
    }
  }

  void clearOnLogout() {
    _settings = const ActivityGoalSettings(
      goalType: ActivityGoalType.minutes,
      defaultSteps: 8000,
      defaultMinutes: 60,
      conditionAdjusted: false,
    );
    _isLoading = false;
    notifyListeners();
  }
}
