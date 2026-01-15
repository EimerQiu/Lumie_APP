import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../shared/models/activity_models.dart';

/// API service for communicating with the Lumie backend
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final String _baseUrl = ApiConstants.baseUrl;

  Future<Map<String, dynamic>> _get(String endpoint) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$endpoint'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch data: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> _getList(String endpoint) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$endpoint'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch data: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_baseUrl$endpoint'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    ).timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to post data: ${response.statusCode}');
    }
  }

  // Activity Types
  Future<List<ActivityType>> getActivityTypes() async {
    final data = await _getList(ApiConstants.activityTypes);
    return data.map((json) => ActivityType(
      id: json['id'],
      name: json['name'],
      icon: json['icon'],
      category: json['category'],
    )).toList();
  }

  // Daily Summary
  Future<DailyActivitySummary> getDailySummary({DateTime? date}) async {
    String endpoint = ApiConstants.dailySummary;
    if (date != null) {
      endpoint += '?date=${date.toIso8601String()}';
    }
    final data = await _get(endpoint);
    return DailyActivitySummary.fromJson(data);
  }

  // Weekly Summary
  Future<List<DailyActivitySummary>> getWeeklySummary({DateTime? endDate}) async {
    String endpoint = ApiConstants.weeklySummary;
    if (endDate != null) {
      endpoint += '?end_date=${endDate.toIso8601String()}';
    }
    final data = await _getList(endpoint);
    return data.map((json) => DailyActivitySummary.fromJson(json)).toList();
  }

  // Adaptive Goal
  Future<AdaptiveGoal> getAdaptiveGoal({DateTime? date}) async {
    String endpoint = ApiConstants.adaptiveGoal;
    if (date != null) {
      endpoint += '?date=${date.toIso8601String()}';
    }
    final data = await _get(endpoint);
    return AdaptiveGoal.fromJson(data);
  }

  // Create Activity
  Future<ActivityRecord> createActivity({
    required String activityTypeId,
    required DateTime startTime,
    required DateTime endTime,
    ActivityIntensity? intensity,
    required ActivitySource source,
    bool isEstimated = false,
    int? heartRateAvg,
    int? heartRateMax,
    String? notes,
  }) async {
    final body = {
      'activity_type_id': activityTypeId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'intensity': intensity?.name,
      'source': source.name,
      'is_estimated': isEstimated,
      'heart_rate_avg': heartRateAvg,
      'heart_rate_max': heartRateMax,
      'notes': notes,
    };
    final data = await _post(ApiConstants.activity, body);
    return ActivityRecord.fromJson(data);
  }

  // Ring Status
  Future<Map<String, dynamic>> getRingStatus() async {
    return await _get(ApiConstants.ringStatus);
  }

  // Detected Activities
  Future<List<RingDetectedActivity>> getDetectedActivities() async {
    final data = await _getList(ApiConstants.ringDetected);
    return data.map((json) => RingDetectedActivity.fromJson(json)).toList();
  }

  // Walk Test History
  Future<List<WalkTestResult>> getWalkTestHistory({int limit = 10}) async {
    final data = await _getList('${ApiConstants.walkTestHistory}?limit=$limit');
    return data.map((json) => WalkTestResult.fromJson(json)).toList();
  }

  // Create Walk Test
  Future<WalkTestResult> createWalkTest({
    required double distanceMeters,
    required int durationSeconds,
    int? avgHeartRate,
    int? maxHeartRate,
    int? recoveryHeartRate,
    String? notes,
  }) async {
    final body = {
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'avg_heart_rate': avgHeartRate,
      'max_heart_rate': maxHeartRate,
      'recovery_heart_rate': recoveryHeartRate,
      'notes': notes,
    };
    final data = await _post(ApiConstants.walkTest, body);
    return WalkTestResult.fromJson(data);
  }

  // Best Walk Test
  Future<WalkTestResult?> getBestWalkTest() async {
    try {
      final data = await _get(ApiConstants.walkTestBest);
      return WalkTestResult.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  // Health Check
  Future<bool> healthCheck() async {
    try {
      await _get(ApiConstants.health);
      return true;
    } catch (_) {
      return false;
    }
  }
}
