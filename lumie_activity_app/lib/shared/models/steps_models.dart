// Step count data models for Lumie App

enum ActivityGoalType {
  steps,
  minutes;

  String get displayName => this == steps ? 'Steps' : 'Active Time';
  String get unitLabel => this == steps ? 'steps' : 'min';
}

/// One day's step and active-time data returned by GET /steps/history.
class DailyStepData {
  final String dateStr;       // YYYY-MM-DD
  final int steps;
  final int activeMinutes;    // ring exercise_time_seconds / 60
  final double distanceKm;
  final int goalMinutes;
  final int goalSteps;
  final String goalReason;
  final bool goalIsReduced;
  final ActivityGoalType goalType;

  const DailyStepData({
    required this.dateStr,
    required this.steps,
    required this.activeMinutes,
    required this.distanceKm,
    required this.goalMinutes,
    required this.goalSteps,
    required this.goalReason,
    required this.goalIsReduced,
    this.goalType = ActivityGoalType.minutes,
  });

  DateTime get date {
    final parts = dateStr.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// The primary goal value in the user's chosen unit.
  int get effectiveGoal =>
      goalType == ActivityGoalType.steps ? goalSteps : goalMinutes;

  /// Progress against the user's chosen unit.
  int get effectiveCurrent =>
      goalType == ActivityGoalType.steps ? steps : activeMinutes;

  bool get goalMet => effectiveCurrent >= effectiveGoal;

  double get goalProgress =>
      effectiveGoal > 0 ? (effectiveCurrent / effectiveGoal).clamp(0.0, 1.5) : 0.0;

  factory DailyStepData.fromJson(Map<String, dynamic> json) {
    return DailyStepData(
      dateStr: json['date_str'] as String,
      steps: json['steps'] as int,
      activeMinutes: json['active_minutes'] as int,
      distanceKm: (json['distance_km'] as num).toDouble(),
      goalMinutes: json['goal_minutes'] as int,
      goalSteps: json['goal_steps'] as int? ?? ((json['goal_minutes'] as int) * 8000 ~/ 60),
      goalReason: json['goal_reason'] as String,
      goalIsReduced: json['goal_is_reduced'] as bool,
      goalType: (json['goal_type'] as String?) == 'steps'
          ? ActivityGoalType.steps
          : ActivityGoalType.minutes,
    );
  }
}

/// Adaptive activity goal for a single day.
class StepGoal {
  final int goalMinutes;
  final int goalSteps;
  final String reason;
  final bool isReduced;
  final ActivityGoalType goalType;
  final bool conditionAdjusted;

  const StepGoal({
    required this.goalMinutes,
    required this.goalSteps,
    required this.reason,
    required this.isReduced,
    this.goalType = ActivityGoalType.minutes,
    this.conditionAdjusted = false,
  });

  /// The primary goal value in the user's chosen unit.
  int get effectiveGoal =>
      goalType == ActivityGoalType.steps ? goalSteps : goalMinutes;

  factory StepGoal.fromJson(Map<String, dynamic> json) {
    return StepGoal(
      goalMinutes: json['goal_minutes'] as int,
      goalSteps: json['goal_steps'] as int? ?? ((json['goal_minutes'] as int) * 8000 ~/ 60),
      reason: json['reason'] as String,
      isReduced: json['is_reduced'] as bool,
      goalType: (json['goal_type'] as String?) == 'steps'
          ? ActivityGoalType.steps
          : ActivityGoalType.minutes,
      conditionAdjusted: json['condition_adjusted'] as bool? ?? false,
    );
  }
}

/// User's persisted goal-type preference and optional manual override.
class ActivityGoalSettings {
  final ActivityGoalType goalType;
  final int? customGoal;       // user override in their chosen unit; null = use default
  final int defaultSteps;      // condition-adjusted step default
  final int defaultMinutes;    // condition-adjusted minute default
  final bool conditionAdjusted;

  const ActivityGoalSettings({
    required this.goalType,
    this.customGoal,
    required this.defaultSteps,
    required this.defaultMinutes,
    required this.conditionAdjusted,
  });

  /// The effective goal in the user's chosen unit.
  int get effectiveGoal {
    if (customGoal != null) return customGoal!;
    return goalType == ActivityGoalType.steps ? defaultSteps : defaultMinutes;
  }

  /// The effective goal in minutes (for display / dashboard ring).
  int get effectiveGoalMinutes {
    if (goalType == ActivityGoalType.minutes) return effectiveGoal;
    return (effectiveGoal * 60 / 8000).round();
  }

  /// The effective goal in steps.
  int get effectiveGoalSteps {
    if (goalType == ActivityGoalType.steps) return effectiveGoal;
    return (effectiveGoal * 8000 / 60).round();
  }

  factory ActivityGoalSettings.fromJson(Map<String, dynamic> json) {
    return ActivityGoalSettings(
      goalType: (json['goal_type'] as String?) == 'steps'
          ? ActivityGoalType.steps
          : ActivityGoalType.minutes,
      customGoal: json['custom_goal'] as int?,
      defaultSteps: json['default_steps'] as int,
      defaultMinutes: json['default_minutes'] as int,
      conditionAdjusted: json['condition_adjusted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'goal_type': goalType == ActivityGoalType.steps ? 'steps' : 'minutes',
        'custom_goal': customGoal,
      };

  ActivityGoalSettings copyWith({
    ActivityGoalType? goalType,
    Object? customGoal = _sentinel,
    int? defaultSteps,
    int? defaultMinutes,
    bool? conditionAdjusted,
  }) {
    return ActivityGoalSettings(
      goalType: goalType ?? this.goalType,
      customGoal: customGoal == _sentinel ? this.customGoal : customGoal as int?,
      defaultSteps: defaultSteps ?? this.defaultSteps,
      defaultMinutes: defaultMinutes ?? this.defaultMinutes,
      conditionAdjusted: conditionAdjusted ?? this.conditionAdjusted,
    );
  }
}

const _sentinel = Object();
