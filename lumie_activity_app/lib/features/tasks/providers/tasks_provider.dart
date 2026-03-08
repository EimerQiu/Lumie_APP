/// Tasks Provider - State management for Med-Reminder feature

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/services/task_service.dart';
import '../../../shared/models/task_models.dart';
import '../../../shared/models/user_models.dart';

enum TasksState { initial, loading, loaded, error }

class TasksProvider extends ChangeNotifier {
  final TaskService _taskService = TaskService();

  TasksState _state = TasksState.initial;
  List<Task> _tasks = [];
  List<RepeatTaskTemplate> _templates = [];
  String? _errorMessage;
  SubscriptionTier _userTier = SubscriptionTier.free;
  Timer? _pollTimer;

  // Getters
  TasksState get state => _state;
  List<Task> get tasks => _tasks;
  List<Task> get pendingTasks =>
      _tasks.where((t) => t.status == TaskStatus.pending).toList();
  List<Task> get expiredTasks =>
      _tasks.where((t) => t.status == TaskStatus.expired).toList();
  List<Task> get completedTasks =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();

  /// Display list: backend already filters to within-window + not-done tasks
  List<Task> get activeTasks => _tasks;
  List<RepeatTaskTemplate> get templates => _templates;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == TasksState.loading;
  bool get hasError => _state == TasksState.error;

  /// Set user's subscription tier
  void setUserTier(SubscriptionTier tier) {
    _userTier = tier;
    notifyListeners();
  }

  /// Count of pending tasks for display
  int get activeTaskCount => activeTasks.length;

  /// Free users can only create tasks within 7 days
  int get maxTaskDays => _userTier == SubscriptionTier.free ? 7 : 999999;
  bool get isFreeUser => _userTier == SubscriptionTier.free;

  /// Get device timezone with fallback
  String _getDeviceTimezone() {
    try {
      // Try to get the timezone name from the timezone package
      String tzName = tz.local.name;
      // If it's just 'UTC', try to get a more specific timezone
      if (tzName == 'UTC' || tzName.isEmpty) {
        // Get UTC offset from DateTime
        final now = DateTime.now();
        final offset = now.timeZoneOffset;

        // Map common offsets to IANA timezone names
        final offsetHours = offset.inHours;
        final Map<int, String> offsetMap = {
          -8: 'America/Los_Angeles',
          -7: 'America/Denver',
          -6: 'America/Chicago',
          -5: 'America/New_York',
          0: 'UTC',
          1: 'Europe/London',
          8: 'Asia/Shanghai',
          9: 'Asia/Tokyo',
        };

        return offsetMap[offsetHours] ?? 'UTC';
      }
      return tzName;
    } catch (e) {
      return 'UTC';
    }
  }

  /// Task info text for UI display
  String get taskLimitText {
    return '$activeTaskCount tasks';
  }

  /// Banner message for subscription status
  String? get subscriptionBannerMessage {
    return null;
  }

  /// Load tasks for current user
  Future<void> loadTasks({String? date}) async {
    _state = TasksState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // Get device timezone - use a fallback approach for iOS
      String deviceTimezone = _getDeviceTimezone();
      if (deviceTimezone == 'UTC' || deviceTimezone.isEmpty) {
        // If timezone detection failed, try the timezone package as fallback
        deviceTimezone = tz.local.name;
      }

      final response = await _taskService.getTasks(
        date: date,
        timezone: deviceTimezone,
      );
      _tasks = response.tasks;
      _state = TasksState.loaded;
    } catch (e) {
      _state = TasksState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    }

    notifyListeners();
  }

  /// Load templates for current user
  Future<void> loadTemplates() async {
    try {
      final response = await _taskService.getTemplates();
      _templates = response.templates;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  /// Create a new task
  Future<Task> createTask({
    required String taskName,
    required String taskType,
    required String openDatetime,
    required String closeDatetime,
    String? userId,
    String? teamId,
    String? taskInfo,
  }) async {
    // Get device timezone for time conversion
    String deviceTimezone = _getDeviceTimezone();
    if (deviceTimezone == 'UTC' || deviceTimezone.isEmpty) {
      deviceTimezone = tz.local.name;
    }

    final task = await _taskService.createTask(
      taskName: taskName,
      taskType: taskType,
      openDatetime: openDatetime,
      closeDatetime: closeDatetime,
      timezone: deviceTimezone,
      userId: userId,
      teamId: teamId,
      taskInfo: taskInfo,
    );

    await loadTasks();
    return task;
  }

  /// Complete a task
  Future<void> completeTask(String taskId) async {
    await _taskService.completeTask(taskId);
    // Remove from local list immediately for responsive UI
    _tasks.removeWhere((t) => t.taskId == taskId);
    notifyListeners();
    // Reload to get fresh data
    await loadTasks();
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    await _taskService.deleteTask(taskId);
    _tasks.removeWhere((t) => t.taskId == taskId);
    notifyListeners();
  }

  /// Create a template
  Future<RepeatTaskTemplate> createTemplate({
    required String templateName,
    required String templateType,
    String? description,
    required int minInterval,
    required List<Map<String, dynamic>> timeWindowList,
  }) async {
    final template = await _taskService.createTemplate(
      templateName: templateName,
      templateType: templateType,
      description: description,
      minInterval: minInterval,
      timeWindowList: timeWindowList,
    );

    await loadTemplates();
    return template;
  }

  /// Delete a template
  Future<void> deleteTemplate(String templateId) async {
    await _taskService.deleteTemplate(templateId);
    _templates.removeWhere((t) => t.id == templateId);
    notifyListeners();
  }

  /// Get template by ID
  Future<RepeatTaskTemplate> getTemplate(String templateId) async {
    return await _taskService.getTemplate(templateId);
  }

  /// Update an existing template
  Future<RepeatTaskTemplate> updateTemplate({
    required String templateId,
    required String templateName,
    required String templateType,
    String? description,
    required int minInterval,
    required List<Map<String, dynamic>> timeWindowList,
  }) async {
    final template = await _taskService.updateTemplate(
      templateId: templateId,
      templateName: templateName,
      templateType: templateType,
      description: description,
      minInterval: minInterval,
      timeWindowList: timeWindowList,
    );

    // Replace template in list for immediate UI update
    final idx = _templates.indexWhere((t) => t.id == templateId);
    if (idx != -1) {
      _templates[idx] = template;
    } else {
      await loadTemplates();
    }
    notifyListeners();
    return template;
  }

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
    final deviceTimezone = _getDeviceTimezone();
    return await _taskService.batchPreview(
      templateId: templateId,
      taskName: taskName,
      startDate: startDate,
      endDate: endDate,
      teamId: teamId,
      userId: userId,
      taskInfo: taskInfo,
      timezone: deviceTimezone,
    );
  }

  /// Execute batch generation
  Future<void> batchGenerate({
    required String templateId,
    required String taskName,
    required String startDate,
    required String endDate,
    String? teamId,
    String? userId,
    String? taskInfo,
  }) async {
    final deviceTimezone = _getDeviceTimezone();
    await _taskService.batchGenerate(
      templateId: templateId,
      taskName: taskName,
      startDate: startDate,
      endDate: endDate,
      teamId: teamId,
      userId: userId,
      taskInfo: taskInfo,
      timezone: deviceTimezone,
    );
    await loadTasks();
  }

  /// Start auto-polling (180s interval per PRD)
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 180),
      (_) => loadTasks(),
    );
  }

  /// Stop auto-polling
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset provider state
  void reset() {
    stopPolling();
    _state = TasksState.initial;
    _tasks = [];
    _templates = [];
    _errorMessage = null;
    _userTier = SubscriptionTier.free;
    notifyListeners();
  }
}
