class DayprintEvent {
  final String type; // "task_completed" | "advisor_chat"
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
