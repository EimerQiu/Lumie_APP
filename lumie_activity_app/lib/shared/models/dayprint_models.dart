class DayprintEvent {
  final String type; // "task_completed" | "advisor_chat" | "meal_logged" | …
  final String timestamp;
  final Map<String, dynamic> data;

  const DayprintEvent({
    required this.type,
    required this.timestamp,
    required this.data,
  });

  factory DayprintEvent.fromJson(Map<String, dynamic> json) => DayprintEvent(
    type: json['type'] as String? ?? '',
    timestamp: json['timestamp'] as String? ?? '',
    data: (json['data'] as Map<String, dynamic>?) ?? {},
  );

  /// Canonical identity for dedupe — must match the backend scheme so a
  /// row written by the bridge collapses with any legacy variant for the
  /// same logical event.
  ///
  ///   - Nutrition-task event → `nutrition_task:<user_id>:<source_task_id>`
  ///   - Manual meal_logged   → `meal:<meal_id>`
  ///   - Other task_completed → `task:<user_id>:<source_task_id>`
  ///   - Anything else        → null (no dedupe applies)
  String? canonicalSourceKey(String userId) {
    final sourceTaskId = data['source_task_id'] as String?;
    final taskType = data['task_type'] as String?;
    final sourceType = data['source_type'] as String? ?? '';
    final mealId = data['meal_id'] as String?;

    final isNutrition = sourceType.startsWith('nutrition_task') ||
        taskType == 'Nutrition' ||
        taskType == 'nutrition';

    if (sourceTaskId != null &&
        sourceTaskId.isNotEmpty &&
        (isNutrition || type == 'meal_logged')) {
      return 'nutrition_task:$userId:$sourceTaskId';
    }
    if (type == 'meal_logged' && mealId != null && mealId.isNotEmpty) {
      return 'meal:$mealId';
    }
    if (type == 'task_completed' &&
        sourceTaskId != null &&
        sourceTaskId.isNotEmpty) {
      return 'task:$userId:$sourceTaskId';
    }
    return null;
  }
}

class Dayprint {
  final String userId;
  final String date;
  final List<DayprintEvent> events;

  const Dayprint({
    required this.userId,
    required this.date,
    required this.events,
  });

  factory Dayprint.fromJson(Map<String, dynamic> json) => Dayprint(
    userId: json['user_id'] as String? ?? '',
    date: json['date'] as String? ?? '',
    events: (json['events'] as List<dynamic>? ?? [])
        .map((e) => DayprintEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class DayprintHistoryPage {
  final List<Dayprint> dayprints;
  final bool hasMore;
  final String? nextBeforeDate;

  const DayprintHistoryPage({
    required this.dayprints,
    required this.hasMore,
    required this.nextBeforeDate,
  });

  factory DayprintHistoryPage.fromJson(Map<String, dynamic> json) =>
      DayprintHistoryPage(
        dayprints: (json['dayprints'] as List<dynamic>? ?? [])
            .map((e) => Dayprint.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: json['has_more'] as bool? ?? false,
        nextBeforeDate: json['next_before_date'] as String?,
      );
}
