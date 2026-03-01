/// Tasks Provider - State management for Med-Reminder feature

import 'dart:async';
import 'package:flutter/foundation.dart';
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
  List<Task> get overdueTasks =>
      _tasks.where((t) => t.status == TaskStatus.overdue).toList();
  List<Task> get completedTasks =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();
  List<Task> get activeTasks =>
      _tasks.where((t) => t.status != TaskStatus.completed).toList();
  List<RepeatTaskTemplate> get templates => _templates;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == TasksState.loading;
  bool get hasError => _state == TasksState.error;

  /// Set user's subscription tier
  void setUserTier(SubscriptionTier tier) {
    _userTier = tier;
    notifyListeners();
  }

  /// Count of active (non-completed) tasks
  int get activeTaskCount => activeTasks.length;

  /// Check if user has reached task limit
  bool get hasReachedTaskLimit {
    if (_userTier == SubscriptionTier.free) {
      return activeTaskCount >= 6;
    }
    return false; // Pro = unlimited
  }

  /// Check if user can create more tasks
  bool get canCreateTask => !hasReachedTaskLimit;

  /// Task limit text for UI display
  String get taskLimitText {
    if (_userTier == SubscriptionTier.free) {
      return '$activeTaskCount/6 tasks';
    }
    return '$activeTaskCount tasks';
  }

  /// Banner message for subscription status
  String? get subscriptionBannerMessage {
    if (_userTier == SubscriptionTier.free && hasReachedTaskLimit) {
      return 'Task limit reached ($activeTaskCount/6). Upgrade to Pro for unlimited tasks.';
    }
    return null;
  }

  /// Load tasks for current user
  Future<void> loadTasks({String? status, String? date}) async {
    _state = TasksState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _taskService.getTasks(
        status: status,
        date: date,
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
    final task = await _taskService.createTask(
      taskName: taskName,
      taskType: taskType,
      openDatetime: openDatetime,
      closeDatetime: closeDatetime,
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
    return await _taskService.batchPreview(
      templateId: templateId,
      taskName: taskName,
      startDate: startDate,
      endDate: endDate,
      teamId: teamId,
      userId: userId,
      taskInfo: taskInfo,
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
    await _taskService.batchGenerate(
      templateId: templateId,
      taskName: taskName,
      startDate: startDate,
      endDate: endDate,
      teamId: teamId,
      userId: userId,
      taskInfo: taskInfo,
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
