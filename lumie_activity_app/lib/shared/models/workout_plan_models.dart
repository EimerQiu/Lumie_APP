/// Models for the workout plan builder, exercise library, session logging,
/// and personal records.
library;

// ── Enums ──────────────────────────────────────────────────────────────────────

enum PoseType {
  squat,
  curl,
  pushup,
  lunge,
  shoulderPress,
  generic,
  // Free weight additions
  lateralRaise,
  rdl,
  backSquat,
  benchPress,
  deadlift,
  barbellRow,
  // Machine / manual — no camera
  machine,
}

PoseType? poseTypeFromString(String? value) {
  if (value == null) return null;
  const map = {
    'squat': PoseType.squat,
    'curl': PoseType.curl,
    'pushup': PoseType.pushup,
    'lunge': PoseType.lunge,
    'shoulderPress': PoseType.shoulderPress,
    'generic': PoseType.generic,
    'lateralRaise': PoseType.lateralRaise,
    'rdl': PoseType.rdl,
    'backSquat': PoseType.backSquat,
    'benchPress': PoseType.benchPress,
    'deadlift': PoseType.deadlift,
    'barbellRow': PoseType.barbellRow,
    'machine': PoseType.machine,
  };
  return map[value];
}

String? poseTypeToString(PoseType? pt) {
  if (pt == null) return null;
  return pt.name;
}

enum EquipmentType {
  bodyweight,
  dumbbell,
  barbell,
  machine,
  cable,
  band,
}

EquipmentType equipmentTypeFromString(String value) {
  return EquipmentType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => EquipmentType.bodyweight,
  );
}

enum MovementType { push, pull, hinge, squat, carry, isolation, compound }

enum SetType { straight, superset, circuit, dropSet, failure }

SetType setTypeFromString(String value) {
  const map = {
    'straight': SetType.straight,
    'superset': SetType.superset,
    'circuit': SetType.circuit,
    'drop_set': SetType.dropSet,
    'failure': SetType.failure,
  };
  return map[value] ?? SetType.straight;
}

String setTypeToString(SetType st) {
  const map = {
    SetType.straight: 'straight',
    SetType.superset: 'superset',
    SetType.circuit: 'circuit',
    SetType.dropSet: 'drop_set',
    SetType.failure: 'failure',
  };
  return map[st]!;
}

enum SplitType {
  fullBody,
  upperLower,
  pushPullLegs,
  bodyPart,
  abBlock,
  custom,
}

SplitType splitTypeFromString(String value) {
  const map = {
    'full_body': SplitType.fullBody,
    'upper_lower': SplitType.upperLower,
    'push_pull_legs': SplitType.pushPullLegs,
    'body_part': SplitType.bodyPart,
    'ab_block': SplitType.abBlock,
    'custom': SplitType.custom,
  };
  return map[value] ?? SplitType.fullBody;
}

String splitTypeToString(SplitType st) {
  const map = {
    SplitType.fullBody: 'full_body',
    SplitType.upperLower: 'upper_lower',
    SplitType.pushPullLegs: 'push_pull_legs',
    SplitType.bodyPart: 'body_part',
    SplitType.abBlock: 'ab_block',
    SplitType.custom: 'custom',
  };
  return map[st]!;
}

enum SetCompletionStatus { completed, failed, pr, skipped }

// ── Exercise Library ───────────────────────────────────────────────────────────

class ExerciseDefinition {
  final String exerciseId;
  final String name;
  final String description;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final EquipmentType equipmentType;
  final String movementType;
  final PoseType? poseType;
  final String? recommendedOrientation;
  final String formDescription;
  final bool isSystem;
  final String? createdBy;
  final bool icd10Caution;
  final bool isActive;

  const ExerciseDefinition({
    required this.exerciseId,
    required this.name,
    this.description = '',
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    required this.equipmentType,
    this.movementType = 'isolation',
    this.poseType,
    this.recommendedOrientation,
    this.formDescription = '',
    this.isSystem = true,
    this.createdBy,
    this.icd10Caution = false,
    this.isActive = true,
  });

  factory ExerciseDefinition.fromJson(Map<String, dynamic> json) {
    return ExerciseDefinition(
      exerciseId: json['exercise_id'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      primaryMuscles: List<String>.from(json['primary_muscles'] ?? []),
      secondaryMuscles: List<String>.from(json['secondary_muscles'] ?? []),
      equipmentType: equipmentTypeFromString(json['equipment_type'] as String),
      movementType: (json['movement_type'] as String?) ?? 'isolation',
      poseType: poseTypeFromString(json['pose_type'] as String?),
      recommendedOrientation: json['recommended_orientation'] as String?,
      formDescription: (json['form_description'] as String?) ?? '',
      isSystem: (json['is_system'] as bool?) ?? true,
      createdBy: json['created_by'] as String?,
      icd10Caution: (json['icd10_caution'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'name': name,
        'description': description,
        'primary_muscles': primaryMuscles,
        'secondary_muscles': secondaryMuscles,
        'equipment_type': equipmentType.name,
        'movement_type': movementType,
        'pose_type': poseTypeToString(poseType),
        'recommended_orientation': recommendedOrientation,
        'form_description': formDescription,
        'is_system': isSystem,
        'created_by': createdBy,
      };

  /// Whether this exercise uses camera-based pose detection.
  bool get usesCameraDetection =>
      poseType != null &&
      poseType != PoseType.machine &&
      equipmentType != EquipmentType.machine;
}

// ── Template Structures ────────────────────────────────────────────────────────

class TemplateExercise {
  String exerciseId;
  String exerciseName;
  String equipmentType;
  PoseType? poseType;
  int order;
  int defaultSets;
  int defaultReps;
  double? defaultWeight;
  int defaultRestSeconds;
  SetType setType;
  String? groupId;
  String? notes;

  TemplateExercise({
    required this.exerciseId,
    this.exerciseName = '',
    this.equipmentType = 'bodyweight',
    this.poseType,
    this.order = 0,
    this.defaultSets = 3,
    this.defaultReps = 10,
    this.defaultWeight,
    this.defaultRestSeconds = 60,
    this.setType = SetType.straight,
    this.groupId,
    this.notes,
  });

  factory TemplateExercise.fromJson(Map<String, dynamic> json) {
    return TemplateExercise(
      exerciseId: json['exercise_id'] as String,
      exerciseName: (json['exercise_name'] as String?) ?? '',
      equipmentType: (json['equipment_type'] as String?) ?? 'bodyweight',
      poseType: poseTypeFromString(json['pose_type'] as String?),
      order: (json['order'] as int?) ?? 0,
      defaultSets: (json['default_sets'] as int?) ?? 3,
      defaultReps: (json['default_reps'] as int?) ?? 10,
      defaultWeight: (json['default_weight'] as num?)?.toDouble(),
      defaultRestSeconds: (json['default_rest_seconds'] as int?) ?? 60,
      setType: setTypeFromString((json['set_type'] as String?) ?? 'straight'),
      groupId: json['group_id'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'equipment_type': equipmentType,
        'pose_type': poseTypeToString(poseType),
        'order': order,
        'default_sets': defaultSets,
        'default_reps': defaultReps,
        'default_weight': defaultWeight,
        'default_rest_seconds': defaultRestSeconds,
        'set_type': setTypeToString(setType),
        'group_id': groupId,
        'notes': notes,
      };

  TemplateExercise copyWith({
    String? exerciseId,
    String? exerciseName,
    String? equipmentType,
    PoseType? poseType,
    int? order,
    int? defaultSets,
    int? defaultReps,
    double? defaultWeight,
    int? defaultRestSeconds,
    SetType? setType,
    String? groupId,
    String? notes,
  }) {
    return TemplateExercise(
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      equipmentType: equipmentType ?? this.equipmentType,
      poseType: poseType ?? this.poseType,
      order: order ?? this.order,
      defaultSets: defaultSets ?? this.defaultSets,
      defaultReps: defaultReps ?? this.defaultReps,
      defaultWeight: defaultWeight ?? this.defaultWeight,
      defaultRestSeconds: defaultRestSeconds ?? this.defaultRestSeconds,
      setType: setType ?? this.setType,
      groupId: groupId ?? this.groupId,
      notes: notes ?? this.notes,
    );
  }
}

class WorkoutBlock {
  String blockId;
  String name;
  int order;
  List<TemplateExercise> exercises;

  /// Rest between individual exercise transitions within this block (seconds).
  /// Only relevant for blocks with 2+ exercises (supersets / circuits).
  /// null = no countdown timer, just show the "Ready?" confirm button.
  int? restBetweenExercises;

  /// Rest between full rounds for circuits (3+ exercises), in seconds.
  /// null = use the smart default rest duration.
  int? restBetweenRounds;

  WorkoutBlock({
    required this.blockId,
    required this.name,
    this.order = 0,
    List<TemplateExercise>? exercises,
    this.restBetweenExercises,
    this.restBetweenRounds,
  }) : exercises = exercises ?? [];

  /// Auto-detected set type based on exercise count.
  SetType get autoSetType {
    if (exercises.length >= 3) return SetType.circuit;
    if (exercises.length == 2) return SetType.superset;
    return SetType.straight;
  }

  /// Human-readable label for the auto-detected set type.
  String? get setTypeLabel {
    if (exercises.length >= 3) return 'Circuit';
    if (exercises.length == 2) return 'Superset';
    return null; // straight — no special label
  }

  factory WorkoutBlock.fromJson(Map<String, dynamic> json) {
    return WorkoutBlock(
      blockId: json['block_id'] as String,
      name: json['name'] as String,
      order: (json['order'] as int?) ?? 0,
      exercises: (json['exercises'] as List<dynamic>?)
              ?.map((e) => TemplateExercise.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      restBetweenExercises: json['rest_between_exercises'] as int?,
      restBetweenRounds: json['rest_between_rounds'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'block_id': blockId,
        'name': name,
        'order': order,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        if (restBetweenExercises != null)
          'rest_between_exercises': restBetweenExercises,
        if (restBetweenRounds != null)
          'rest_between_rounds': restBetweenRounds,
      };
}

class WorkoutTemplate {
  final String templateId;
  final String userId;
  String name;
  String emoji;
  SplitType splitType;
  String? splitDayLabel;
  String? splitGroupId;
  List<WorkoutBlock> blocks;
  int restDurationSeconds;
  final bool isSystemDefault;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  WorkoutTemplate({
    required this.templateId,
    this.userId = '',
    required this.name,
    this.emoji = '💪',
    this.splitType = SplitType.fullBody,
    this.splitDayLabel,
    this.splitGroupId,
    List<WorkoutBlock>? blocks,
    this.restDurationSeconds = 60,
    this.isSystemDefault = false,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  }) : blocks = blocks ?? [];

  factory WorkoutTemplate.fromJson(Map<String, dynamic> json) {
    return WorkoutTemplate(
      templateId: json['template_id'] as String,
      userId: (json['user_id'] as String?) ?? '',
      name: json['name'] as String,
      emoji: (json['emoji'] as String?) ?? '💪',
      splitType:
          splitTypeFromString((json['split_type'] as String?) ?? 'full_body'),
      splitDayLabel: json['split_day_label'] as String?,
      splitGroupId: json['split_group_id'] as String?,
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((b) => WorkoutBlock.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      restDurationSeconds: (json['rest_duration_seconds'] as int?) ?? 60,
      isSystemDefault: (json['is_system_default'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? true,
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'template_id': templateId,
        'user_id': userId,
        'name': name,
        'emoji': emoji,
        'split_type': splitTypeToString(splitType),
        'split_day_label': splitDayLabel,
        'split_group_id': splitGroupId,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'rest_duration_seconds': restDurationSeconds,
        'is_system_default': isSystemDefault,
      };

  /// Flat list of all exercises across all blocks.
  List<TemplateExercise> get allExercises =>
      blocks.expand((b) => b.exercises).toList();

  /// Total exercise count.
  int get exerciseCount => allExercises.length;
}

// ── Session Logging ────────────────────────────────────────────────────────────

class CompletedSet {
  int setIndex;
  int targetReps;
  double? targetWeight;
  int actualReps;
  double? actualWeight;
  SetCompletionStatus status;
  bool isPr;
  int? rpe;
  String? notes;
  bool wasCameraTracked;

  CompletedSet({
    required this.setIndex,
    this.targetReps = 0,
    this.targetWeight,
    this.actualReps = 0,
    this.actualWeight,
    this.status = SetCompletionStatus.completed,
    this.isPr = false,
    this.rpe,
    this.notes,
    this.wasCameraTracked = false,
  });

  factory CompletedSet.fromJson(Map<String, dynamic> json) {
    return CompletedSet(
      setIndex: (json['set_index'] as int?) ?? 0,
      targetReps: (json['target_reps'] as int?) ?? 0,
      targetWeight: (json['target_weight'] as num?)?.toDouble(),
      actualReps: (json['actual_reps'] as int?) ?? 0,
      actualWeight: (json['actual_weight'] as num?)?.toDouble(),
      status: _statusFromString((json['status'] as String?) ?? 'completed'),
      isPr: (json['is_pr'] as bool?) ?? false,
      rpe: json['rpe'] as int?,
      notes: json['notes'] as String?,
      wasCameraTracked: (json['was_camera_tracked'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'set_index': setIndex,
        'target_reps': targetReps,
        'target_weight': targetWeight,
        'actual_reps': actualReps,
        'actual_weight': actualWeight,
        'status': status.name,
        'is_pr': isPr,
        'rpe': rpe,
        'notes': notes,
        'was_camera_tracked': wasCameraTracked,
      };

  double get volume => (actualWeight ?? 0) * actualReps;
}

SetCompletionStatus _statusFromString(String s) {
  return SetCompletionStatus.values.firstWhere(
    (e) => e.name == s,
    orElse: () => SetCompletionStatus.completed,
  );
}

class CompletedExercise {
  final String exerciseId;
  final String exerciseName;
  final String equipmentType;
  final PoseType? poseType;
  final SetType setType;
  final String? groupId;
  final String? blockName;
  List<CompletedSet> sets;

  CompletedExercise({
    required this.exerciseId,
    required this.exerciseName,
    this.equipmentType = '',
    this.poseType,
    this.setType = SetType.straight,
    this.groupId,
    this.blockName,
    List<CompletedSet>? sets,
  }) : sets = sets ?? [];

  factory CompletedExercise.fromJson(Map<String, dynamic> json) {
    return CompletedExercise(
      exerciseId: json['exercise_id'] as String,
      exerciseName: (json['exercise_name'] as String?) ?? '',
      equipmentType: (json['equipment_type'] as String?) ?? '',
      poseType: poseTypeFromString(json['pose_type'] as String?),
      setType: setTypeFromString((json['set_type'] as String?) ?? 'straight'),
      groupId: json['group_id'] as String?,
      blockName: json['block_name'] as String?,
      sets: (json['sets'] as List<dynamic>?)
              ?.map((s) => CompletedSet.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'equipment_type': equipmentType,
        'pose_type': poseTypeToString(poseType),
        'set_type': setTypeToString(setType),
        'group_id': groupId,
        'block_name': blockName,
        'sets': sets.map((s) => s.toJson()).toList(),
      };

  double get totalVolume =>
      sets.fold(0.0, (sum, s) => sum + s.volume);

  int get totalReps => sets.fold(0, (sum, s) => sum + s.actualReps);
}

class WorkoutSession {
  final String sessionId;
  final String userId;
  final String? templateId;
  final String templateName;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  List<CompletedExercise> exercises;
  final int totalSets;
  final int totalReps;
  final double totalVolume;
  final List<Map<String, dynamic>> prs;
  final int? heartRateAvg;
  final int? heartRateMax;
  String? notes;

  WorkoutSession({
    required this.sessionId,
    this.userId = '',
    this.templateId,
    this.templateName = '',
    required this.startedAt,
    required this.endedAt,
    this.durationSeconds = 0,
    List<CompletedExercise>? exercises,
    this.totalSets = 0,
    this.totalReps = 0,
    this.totalVolume = 0.0,
    this.prs = const [],
    this.heartRateAvg,
    this.heartRateMax,
    this.notes,
  }) : exercises = exercises ?? [];

  factory WorkoutSession.fromJson(Map<String, dynamic> json) {
    return WorkoutSession(
      sessionId: json['session_id'] as String,
      userId: (json['user_id'] as String?) ?? '',
      templateId: json['template_id'] as String?,
      templateName: (json['template_name'] as String?) ?? '',
      startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
      endedAt: DateTime.parse(json['ended_at'] as String).toUtc(),
      durationSeconds: (json['duration_seconds'] as int?) ?? 0,
      exercises: (json['exercises'] as List<dynamic>?)
              ?.map(
                  (e) => CompletedExercise.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalSets: (json['total_sets'] as int?) ?? 0,
      totalReps: (json['total_reps'] as int?) ?? 0,
      totalVolume: (json['total_volume'] as num?)?.toDouble() ?? 0.0,
      prs: (json['prs'] as List<dynamic>?)
              ?.map((p) => Map<String, dynamic>.from(p as Map))
              .toList() ??
          [],
      heartRateAvg: json['heart_rate_avg'] as int?,
      heartRateMax: json['heart_rate_max'] as int?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'template_id': templateId,
        'template_name': templateName,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_seconds': durationSeconds,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'heart_rate_avg': heartRateAvg,
        'heart_rate_max': heartRateMax,
        'notes': notes,
      };

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  /// Muscles worked across all exercises (primary only, deduplicated).
  Set<String> get musclesWorked {
    // The exercise definitions aren't available here — this will be populated
    // at the UI layer by cross-referencing the exercise library.
    return {};
  }
}

// ── Personal Records ───────────────────────────────────────────────────────────

class PersonalRecord {
  final String prId;
  final String exerciseId;
  final String exerciseName;
  final String prType; // max_weight, max_reps, max_volume
  final double value;
  final double? previousValue;
  final String sessionId;
  final DateTime achievedAt;

  const PersonalRecord({
    required this.prId,
    required this.exerciseId,
    this.exerciseName = '',
    required this.prType,
    required this.value,
    this.previousValue,
    required this.sessionId,
    required this.achievedAt,
  });

  factory PersonalRecord.fromJson(Map<String, dynamic> json) {
    return PersonalRecord(
      prId: json['pr_id'] as String,
      exerciseId: json['exercise_id'] as String,
      exerciseName: (json['exercise_name'] as String?) ?? '',
      prType: json['pr_type'] as String,
      value: (json['value'] as num).toDouble(),
      previousValue: (json['previous_value'] as num?)?.toDouble(),
      sessionId: json['session_id'] as String,
      achievedAt: DateTime.parse(json['achieved_at'] as String).toUtc(),
    );
  }
}

// ── Overload Advice ────────────────────────────────────────────────────────────

class OverloadSuggestion {
  final String exerciseId;
  final String exerciseName;
  final String suggestionType;
  final double currentValue;
  final double suggestedValue;
  final String reasoning;

  const OverloadSuggestion({
    required this.exerciseId,
    required this.exerciseName,
    required this.suggestionType,
    required this.currentValue,
    required this.suggestedValue,
    required this.reasoning,
  });

  factory OverloadSuggestion.fromJson(Map<String, dynamic> json) {
    return OverloadSuggestion(
      exerciseId: json['exercise_id'] as String,
      exerciseName: (json['exercise_name'] as String?) ?? '',
      suggestionType: json['suggestion_type'] as String,
      currentValue: (json['current_value'] as num).toDouble(),
      suggestedValue: (json['suggested_value'] as num).toDouble(),
      reasoning: json['reasoning'] as String,
    );
  }
}

// ── Legacy compatibility ───────────────────────────────────────────────────────
// The old Exercise / WorkoutPlan classes are kept for backward compatibility
// with the existing WorkoutSessionScreen until it is fully migrated.

class Exercise {
  final String name;
  final int targetReps;
  final int sets;
  final PoseType poseType;

  const Exercise({
    required this.name,
    required this.targetReps,
    required this.sets,
    required this.poseType,
  });
}

class WorkoutPlan {
  final String id;
  final String name;
  final String emoji;
  final List<Exercise> exercises;
  final int restDurationSeconds;
  final bool isFreeDefault;

  const WorkoutPlan({
    required this.id,
    required this.name,
    required this.emoji,
    required this.exercises,
    required this.restDurationSeconds,
    this.isFreeDefault = false,
  });

  static const List<WorkoutPlan> samplePlans = [
    WorkoutPlan(
      id: 'full_body_starter',
      name: 'Full Body Starter',
      emoji: '⭐',
      isFreeDefault: true,
      exercises: [
        Exercise(
            name: 'Squats',
            targetReps: 10,
            sets: 3,
            poseType: PoseType.squat),
        Exercise(
            name: 'Push-Ups',
            targetReps: 8,
            sets: 3,
            poseType: PoseType.pushup),
        Exercise(
            name: 'Lunges',
            targetReps: 10,
            sets: 2,
            poseType: PoseType.lunge),
      ],
      restDurationSeconds: 60,
    ),
  ];

  /// Convert a WorkoutTemplate to a legacy WorkoutPlan for the old session screen.
  factory WorkoutPlan.fromTemplate(WorkoutTemplate template) {
    final exercises = template.allExercises.map((te) {
      return Exercise(
        name: te.exerciseName,
        targetReps: te.defaultReps,
        sets: te.defaultSets,
        poseType: te.poseType ?? PoseType.generic,
      );
    }).toList();
    return WorkoutPlan(
      id: template.templateId,
      name: template.name,
      emoji: template.emoji,
      exercises: exercises,
      restDurationSeconds: template.restDurationSeconds,
      isFreeDefault: template.isSystemDefault,
    );
  }
}
