/// Task Service - API client for Med-Reminder operations

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../shared/models/task_models.dart';
import '../../shared/models/subscription_error.dart';

class TaskService {
  // Singleton pattern (identical to TeamService)
  static final TaskService _instance = TaskService._internal();
  factory TaskService() => _instance;
  TaskService._internal();

  String? _token;

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Parse subscription error from 403 response
  SubscriptionErrorResponse? _parseSubscriptionError(dynamic responseBody) {
    try {
      if (responseBody is Map<String, dynamic> &&
          responseBody.containsKey('error')) {
        return SubscriptionErrorResponse.fromJson(responseBody);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Handle standard error responses
  Never _handleError(http.Response response, String action) {
    if (response.statusCode == 403) {
      final body = json.decode(response.body);
      // Check if it's a nested detail with error inside
      final errorBody = body is Map<String, dynamic> && body.containsKey('detail') && body['detail'] is Map
          ? body['detail'] as Map<String, dynamic>
          : body;
      final errorResponse = _parseSubscriptionError(errorBody);
      if (errorResponse != null && errorResponse.isSubscriptionError) {
        throw SubscriptionLimitException(errorResponse);
      }
      throw Exception(body['detail'] ?? 'Permission denied');
    }
    final error = json.decode(response.body);
    throw Exception(error['detail'] ?? 'Failed to $action');
  }

  // ============ Task Operations ============

  /// Create a new task
  Future<Task> createTask({
    required String taskName,
    required String taskType,
    required String openDatetime,
    required String closeDatetime,
    String? userId,
    String? teamId,
    String? rpttaskId,
    String? taskInfo,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/tasks'),
      headers: _headers,
      body: json.encode({
        'task_name': taskName,
        'task_type': taskType,
        'open_datetime': openDatetime,
        'close_datetime': closeDatetime,
        if (userId != null) 'user_id': userId,
        if (teamId != null) 'team_id': teamId,
        if (rpttaskId != null) 'rpttask_id': rpttaskId,
        if (taskInfo != null) 'task_info': taskInfo,
      }),
    );

    if (response.statusCode == 201) {
      return Task.fromJson(json.decode(response.body));
    }
    _handleError(response, 'create task');
  }

  /// Get tasks for current user
  Future<TaskListResponse> getTasks({
    String? status,
    String? date,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (date != null) queryParams['date'] = date;

    final uri = Uri.parse('${ApiConstants.baseUrl}/tasks')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      return TaskListResponse.fromJson(json.decode(response.body));
    }
    _handleError(response, 'get tasks');
  }

  /// Complete a task
  Future<Task> completeTask(String taskId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/tasks/$taskId/complete'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    }
    _handleError(response, 'complete task');
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/tasks/$taskId'),
      headers: _headers,
    );

    if (response.statusCode == 200) return;
    _handleError(response, 'delete task');
  }

  // ============ Template Operations ============

  /// Get all templates
  Future<TemplateListResponse> getTemplates() async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/tasks/templates'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return TemplateListResponse.fromJson(json.decode(response.body));
    }
    _handleError(response, 'get templates');
  }

  /// Create a template
  Future<RepeatTaskTemplate> createTemplate({
    required String templateName,
    required String templateType,
    String? description,
    required int minInterval,
    required List<Map<String, dynamic>> timeWindowList,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/tasks/templates'),
      headers: _headers,
      body: json.encode({
        'template_name': templateName,
        'template_type': templateType,
        if (description != null) 'description': description,
        'min_interval': minInterval,
        'time_window_list': timeWindowList,
      }),
    );

    if (response.statusCode == 201) {
      return RepeatTaskTemplate.fromJson(json.decode(response.body));
    }
    _handleError(response, 'create template');
  }

  /// Get template detail
  Future<RepeatTaskTemplate> getTemplate(String templateId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/tasks/templates/$templateId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return RepeatTaskTemplate.fromJson(json.decode(response.body));
    }
    _handleError(response, 'get template');
  }

  /// Delete a template
  Future<void> deleteTemplate(String templateId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/tasks/templates/$templateId'),
      headers: _headers,
    );

    if (response.statusCode == 200) return;
    _handleError(response, 'delete template');
  }

  // ============ Batch Operations ============

  /// Preview batch generation
  Future<Map<String, dynamic>> batchPreview({
    required String templateId,
    required String taskName,
    required String startDate,
    required String endDate,
    String? teamId,
    String? userId,
    String? taskInfo,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/tasks/batch/preview'),
      headers: _headers,
      body: json.encode({
        'template_id': templateId,
        'task_name': taskName,
        'start_date': startDate,
        'end_date': endDate,
        if (teamId != null) 'team_id': teamId,
        if (userId != null) 'user_id': userId,
        if (taskInfo != null) 'task_info': taskInfo,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _handleError(response, 'preview batch');
  }

  /// Execute batch generation
  Future<List<Task>> batchGenerate({
    required String templateId,
    required String taskName,
    required String startDate,
    required String endDate,
    String? teamId,
    String? userId,
    String? taskInfo,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/tasks/batch/generate'),
      headers: _headers,
      body: json.encode({
        'template_id': templateId,
        'task_name': taskName,
        'start_date': startDate,
        'end_date': endDate,
        if (teamId != null) 'team_id': teamId,
        if (userId != null) 'user_id': userId,
        if (taskInfo != null) 'task_info': taskInfo,
      }),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return (data['tasks'] as List)
          .map((t) => Task.fromJson(t as Map<String, dynamic>))
          .toList();
    }
    _handleError(response, 'generate tasks');
  }
}
