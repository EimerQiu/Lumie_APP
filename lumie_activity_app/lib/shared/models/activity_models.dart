// Activity data models for Lumie App

enum ActivityIntensity {
  low,
  moderate,
  high;

  String get displayName {
    switch (this) {
      case ActivityIntensity.low:
        return 'Low';
      case ActivityIntensity.moderate:
        return 'Moderate';
      case ActivityIntensity.high:
        return 'High';
    }
  }

  String get description {
    switch (this) {
      case ActivityIntensity.low:
        return 'Light effort, easy breathing';
      case ActivityIntensity.moderate:
        return 'Some effort, slightly elevated breathing';
      case ActivityIntensity.high:
        return 'Significant effort, heavy breathing';
    }
  }
}

enum ActivitySource {
  ring,
  manual;

  String get displayName {
    switch (this) {
      case ActivitySource.ring:
        return 'Lumie Ring';
      case ActivitySource.manual:
        return 'Manual Entry';
    }
  }
}

enum RingStatus {
  connected,
  disconnected,
  syncing;

  String get displayName {
    switch (this) {
      case RingStatus.connected:
        return 'Connected';
      case RingStatus.disconnected:
        return 'Disconnected';
      case RingStatus.syncing:
        return 'Syncing...';
    }
  }
}

class ActivityType {
  final String id;
  final String name;
  final String icon;
  final String category;

  const ActivityType({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
  });

  static const List<ActivityType> predefinedTypes = [
    ActivityType(id: 'walking', name: 'Walking', icon: '🚶', category: 'Movement'),
    ActivityType(id: 'running', name: 'Running', icon: '🏃', category: 'Movement'),
    ActivityType(id: 'cycling', name: 'Cycling', icon: '🚴', category: 'Movement'),
    ActivityType(id: 'swimming', name: 'Swimming', icon: '🏊', category: 'Movement'),
    ActivityType(id: 'yoga', name: 'Yoga', icon: '🧘', category: 'Wellness'),
    ActivityType(id: 'stretching', name: 'Stretching', icon: '🤸', category: 'Wellness'),
    ActivityType(id: 'dancing', name: 'Dancing', icon: '💃', category: 'Movement'),
    ActivityType(id: 'basketball', name: 'Basketball', icon: '🏀', category: 'Sports'),
    ActivityType(id: 'soccer', name: 'Soccer', icon: '⚽', category: 'Sports'),
    ActivityType(id: 'tennis', name: 'Tennis', icon: '🎾', category: 'Sports'),
    ActivityType(id: 'hiking', name: 'Hiking', icon: '🥾', category: 'Outdoor'),
    ActivityType(id: 'gym', name: 'Gym Workout', icon: '💪', category: 'Fitness'),
    ActivityType(id: 'other', name: 'Other', icon: '⭐', category: 'Other'),
  ];
}

class ActivityRecord {
  final String id;
  final ActivityType activityType;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final ActivityIntensity? intensity;
  final ActivitySource source;
  final bool isEstimated;
  final int? heartRateAvg;
  final int? heartRateMax;
  final String? notes;

  const ActivityRecord({
    required this.id,
    required this.activityType,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.intensity,
    required this.source,
    required this.isEstimated,
    this.heartRateAvg,
    this.heartRateMax,
    this.notes,
  });

  factory ActivityRecord.fromJson(Map<String, dynamic> json) {
    return ActivityRecord(
      id: json['id'] as String,
      activityType: ActivityType.predefinedTypes.firstWhere(
        (t) => t.id == json['activity_type_id'],
        orElse: () => ActivityType.predefinedTypes.last,
      ),
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      durationMinutes: json['duration_minutes'] as int,
      intensity: json['intensity'] != null
          ? ActivityIntensity.values.byName(json['intensity'] as String)
          : null,
      source: ActivitySource.values.byName(json['source'] as String),
      isEstimated: json['is_estimated'] as bool,
      heartRateAvg: json['heart_rate_avg'] as int?,
      heartRateMax: json['heart_rate_max'] as int?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'activity_type_id': activityType.id,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'duration_minutes': durationMinutes,
      'intensity': intensity?.name,
      'source': source.name,
      'is_estimated': isEstimated,
      'heart_rate_avg': heartRateAvg,
      'heart_rate_max': heartRateMax,
      'notes': notes,
    };
  }
}

class DailyActivitySummary {
  final DateTime date;
  final int totalActiveMinutes;
  final int goalMinutes;
  final ActivityIntensity dominantIntensity;
  final List<ActivityRecord> activities;
  final int ringTrackedMinutes;
  final int manualMinutes;

  const DailyActivitySummary({
    required this.date,
    required this.totalActiveMinutes,
    required this.goalMinutes,
    required this.dominantIntensity,
    required this.activities,
    required this.ringTrackedMinutes,
    required this.manualMinutes,
  });

  double get goalProgress => goalMinutes > 0
      ? (totalActiveMinutes / goalMinutes).clamp(0.0, 1.5)
      : 0.0;

  bool get goalMet => totalActiveMinutes >= goalMinutes;

  factory DailyActivitySummary.fromJson(Map<String, dynamic> json) {
    return DailyActivitySummary(
      date: DateTime.parse(json['date'] as String),
      totalActiveMinutes: json['total_active_minutes'] as int,
      goalMinutes: json['goal_minutes'] as int,
      dominantIntensity: ActivityIntensity.values.byName(
        json['dominant_intensity'] as String,
      ),
      activities: (json['activities'] as List)
          .map((a) => ActivityRecord.fromJson(a as Map<String, dynamic>))
          .toList(),
      ringTrackedMinutes: json['ring_tracked_minutes'] as int,
      manualMinutes: json['manual_minutes'] as int,
    );
  }
}

class AdaptiveGoal {
  final DateTime date;
  final int recommendedMinutes;
  final String reason;
  final List<String> factors;
  final bool isReduced;

  const AdaptiveGoal({
    required this.date,
    required this.recommendedMinutes,
    required this.reason,
    required this.factors,
    required this.isReduced,
  });

  factory AdaptiveGoal.fromJson(Map<String, dynamic> json) {
    return AdaptiveGoal(
      date: DateTime.parse(json['date'] as String),
      recommendedMinutes: json['recommended_minutes'] as int,
      reason: json['reason'] as String,
      factors: List<String>.from(json['factors'] as List),
      isReduced: json['is_reduced'] as bool,
    );
  }
}

class WalkTestResult {
  final String id;
  final DateTime date;
  final double distanceMeters;
  final int durationSeconds;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? recoveryHeartRate;
  final String? notes;

  const WalkTestResult({
    required this.id,
    required this.date,
    required this.distanceMeters,
    required this.durationSeconds,
    this.avgHeartRate,
    this.maxHeartRate,
    this.recoveryHeartRate,
    this.notes,
  });

  factory WalkTestResult.fromJson(Map<String, dynamic> json) {
    return WalkTestResult(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      distanceMeters: (json['distance_meters'] as num).toDouble(),
      durationSeconds: json['duration_seconds'] as int,
      avgHeartRate: json['avg_heart_rate'] as int?,
      maxHeartRate: json['max_heart_rate'] as int?,
      recoveryHeartRate: json['recovery_heart_rate'] as int?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'avg_heart_rate': avgHeartRate,
      'max_heart_rate': maxHeartRate,
      'recovery_heart_rate': recoveryHeartRate,
      'notes': notes,
    };
  }
}

class RingDetectedActivity {
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final String suggestedActivityTypeId;
  final double confidence;
  final int? heartRateAvg;
  final int? heartRateMax;
  final ActivityIntensity? measuredIntensity;

  const RingDetectedActivity({
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.suggestedActivityTypeId,
    required this.confidence,
    this.heartRateAvg,
    this.heartRateMax,
    this.measuredIntensity,
  });

  ActivityType get suggestedActivityType => ActivityType.predefinedTypes.firstWhere(
        (t) => t.id == suggestedActivityTypeId,
        orElse: () => ActivityType.predefinedTypes.last,
      );

  factory RingDetectedActivity.fromJson(Map<String, dynamic> json) {
    return RingDetectedActivity(
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      durationMinutes: json['duration_minutes'] as int,
      suggestedActivityTypeId: json['suggested_activity_type_id'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      heartRateAvg: json['heart_rate_avg'] as int?,
      heartRateMax: json['heart_rate_max'] as int?,
      measuredIntensity: json['measured_intensity'] != null
          ? ActivityIntensity.values.byName(json['measured_intensity'] as String)
          : null,
    );
  }
}
