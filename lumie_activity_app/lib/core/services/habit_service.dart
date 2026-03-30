/// Habit Tracker API service.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/habit_models.dart';

class HabitService {
  static final HabitService _instance = HabitService._internal();
  factory HabitService() => _instance;
  HabitService._internal();

  final AuthService _auth = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_auth.token}',
      };

  String _todayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Fetch today's habit entry, or null if not yet logged.
  Future<HabitEntry?> getTodayEntry() async {
    final date = _todayDate();
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/habit/entry/$date'),
      headers: _headers,
    ).timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      final body = response.body;
      if (body == 'null' || body.isEmpty) return null;
      return HabitEntry.fromJson(json.decode(body) as Map<String, dynamic>);
    }
    throw Exception('Failed to load habit entry: ${response.statusCode}');
  }

  /// Save (upsert) today's habit entry. Only non-null fields are written.
  Future<HabitEntry> saveEntry({
    int? mood,
    String? energy,
    String? hunger,
    String? workload,
    String? fatigue,
    double? conditionMetric,
  }) async {
    final body = <String, dynamic>{'date': _todayDate()};
    if (mood != null) body['mood'] = mood;
    if (energy != null) body['energy'] = energy;
    if (hunger != null) body['hunger'] = hunger;
    if (workload != null) body['workload'] = workload;
    if (fatigue != null) body['fatigue'] = fatigue;
    if (conditionMetric != null) body['condition_metric'] = conditionMetric;

    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/habit/entry'),
      headers: _headers,
      body: json.encode(body),
    ).timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return HabitEntry.fromJson(
          json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Failed to save habit entry: ${response.statusCode}');
  }
}
