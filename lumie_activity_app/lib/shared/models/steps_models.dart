// Step count data models for Lumie App

/// One day's step and active-time data returned by GET /steps/history.
class DailyStepData {
  final String dateStr;       // YYYY-MM-DD
  final int steps;
  final int activeMinutes;    // ring exercise_time_seconds / 60
  final double distanceKm;
  final int goalMinutes;
  final String goalReason;
  final bool goalIsReduced;

  const DailyStepData({
    required this.dateStr,
    required this.steps,
    required this.activeMinutes,
    required this.distanceKm,
    required this.goalMinutes,
    required this.goalReason,
    required this.goalIsReduced,
  });

  DateTime get date {
    final parts = dateStr.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  bool get goalMet => activeMinutes >= goalMinutes;

  double get goalProgress =>
      goalMinutes > 0 ? (activeMinutes / goalMinutes).clamp(0.0, 1.5) : 0.0;

  factory DailyStepData.fromJson(Map<String, dynamic> json) {
    return DailyStepData(
      dateStr: json['date_str'] as String,
      steps: json['steps'] as int,
      activeMinutes: json['active_minutes'] as int,
      distanceKm: (json['distance_km'] as num).toDouble(),
      goalMinutes: json['goal_minutes'] as int,
      goalReason: json['goal_reason'] as String,
      goalIsReduced: json['goal_is_reduced'] as bool,
    );
  }
}

/// Adaptive activity goal for a single day.
class StepGoal {
  final int goalMinutes;
  final String reason;
  final bool isReduced;

  const StepGoal({
    required this.goalMinutes,
    required this.reason,
    required this.isReduced,
  });

  factory StepGoal.fromJson(Map<String, dynamic> json) {
    return StepGoal(
      goalMinutes: json['goal_minutes'] as int,
      reason: json['reason'] as String,
      isReduced: json['is_reduced'] as bool,
    );
  }
}
