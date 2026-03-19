/// Task and Template models for Med-Reminder feature

enum TaskType {
  medicine,
  life,
  study,
  exercise,
  work,
  meditation,
  love;

  String get displayName {
    switch (this) {
      case TaskType.medicine:
        return 'Medicine';
      case TaskType.life:
        return 'Life';
      case TaskType.study:
        return 'Study';
      case TaskType.exercise:
        return 'Exercise';
      case TaskType.work:
        return 'Work';
      case TaskType.meditation:
        return 'Meditation';
      case TaskType.love:
        return 'Love';
    }
  }

  String get apiValue => displayName;

  static TaskType fromString(String value) {
    return TaskType.values.firstWhere(
      (e) => e.displayName == value,
      orElse: () => TaskType.life,
    );
  }
}

enum TaskStatus {
  pending,
  completed,
  overdue, // Legacy, maps to expired
  expired;

  String get displayName {
    switch (this) {
      case TaskStatus.pending:
        return 'Pending';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.overdue:
      case TaskStatus.expired:
        return 'Expired';
    }
  }

  static TaskStatus fromString(String value) {
    // Normalize "overdue" to "expired"
    if (value == 'overdue') return TaskStatus.expired;
    return TaskStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TaskStatus.pending,
    );
  }
}

/// Helper to safely parse timestamps from backend
/// Backend uses datetime.utcnow() which does NOT append 'Z'
String _ensureUtcSuffix(String dateStr) {
  if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
    return '${dateStr}Z';
  }
  return dateStr;
}

class Task {
  final String taskId;
  final String taskName;
  final TaskType taskType;
  final String openDatetime;
  final String closeDatetime;
  final String userId;
  final String? teamId;
  final String createdBy;
  final String? rpttaskId;
  final TaskStatus status;
  final String? taskInfo;
  final DateTime? completedAt;
  final int extensionCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Task({
    required this.taskId,
    required this.taskName,
    required this.taskType,
    required this.openDatetime,
    required this.closeDatetime,
    required this.userId,
    this.teamId,
    required this.createdBy,
    this.rpttaskId,
    required this.status,
    this.taskInfo,
    this.completedAt,
    this.extensionCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      taskId: json['task_id'] as String,
      taskName: json['task_name'] as String,
      taskType: TaskType.fromString(json['task_type'] as String),
      openDatetime: json['open_datetime'] as String,
      closeDatetime: json['close_datetime'] as String,
      userId: json['user_id'] as String,
      teamId: json['team_id'] as String?,
      createdBy: json['created_by'] as String,
      rpttaskId: json['rpttask_id'] as String?,
      status: TaskStatus.fromString(json['status'] as String),
      taskInfo: json['task_info'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(_ensureUtcSuffix(json['completed_at'] as String))
          : null,
      extensionCount: json['extension_count'] as int? ?? 0,
      createdAt:
          DateTime.parse(_ensureUtcSuffix(json['created_at'] as String)),
      updatedAt:
          DateTime.parse(_ensureUtcSuffix(json['updated_at'] as String)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'task_id': taskId,
      'task_name': taskName,
      'task_type': taskType.apiValue,
      'open_datetime': openDatetime,
      'close_datetime': closeDatetime,
      'user_id': userId,
      'team_id': teamId,
      'created_by': createdBy,
      'rpttask_id': rpttaskId,
      'status': status.name,
      'task_info': taskInfo,
      'completed_at': completedAt?.toIso8601String(),
      'extension_count': extensionCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Calculate progress (0.0 to 1.0) based on current time within window
  /// Times are stored in UTC and need to be compared against local time
  double get progress {
    try {
      final now = DateTime.now();
      // Parse UTC times and convert to local
      final open = DateTime.parse(openDatetime.replaceAll(' ', 'T') + 'Z').toLocal();
      final close = DateTime.parse(closeDatetime.replaceAll(' ', 'T') + 'Z').toLocal();

      if (now.isBefore(open)) return 0.0;
      if (now.isAfter(close)) return 1.0;

      final total = close.difference(open).inSeconds;
      if (total <= 0) return 1.0;
      final elapsed = now.difference(open).inSeconds;
      return (elapsed / total).clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  /// Progress as percentage string
  String get progressText => '${(progress * 100).round()}%';

  /// Gradient color index based on task_id hash mod 6
  int get colorIndex => taskId.hashCode.abs() % 6;

  /// Check if task is actually overdue (current time > close time)
  /// Times are stored in UTC and need to be compared against local time
  bool get isActuallyOverdue {
    try {
      final now = DateTime.now();
      final close = DateTime.parse(closeDatetime.replaceAll(' ', 'T') + 'Z').toLocal();
      return now.isAfter(close);
    } catch (_) {
      return false;
    }
  }

  /// Formatted time window display (UTC→local conversion)
  String get timeWindowText {
    try {
      final open = DateTime.parse('${openDatetime.replaceAll(' ', 'T')}Z').toLocal();
      final close = DateTime.parse('${closeDatetime.replaceAll(' ', 'T')}Z').toLocal();
      final openStr = '${open.hour.toString().padLeft(2, '0')}:${open.minute.toString().padLeft(2, '0')}';
      final closeStr = '${close.hour.toString().padLeft(2, '0')}:${close.minute.toString().padLeft(2, '0')}';
      return '$openStr - $closeStr';
    } catch (_) {}
    return '$openDatetime - $closeDatetime';
  }

  /// Whether this is a team task
  bool get isTeamTask => teamId != null;
}

class TaskListResponse {
  final List<Task> tasks;
  final int total;

  const TaskListResponse({
    required this.tasks,
    required this.total,
  });

  factory TaskListResponse.fromJson(Map<String, dynamic> json) {
    return TaskListResponse(
      tasks: (json['tasks'] as List)
          .map((t) => Task.fromJson(t as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}

class TimeWindow {
  final int id;
  final String name;
  final String openTime;
  final String closeTime;
  final bool isNextDay;

  const TimeWindow({
    required this.id,
    required this.name,
    required this.openTime,
    required this.closeTime,
    this.isNextDay = false,
  });

  factory TimeWindow.fromJson(Map<String, dynamic> json) {
    return TimeWindow(
      id: json['id'] as int,
      name: json['name'] as String,
      openTime: json['open_time'] as String,
      closeTime: json['close_time'] as String,
      isNextDay: json['is_next_day'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'open_time': openTime,
      'close_time': closeTime,
      'is_next_day': isNextDay,
    };
  }
}

class RepeatTaskTemplate {
  final String id;
  final String templateName;
  final TaskType templateType;
  final String? description;
  final int timeWindows;
  final int minInterval;
  final List<TimeWindow> timeWindowList;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RepeatTaskTemplate({
    required this.id,
    required this.templateName,
    required this.templateType,
    this.description,
    required this.timeWindows,
    required this.minInterval,
    required this.timeWindowList,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RepeatTaskTemplate.fromJson(Map<String, dynamic> json) {
    return RepeatTaskTemplate(
      id: json['id'] as String,
      templateName: json['template_name'] as String,
      templateType: TaskType.fromString(json['template_type'] as String),
      description: json['description'] as String?,
      timeWindows: json['time_windows'] as int,
      minInterval: json['min_interval'] as int,
      timeWindowList: (json['time_window_list'] as List)
          .map((tw) => TimeWindow.fromJson(tw as Map<String, dynamic>))
          .toList(),
      createdBy: json['created_by'] as String,
      createdAt:
          DateTime.parse(_ensureUtcSuffix(json['created_at'] as String)),
      updatedAt:
          DateTime.parse(_ensureUtcSuffix(json['updated_at'] as String)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'template_name': templateName,
      'template_type': templateType.apiValue,
      'description': description,
      'time_windows': timeWindows,
      'min_interval': minInterval,
      'time_window_list': timeWindowList.map((tw) => tw.toJson()).toList(),
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class TemplateListResponse {
  final List<RepeatTaskTemplate> templates;
  final int total;

  const TemplateListResponse({
    required this.templates,
    required this.total,
  });

  factory TemplateListResponse.fromJson(Map<String, dynamic> json) {
    return TemplateListResponse(
      templates: (json['templates'] as List)
          .map((t) =>
              RepeatTaskTemplate.fromJson(t as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}

// ============ Admin Models ============

class RptTaskItem {
  final int id;
  final String name;
  final int openTime;
  final int closeTime;

  const RptTaskItem({
    required this.id,
    required this.name,
    required this.openTime,
    required this.closeTime,
  });

  factory RptTaskItem.fromJson(Map<String, dynamic> json) {
    return RptTaskItem(
      id: json['id'] as int,
      name: json['name'] as String,
      openTime: json['open_time'] as int,
      closeTime: json['close_time'] as int,
    );
  }
}

class AdminTaskData {
  final String taskId;
  final String userId;
  final String username;
  final String taskType;
  final String openDatetime;
  final String closeDatetime;
  final String status;
  final String? rpttaskId;
  final String rpttaskName;
  final String? rpttaskInfo;
  final String rpttaskType;
  final List<RptTaskItem> rpttaskList;
  final String? smallTaskId;
  final int minInterval;
  final String? familyId;
  final String? familyName;

  const AdminTaskData({
    required this.taskId,
    required this.userId,
    required this.username,
    required this.taskType,
    required this.openDatetime,
    required this.closeDatetime,
    required this.status,
    this.rpttaskId,
    required this.rpttaskName,
    this.rpttaskInfo,
    required this.rpttaskType,
    this.rpttaskList = const [],
    this.smallTaskId,
    this.minInterval = 0,
    this.familyId,
    this.familyName,
  });

  factory AdminTaskData.fromJson(Map<String, dynamic> json) {
    return AdminTaskData(
      taskId: json['task_id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String,
      taskType: json['task_type'] as String,
      openDatetime: json['open_datetime'] as String,
      closeDatetime: json['close_datetime'] as String,
      status: json['status'] as String,
      rpttaskId: json['rpttask_id'] as String?,
      rpttaskName: json['rpttask_name'] as String,
      rpttaskInfo: json['rpttask_info'] as String?,
      rpttaskType: json['rpttask_type'] as String,
      rpttaskList: (json['rpttask_list'] as List?)
              ?.map((e) => RptTaskItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      smallTaskId: json['small_task_id'] as String?,
      minInterval: json['min_interval'] as int? ?? 0,
      familyId: json['family_id'] as String?,
      familyName: json['family_name'] as String?,
    );
  }

  /// Status badge color
  bool get isCompleted => status == 'completed';
  bool get isPending => status == 'pending';
  bool get isExpired => status == 'expired';

  /// Formatted time window for display (UTC→local conversion)
  String get timeWindowText {
    try {
      final open = DateTime.parse('${openDatetime.replaceAll(' ', 'T')}Z').toLocal();
      final close = DateTime.parse('${closeDatetime.replaceAll(' ', 'T')}Z').toLocal();
      String fmt(DateTime dt) {
        final date = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        return '$date $time';
      }
      return '${fmt(open)} - ${fmt(close)}';
    } catch (_) {}
    return '$openDatetime - $closeDatetime';
  }
}

class AdminTaskListResponse {
  final List<AdminTaskData> previousTasks;
  final List<AdminTaskData> upcomingTasks;

  const AdminTaskListResponse({
    required this.previousTasks,
    required this.upcomingTasks,
  });

  factory AdminTaskListResponse.fromJson(Map<String, dynamic> json) {
    return AdminTaskListResponse(
      previousTasks: (json['previous_tasks'] as List)
          .map((t) => AdminTaskData.fromJson(t as Map<String, dynamic>))
          .toList(),
      upcomingTasks: (json['upcoming_tasks'] as List)
          .map((t) => AdminTaskData.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ============ AI Tips Models ============

class AiTaskStats {
  final int totalTasks;
  final int completedTasks;
  final int expiredTasks;
  final int pendingTasks;
  final double completionRate;

  const AiTaskStats({
    required this.totalTasks,
    required this.completedTasks,
    required this.expiredTasks,
    required this.pendingTasks,
    required this.completionRate,
  });

  factory AiTaskStats.fromJson(Map<String, dynamic> json) {
    return AiTaskStats(
      totalTasks: json['total_tasks'] as int,
      completedTasks: json['completed_tasks'] as int,
      expiredTasks: json['expired_tasks'] as int,
      pendingTasks: json['pending_tasks'] as int,
      completionRate: (json['completion_rate'] as num).toDouble(),
    );
  }
}

class AiTip {
  final String tip;
  final AiTaskStats taskStats;

  const AiTip({required this.tip, required this.taskStats});

  factory AiTip.fromJson(Map<String, dynamic> json) {
    return AiTip(
      tip: json['tip'] as String,
      taskStats: AiTaskStats.fromJson(json['task_stats'] as Map<String, dynamic>),
    );
  }
}
