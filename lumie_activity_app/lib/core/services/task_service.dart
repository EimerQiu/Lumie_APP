/// Task Service - API client for Med-Reminder operations

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../../shared/models/task_models.dart';
import '../../shared/models/subscription_error.dart';

class TaskService {
  // Singleton pattern (identical to TeamService)
  static final TaskService _instance = TaskService._internal();
  factory TaskService() => _instance;
  TaskService._internal();

  String? _token;
  final Dio _dio = Dio();

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
      final errorBody =
          body is Map<String, dynamic> &&
              body.containsKey('detail') &&
              body['detail'] is Map
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
  /// Includes device timezone so backend can convert local times to UTC
  Future<Task> createTask({
    required String taskName,
    required String taskType,
    required String openDatetime,
    required String closeDatetime,
    String? timezone,
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
        if (timezone != null) 'timezone': timezone,
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
  /// Optionally pass device timezone for proper overdue checking while traveling
  Future<TaskListResponse> getTasks({String? date, String? timezone}) async {
    if (_token == null) throw Exception('Not authenticated');

    final queryParams = <String, String>{};
    if (date != null) queryParams['date'] = date;
    if (timezone != null) queryParams['timezone'] = timezone;

    final uri = Uri.parse(
      '${ApiConstants.baseUrl}/tasks',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      return TaskListResponse.fromJson(json.decode(response.body));
    }
    _handleError(response, 'get tasks');
  }

  /// Update an existing task's mutable fields.
  ///
  /// [sendTeamId] / [sendUserId]: when true the field is always included in the
  /// request body (even as null), so the backend's model_fields_set picks it up
  /// and performs the reassignment. Pass false to leave the field untouched.
  Future<Task> updateTask({
    required String taskId,
    String? taskName,
    String? taskType,
    String? openDatetime,
    String? closeDatetime,
    String? timezone,
    String? taskInfo,
    bool sendTeamId = false,
    String? teamId, // null = make personal
    bool sendUserId = false,
    String? userId, // null = assign to self
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{};
    if (taskName != null) body['task_name'] = taskName;
    if (taskType != null) body['task_type'] = taskType;
    if (openDatetime != null) body['open_datetime'] = openDatetime;
    if (closeDatetime != null) body['close_datetime'] = closeDatetime;
    if (timezone != null) body['timezone'] = timezone;
    if (taskInfo != null) body['task_info'] = taskInfo;
    // Always include these when the caller explicitly signals a change,
    // including the null case (personal / self).
    if (sendTeamId) body['team_id'] = teamId;
    if (sendUserId) body['user_id'] = userId;

    final response = await http.patch(
      Uri.parse('${ApiConstants.baseUrl}/tasks/$taskId'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    }
    _handleError(response, 'update task');
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

  /// Upload task check-in attachments (image/video multipart).
  Future<void> uploadTaskAttachments({
    required String taskId,
    required List<File> files,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    if (files.isEmpty) return;

    final multipartFiles = <MultipartFile>[];
    for (final file in files) {
      final filename = file.path.split('/').last;
      multipartFiles.add(
        await MultipartFile.fromFile(file.path, filename: filename),
      );
    }

    try {
      await _dio.post(
        '${ApiConstants.baseUrl}/tasks/$taskId/attachments',
        data: FormData.fromMap({'files': multipartFiles}),
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
        onSendProgress: onSendProgress,
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data['detail'] != null) {
        throw Exception(data['detail'].toString());
      }
      throw Exception('Failed to upload attachments');
    }
  }

  /// Analyze nutrition images and return one concise sentence.
  Future<String> analyzeNutritionImages({required List<File> files}) async {
    if (_token == null) throw Exception('Not authenticated');
    if (files.isEmpty) throw Exception('No files to analyze');

    final multipartFiles = <MultipartFile>[];
    for (final file in files) {
      final filename = file.path.split('/').last;
      multipartFiles.add(
        await MultipartFile.fromFile(file.path, filename: filename),
      );
    }

    debugPrint(
      '[NutritionAnalyze] POST ${ApiConstants.baseUrl}/tasks/nutrition/analyze-images '
      'with ${multipartFiles.length} file(s)',
    );

    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/tasks/nutrition/analyze-images',
        data: FormData.fromMap({'files': multipartFiles}),
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
      );
      debugPrint(
        '[NutritionAnalyze] response status=${response.statusCode} '
        'body_type=${response.data.runtimeType}',
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['summary'] is String) {
        final summary = data['summary'] as String;
        debugPrint(
          '[NutritionAnalyze] OK: summary length=${summary.length}',
        );
        return summary;
      }
      debugPrint(
        '[NutritionAnalyze] FAILED: invalid response shape: '
        '${data.runtimeType} keys='
        '${data is Map ? data.keys.toList() : '(not a map)'}',
      );
      throw Exception('Invalid nutrition analysis response');
    } on DioException catch (e) {
      final data = e.response?.data;
      debugPrint(
        '[NutritionAnalyze] DioException: status=${e.response?.statusCode} '
        'type=${e.type} detail='
        '${data is Map<String, dynamic> ? data['detail'] : '(no detail)'} '
        'url=${e.requestOptions.uri}',
      );
      if (data is Map<String, dynamic> && data['detail'] != null) {
        throw Exception(data['detail'].toString());
      }
      throw Exception('Failed to analyze nutrition images');
    }
  }

  /// Analyze prescription images and return structured medicine entries.
  Future<List<PrescriptionMedicineItem>> analyzeMedicinePrescriptionImages({
    required List<File> files,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    if (files.isEmpty) throw Exception('No files to analyze');
    if (files.length > 12) throw Exception('At most 12 photos are allowed');

    final multipartFiles = <MultipartFile>[];
    for (final file in files) {
      final filename = file.path.split('/').last;
      multipartFiles.add(
        await MultipartFile.fromFile(file.path, filename: filename),
      );
    }

    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/tasks/medicine/analyze-images',
        data: FormData.fromMap({'files': multipartFiles}),
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Invalid prescription analysis response');
      }
      final rows = (data['prescriptions'] as List?) ?? const [];
      final parsed = <PrescriptionMedicineItem>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final name =
            (row['medicine_name'] ?? row['medicine'] ?? row['name'] ?? '')
                .toString()
                .trim();
        final frequency =
            (row['frequency'] ?? row['intake_frequency'] ?? 'Unknown')
                .toString()
                .trim();
        if (name.isEmpty) continue;
        parsed.add(
          PrescriptionMedicineItem(
            medicineName: name,
            frequency: frequency.isEmpty ? 'Unknown' : frequency,
          ),
        );
      }
      return parsed;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data['detail'] != null) {
        throw Exception(data['detail'].toString());
      }
      throw Exception('Failed to analyze prescription images');
    }
  }

  /// Extend a task's close_datetime by 10% of its duration
  Future<Task> extendTask(String taskId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/tasks/$taskId/extend'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    }
    _handleError(response, 'extend task');
  }

  /// Save a note on a task
  Future<Task> updateNote(String taskId, String note) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.patch(
      Uri.parse('${ApiConstants.baseUrl}/tasks/$taskId/note'),
      headers: _headers,
      body: json.encode({'note': note}),
    );

    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    }
    _handleError(response, 'update note');
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

  /// Update an existing template
  Future<RepeatTaskTemplate> updateTemplate({
    required String templateId,
    String? templateName,
    String? templateType,
    String? description,
    int? minInterval,
    List<Map<String, dynamic>>? timeWindowList,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{};
    if (templateName != null) body['template_name'] = templateName;
    if (templateType != null) body['template_type'] = templateType;
    if (description != null) body['description'] = description;
    if (minInterval != null) body['min_interval'] = minInterval;
    if (timeWindowList != null) body['time_window_list'] = timeWindowList;

    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/tasks/templates/$templateId'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return RepeatTaskTemplate.fromJson(json.decode(response.body));
    }
    _handleError(response, 'update template');
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
    String timezone = 'UTC',
    int frequencyMinutes = 1440,
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
        'timezone': timezone,
        'frequency_minutes': frequencyMinutes,
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
    String timezone = 'UTC',
    int frequencyMinutes = 1440,
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
        'timezone': timezone,
        'frequency_minutes': frequencyMinutes,
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

  // ============ Admin Operations ============

  /// Get admin task list (global view across teams)
  Future<AdminTaskListResponse> getAdminTaskList({
    String? email,
    String timeZone = 'UTC',
    String? currentTime,
    int previousOffset = 0,
    int upcomingOffset = 0,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final queryParams = <String, String>{
      'time_zone': timeZone,
      'previous_offset': previousOffset.toString(),
      'upcoming_offset': upcomingOffset.toString(),
    };
    if (email != null && email.isNotEmpty) queryParams['email'] = email;
    if (currentTime != null) queryParams['current_time'] = currentTime;

    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.adminTaskList}',
    ).replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      return AdminTaskListResponse.fromJson(json.decode(response.body));
    }
    _handleError(response, 'get admin tasks');
  }

  /// Fetch full detail for a single task by ID.
  Future<AdminTaskData> getTaskById(String taskId) async {
    if (_token == null) throw Exception('Not authenticated');
    final uri = Uri.parse('${ApiConstants.baseUrl}/admin/tasks/$taskId');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      return AdminTaskData.fromJson(json.decode(response.body));
    }
    _handleError(response, 'get task by id');
  }

  /// Admin complete a task
  ///
  /// Pass [completedAt] to override the server-side timestamp (used for
  /// expired tasks so the done time matches the close time, not now).
  Future<void> adminCompleteTask({
    required String taskId,
    String timeZone = 'UTC',
    DateTime? completedAt,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{'task_id': taskId, 'time_zone': timeZone};
    if (completedAt != null) {
      body['completed_at'] = completedAt.toUtc().toIso8601String();
    }

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.adminTaskComplete}'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) return;
    _handleError(response, 'admin complete task');
  }

  /// Admin delete a task
  Future<void> adminDeleteTask(String taskId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.adminDeleteTask}/$taskId',
      ),
      headers: _headers,
    );

    if (response.statusCode == 200) return;
    _handleError(response, 'admin delete task');
  }

  /// Get tasks for reward calculation
  Future<List<AdminTaskData>> getRewardCalcTasks({
    required String email,
    String timeZone = 'UTC',
    int offset = 0,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final queryParams = <String, String>{
      'email': email,
      'time_zone': timeZone,
      'offset': offset.toString(),
    };

    final uri = Uri.parse(
      '${ApiConstants.baseUrl}${ApiConstants.adminRewardCalc}',
    ).replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;
      return data
          .map((t) => AdminTaskData.fromJson(t as Map<String, dynamic>))
          .toList();
    }
    _handleError(response, 'get reward calc tasks');
  }

  // ============ AI Tips ============

  /// Fetch a personalised AI tip based on task completion history.
  Future<AiTip> getAiTips({int daysBack = 30, String timeZone = 'UTC'}) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/tasks/ai-tips'),
      headers: _headers,
      body: json.encode({'days_back': daysBack, 'time_zone': timeZone}),
    );

    if (response.statusCode == 200) {
      return AiTip.fromJson(json.decode(response.body));
    }
    _handleError(response, 'get AI tips');
  }
}

class PrescriptionMedicineItem {
  final String medicineName;
  final String frequency;

  const PrescriptionMedicineItem({
    required this.medicineName,
    required this.frequency,
  });
}
