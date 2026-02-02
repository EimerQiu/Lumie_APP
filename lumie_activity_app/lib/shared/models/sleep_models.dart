// Sleep data models for Lumie App

/// Sleep stage enum
enum SleepStage {
  awake,
  light,
  deep,
  rem;

  String get displayName {
    switch (this) {
      case SleepStage.awake:
        return 'Awake';
      case SleepStage.light:
        return 'Light';
      case SleepStage.deep:
        return 'Deep';
      case SleepStage.rem:
        return 'REM';
    }
  }
}

/// Sleep stage duration data
class SleepStageData {
  final SleepStage stage;
  final Duration duration;
  final double percentage;

  const SleepStageData({
    required this.stage,
    required this.duration,
    required this.percentage,
  });

  factory SleepStageData.fromJson(Map<String, dynamic> json) {
    return SleepStageData(
      stage: SleepStage.values.firstWhere(
        (s) => s.name == json['stage'],
        orElse: () => SleepStage.light,
      ),
      duration: Duration(minutes: json['duration_minutes'] as int),
      percentage: (json['percentage'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stage': stage.name,
      'duration_minutes': duration.inMinutes,
      'percentage': percentage,
    };
  }
}

/// Sleep session data
class SleepSession {
  final String sessionId;
  final String userId;
  final DateTime bedtime;
  final DateTime wakeTime;
  final Duration totalSleepTime;
  final Duration timeAwake;
  final List<SleepStageData> stages;
  final int restingHeartRate;
  final double sleepQualityScore;
  final DateTime createdAt;

  const SleepSession({
    required this.sessionId,
    required this.userId,
    required this.bedtime,
    required this.wakeTime,
    required this.totalSleepTime,
    required this.timeAwake,
    required this.stages,
    required this.restingHeartRate,
    required this.sleepQualityScore,
    required this.createdAt,
  });

  /// Get total time in bed (from bedtime to wake time)
  Duration get totalTimeInBed => wakeTime.difference(bedtime);

  /// Get sleep efficiency (total sleep / total time in bed)
  double get sleepEfficiency {
    final totalMinutes = totalTimeInBed.inMinutes;
    if (totalMinutes == 0) return 0;
    return (totalSleepTime.inMinutes / totalMinutes) * 100;
  }

  /// Get specific stage duration
  Duration getStageDuration(SleepStage stage) {
    final stageData = stages.firstWhere(
      (s) => s.stage == stage,
      orElse: () => SleepStageData(
        stage: stage,
        duration: Duration.zero,
        percentage: 0,
      ),
    );
    return stageData.duration;
  }

  /// Get specific stage percentage
  double getStagePercentage(SleepStage stage) {
    final stageData = stages.firstWhere(
      (s) => s.stage == stage,
      orElse: () => SleepStageData(
        stage: stage,
        duration: Duration.zero,
        percentage: 0,
      ),
    );
    return stageData.percentage;
  }

  factory SleepSession.fromJson(Map<String, dynamic> json) {
    return SleepSession(
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      bedtime: DateTime.parse(json['bedtime'] as String),
      wakeTime: DateTime.parse(json['wake_time'] as String),
      totalSleepTime: Duration(minutes: json['total_sleep_minutes'] as int),
      timeAwake: Duration(minutes: json['time_awake_minutes'] as int),
      stages: (json['stages'] as List)
          .map((s) => SleepStageData.fromJson(s))
          .toList(),
      restingHeartRate: json['resting_heart_rate'] as int,
      sleepQualityScore: (json['sleep_quality_score'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'user_id': userId,
      'bedtime': bedtime.toIso8601String(),
      'wake_time': wakeTime.toIso8601String(),
      'total_sleep_minutes': totalSleepTime.inMinutes,
      'time_awake_minutes': timeAwake.inMinutes,
      'stages': stages.map((s) => s.toJson()).toList(),
      'resting_heart_rate': restingHeartRate,
      'sleep_quality_score': sleepQualityScore,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Sleep target data (age-aware and adaptive)
class SleepTarget {
  final Duration minDuration;
  final Duration maxDuration;
  final Duration targetDuration;
  final Map<SleepStage, double> targetStagePercentages;

  const SleepTarget({
    required this.minDuration,
    required this.maxDuration,
    required this.targetDuration,
    required this.targetStagePercentages,
  });

  factory SleepTarget.fromJson(Map<String, dynamic> json) {
    final stagePercentages = <SleepStage, double>{};
    final stagesJson = json['target_stage_percentages'] as Map<String, dynamic>;
    stagesJson.forEach((key, value) {
      final stage = SleepStage.values.firstWhere(
        (s) => s.name == key,
        orElse: () => SleepStage.light,
      );
      stagePercentages[stage] = (value as num).toDouble();
    });

    return SleepTarget(
      minDuration: Duration(minutes: json['min_duration_minutes'] as int),
      maxDuration: Duration(minutes: json['max_duration_minutes'] as int),
      targetDuration: Duration(minutes: json['target_duration_minutes'] as int),
      targetStagePercentages: stagePercentages,
    );
  }

  Map<String, dynamic> toJson() {
    final stagesJson = <String, double>{};
    targetStagePercentages.forEach((stage, percentage) {
      stagesJson[stage.name] = percentage;
    });

    return {
      'min_duration_minutes': minDuration.inMinutes,
      'max_duration_minutes': maxDuration.inMinutes,
      'target_duration_minutes': targetDuration.inMinutes,
      'target_stage_percentages': stagesJson,
    };
  }
}

/// Sleep summary for a date range
class SleepSummary {
  final DateTime startDate;
  final DateTime endDate;
  final double averageSleepHours;
  final double averageRestingHR;
  final double averageSleepQuality;
  final double sleepConsistency;
  final Map<SleepStage, double> averageStagePercentages;

  const SleepSummary({
    required this.startDate,
    required this.endDate,
    required this.averageSleepHours,
    required this.averageRestingHR,
    required this.averageSleepQuality,
    required this.sleepConsistency,
    required this.averageStagePercentages,
  });

  factory SleepSummary.fromJson(Map<String, dynamic> json) {
    final stagePercentages = <SleepStage, double>{};
    final stagesJson = json['average_stage_percentages'] as Map<String, dynamic>;
    stagesJson.forEach((key, value) {
      final stage = SleepStage.values.firstWhere(
        (s) => s.name == key,
        orElse: () => SleepStage.light,
      );
      stagePercentages[stage] = (value as num).toDouble();
    });

    return SleepSummary(
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      averageSleepHours: (json['average_sleep_hours'] as num).toDouble(),
      averageRestingHR: (json['average_resting_hr'] as num).toDouble(),
      averageSleepQuality: (json['average_sleep_quality'] as num).toDouble(),
      sleepConsistency: (json['sleep_consistency'] as num).toDouble(),
      averageStagePercentages: stagePercentages,
    );
  }

  Map<String, dynamic> toJson() {
    final stagesJson = <String, double>{};
    averageStagePercentages.forEach((stage, percentage) {
      stagesJson[stage.name] = percentage;
    });

    return {
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'average_sleep_hours': averageSleepHours,
      'average_resting_hr': averageRestingHR,
      'average_sleep_quality': averageSleepQuality,
      'sleep_consistency': sleepConsistency,
      'average_stage_percentages': stagesJson,
    };
  }
}
