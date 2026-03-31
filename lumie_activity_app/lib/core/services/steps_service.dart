import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/steps_models.dart';
import '../../shared/models/ring_models.dart';
export '../../shared/models/steps_models.dart' show ActivityGoalType, ActivityGoalSettings;

/// Syncs ring step data to the backend and reads daily step history.
class StepsService {
  static final StepsService _instance = StepsService._internal();
  factory StepsService() => _instance;
  StepsService._internal();

  final AuthService _authService = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─── Ring sync ────────────────────────────────────────────────────────────

  /// Upload raw daily step records from the ring to the backend.
  /// Best-effort — errors are silently swallowed so the UI isn't blocked.
  Future<void> syncFromRingRecords(List<RingRawDailySteps> records) async {
    if (records.isEmpty) return;
    final payload = {
      'records': records
          .map((r) => {
                'date_str': _fmtDate(r.date),
                'steps': r.steps,
                'exercise_time_seconds': r.exerciseTimeSeconds,
                'distance_km': r.distanceKm,
              })
          .toList(),
    };
    try {
      await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/steps/sync'),
            headers: _headers,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  // ─── Read endpoints ───────────────────────────────────────────────────────

  /// Return daily step records in [start, end], newest first.
  Future<List<DailyStepData>> getHistory({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}/steps/history'
              '?start=${start.toIso8601String()}&end=${end.toIso8601String()}',
            ),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((d) => DailyStepData.fromJson(d as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Return the adaptive activity goal for [date] (defaults to today).
  Future<StepGoal?> getGoal(DateTime date) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}/steps/goal'
              '?date=${date.toIso8601String()}',
            ),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return StepGoal.fromJson(json.decode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ─── Goal settings ────────────────────────────────────────────────────────

  /// Fetch the user's persisted goal-type preference + condition defaults.
  Future<ActivityGoalSettings?> getGoalSettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}/steps/goal-settings'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return ActivityGoalSettings.fromJson(
            json.decode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Persist the user's goal-type preference and optional manual override.
  Future<ActivityGoalSettings?> updateGoalSettings(ActivityGoalSettings settings) async {
    try {
      final response = await http
          .put(
            Uri.parse('${ApiConstants.baseUrl}/steps/goal-settings'),
            headers: _headers,
            body: json.encode(settings.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ActivityGoalSettings.fromJson(
            json.decode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }
}
