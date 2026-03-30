/// Models for saved/personalized workout plans used in the guided session flow.
library;

enum PoseType { squat, curl, pushup, lunge, shoulderPress, generic }

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

  /// Seconds to rest between sets.
  final int restDurationSeconds;

  /// True for the one plan that is available to all users at no cost.
  /// All other plans require an active subscription.
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
    // ── Free default — available to every user ─────────────────────────────
    WorkoutPlan(
      id: 'full_body_starter',
      name: 'Full Body Starter',
      emoji: '⭐',
      isFreeDefault: true,
      exercises: [
        Exercise(name: 'Squats', targetReps: 10, sets: 3, poseType: PoseType.squat),
        Exercise(name: 'Push-Ups', targetReps: 8, sets: 3, poseType: PoseType.pushup),
        Exercise(name: 'Lunges', targetReps: 10, sets: 2, poseType: PoseType.lunge),
      ],
      restDurationSeconds: 60,
    ),
    // ── Premium plans ──────────────────────────────────────────────────────
    WorkoutPlan(
      id: 'strength_basics',
      name: 'Strength Basics',
      emoji: '💪',
      exercises: [
        Exercise(name: 'Squats', targetReps: 12, sets: 3, poseType: PoseType.squat),
        Exercise(name: 'Push-Ups', targetReps: 10, sets: 3, poseType: PoseType.pushup),
        Exercise(name: 'Bicep Curls', targetReps: 12, sets: 3, poseType: PoseType.curl),
      ],
      restDurationSeconds: 60,
    ),
    WorkoutPlan(
      id: 'cardio_flow',
      name: 'Cardio Flow',
      emoji: '🔥',
      exercises: [
        Exercise(name: 'Jumping Jacks', targetReps: 20, sets: 3, poseType: PoseType.generic),
        Exercise(name: 'High Knees', targetReps: 20, sets: 3, poseType: PoseType.generic),
        Exercise(name: 'Squat Jumps', targetReps: 15, sets: 3, poseType: PoseType.squat),
      ],
      restDurationSeconds: 30,
    ),
    WorkoutPlan(
      id: 'leg_day',
      name: 'Leg Day',
      emoji: '🦵',
      exercises: [
        Exercise(name: 'Squats', targetReps: 15, sets: 4, poseType: PoseType.squat),
        Exercise(name: 'Lunges', targetReps: 12, sets: 3, poseType: PoseType.lunge),
      ],
      restDurationSeconds: 90,
    ),
    WorkoutPlan(
      id: 'upper_body',
      name: 'Upper Body',
      emoji: '🏋️',
      exercises: [
        Exercise(name: 'Push-Ups', targetReps: 12, sets: 3, poseType: PoseType.pushup),
        Exercise(name: 'Bicep Curls', targetReps: 12, sets: 3, poseType: PoseType.curl),
        Exercise(name: 'Shoulder Press', targetReps: 10, sets: 3, poseType: PoseType.shoulderPress),
      ],
      restDurationSeconds: 60,
    ),
  ];
}
