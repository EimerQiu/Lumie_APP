import 'package:shared_preferences/shared_preferences.dart';

/// Workout-related user preferences stored locally.
class WorkoutPrefsService {
  static const _keyWeightUnit = 'workout_weight_unit';

  /// Returns 'lbs' or 'kg'. Defaults to 'lbs'.
  static Future<String> getWeightUnit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWeightUnit) ?? 'lbs';
  }

  /// Persists the preferred weight unit ('lbs' or 'kg').
  static Future<void> setWeightUnit(String unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWeightUnit, unit);
  }
}
