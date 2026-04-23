/// Workout Service — API client for exercises, templates, sessions, and PRs.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../shared/models/workout_plan_models.dart';
import '../../shared/models/subscription_error.dart';

class WorkoutApiService {
  static final WorkoutApiService _instance = WorkoutApiService._internal();
  factory WorkoutApiService() => _instance;
  WorkoutApiService._internal();

  String? _token;

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Never _handleError(http.Response response, String action) {
    if (response.statusCode == 403) {
      final body = json.decode(response.body);
      final errorBody = body is Map<String, dynamic> &&
              body.containsKey('detail') &&
              body['detail'] is Map
          ? body['detail'] as Map<String, dynamic>
          : body;
      if (errorBody is Map<String, dynamic> &&
          errorBody.containsKey('error')) {
        final errResp = SubscriptionErrorResponse.fromJson(errorBody);
        if (errResp.isSubscriptionError) {
          throw SubscriptionLimitException(errResp);
        }
      }
      throw Exception(body['detail'] ?? 'Permission denied');
    }
    final error = json.decode(response.body);
    throw Exception(error['detail'] ?? 'Failed to $action');
  }

  // ── Exercises ─────────────────────────────────────────────────────────────

  Future<List<ExerciseDefinition>> listExercises({
    String? muscleGroup,
    String? equipmentType,
    String? movementType,
    String? search,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final params = <String, String>{};
    if (muscleGroup != null) params['muscle_group'] = muscleGroup;
    if (equipmentType != null) params['equipment_type'] = equipmentType;
    if (movementType != null) params['movement_type'] = movementType;
    if (search != null && search.isNotEmpty) params['search'] = search;

    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.exercises}')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) _handleError(response, 'list exercises');

    final body = json.decode(response.body) as Map<String, dynamic>;
    final list = body['exercises'] as List<dynamic>;
    return list
        .map((e) => ExerciseDefinition.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ExerciseDefinition> getExercise(String exerciseId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.exercises}/$exerciseId'),
      headers: _headers,
    );
    if (response.statusCode != 200) _handleError(response, 'get exercise');
    return ExerciseDefinition.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<ExerciseDefinition> createExercise({
    required String name,
    String description = '',
    List<String> primaryMuscles = const [],
    List<String> secondaryMuscles = const [],
    required String equipmentType,
    String movementType = 'isolation',
    String formDescription = '',
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.exercises}'),
      headers: _headers,
      body: json.encode({
        'name': name,
        'description': description,
        'primary_muscles': primaryMuscles,
        'secondary_muscles': secondaryMuscles,
        'equipment_type': equipmentType,
        'movement_type': movementType,
        'form_description': formDescription,
      }),
    );
    if (response.statusCode != 201) _handleError(response, 'create exercise');
    return ExerciseDefinition.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<bool> deleteExercise(String exerciseId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.delete(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.exercises}/$exerciseId'),
      headers: _headers,
    );
    return response.statusCode == 200;
  }

  // ── Templates ─────────────────────────────────────────────────────────────

  Future<List<WorkoutTemplate>> listTemplates() async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutTemplates}'),
      headers: _headers,
    );
    if (response.statusCode != 200) _handleError(response, 'list templates');

    final body = json.decode(response.body) as Map<String, dynamic>;
    final list = body['templates'] as List<dynamic>;
    return list
        .map((t) => WorkoutTemplate.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<WorkoutTemplate> getTemplate(String templateId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutTemplates}/$templateId'),
      headers: _headers,
    );
    if (response.statusCode != 200) _handleError(response, 'get template');
    return WorkoutTemplate.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<WorkoutTemplate> createTemplate({
    required String name,
    String emoji = '💪',
    String splitType = 'full_body',
    String? splitDayLabel,
    String? splitGroupId,
    List<Map<String, dynamic>> blocks = const [],
    int restDurationSeconds = 60,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.post(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutTemplates}'),
      headers: _headers,
      body: json.encode({
        'name': name,
        'emoji': emoji,
        'split_type': splitType,
        'split_day_label': splitDayLabel,
        'split_group_id': splitGroupId,
        'blocks': blocks,
        'rest_duration_seconds': restDurationSeconds,
      }),
    );
    if (response.statusCode != 201) _handleError(response, 'create template');
    return WorkoutTemplate.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<WorkoutTemplate> updateTemplate(
    String templateId,
    Map<String, dynamic> updates,
  ) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.put(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutTemplates}/$templateId'),
      headers: _headers,
      body: json.encode(updates),
    );
    if (response.statusCode != 200) _handleError(response, 'update template');
    return WorkoutTemplate.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<bool> deleteTemplate(String templateId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.delete(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutTemplates}/$templateId'),
      headers: _headers,
    );
    return response.statusCode == 200;
  }

  Future<WorkoutTemplate> duplicateTemplate(String templateId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.post(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutTemplates}/$templateId/duplicate'),
      headers: _headers,
    );
    if (response.statusCode != 201) {
      _handleError(response, 'duplicate template');
    }
    return WorkoutTemplate.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  // ── Sessions ──────────────────────────────────────────────────────────────

  Future<WorkoutSession> createSession({
    required Map<String, dynamic> sessionData,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.post(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutSessions}'),
      headers: _headers,
      body: json.encode(sessionData),
    );
    if (response.statusCode != 201) _handleError(response, 'save session');
    return WorkoutSession.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<List<WorkoutSession>> listSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutSessions}?limit=$limit&offset=$offset'),
      headers: _headers,
    );
    if (response.statusCode != 200) _handleError(response, 'list sessions');

    final body = json.decode(response.body) as Map<String, dynamic>;
    final list = body['sessions'] as List<dynamic>;
    return list
        .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<WorkoutSession> getSession(String sessionId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutSessions}/$sessionId'),
      headers: _headers,
    );
    if (response.statusCode != 200) _handleError(response, 'get session');
    return WorkoutSession.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  Future<WorkoutSession> updateSession(
    String sessionId,
    Map<String, dynamic> updates,
  ) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.put(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutSessions}/$sessionId'),
      headers: _headers,
      body: json.encode(updates),
    );
    if (response.statusCode != 200) _handleError(response, 'update session');
    return WorkoutSession.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  // ── Personal Records ──────────────────────────────────────────────────────

  Future<List<PersonalRecord>> listPersonalRecords() async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.personalRecords}'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      _handleError(response, 'list personal records');
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final list = body['records'] as List<dynamic>;
    return list
        .map((r) => PersonalRecord.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // ── Overload Advice ───────────────────────────────────────────────────────

  Future<List<OverloadSuggestion>> getOverloadAdvice(
      String templateId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.workoutTemplates}/$templateId/overload-advice'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      _handleError(response, 'get overload advice');
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final list = body['suggestions'] as List<dynamic>;
    return list
        .map((s) => OverloadSuggestion.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  // ── Exercise History ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getExerciseHistory(
    String exerciseId, {
    int limit = 20,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse(
          '${ApiConstants.baseUrl}${ApiConstants.exercises}/$exerciseId/history?limit=$limit'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      _handleError(response, 'get exercise history');
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['history'] as List);
  }
}
