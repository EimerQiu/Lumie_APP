/// Centralized stick-figure keyframes for all supported exercises.
///
/// Each exercise defines start (top/extended) and end (bottom/contracted)
/// keyframes as maps of landmark name → normalized (0..1) offset.
///
/// Front-view exercises use bilateral landmarks (lShoulder/rShoulder).
/// Side-view exercises use single landmarks (shoulder, elbow, etc.).
///
/// Free-weight exercises include `equipmentProp` to indicate whether
/// the painter should draw dumbbell or barbell shapes.
library;

import 'dart:ui';
import '../../../shared/models/workout_plan_models.dart';

/// All data needed to animate one exercise's stick figure demo.
class ExerciseDemo {
  final Map<String, Offset> start;
  final Map<String, Offset> end;
  final String primaryView; // 'front' or 'side'
  final String? secondaryView;
  final EquipmentProp equipmentProp;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final String formCue; // One-line beginner cue

  const ExerciseDemo({
    required this.start,
    required this.end,
    this.primaryView = 'front',
    this.secondaryView,
    this.equipmentProp = EquipmentProp.none,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.formCue = '',
  });
}

enum EquipmentProp { none, dumbbell, barbell }

/// Look up the demo for a given PoseType.  Returns null for exercises
/// without a defined demo (machine, generic).
ExerciseDemo? getDemoForPoseType(PoseType? pt) {
  if (pt == null) return null;
  return _demos[pt];
}

// ── Bodyweight keyframes (migrated from workout_session_screen.dart) ─────────

const _squatStand = <String, Offset>{
  'head': Offset(0.50, 0.07),
  'neck': Offset(0.50, 0.15),
  'lShoulder': Offset(0.36, 0.22),
  'rShoulder': Offset(0.64, 0.22),
  'lElbow': Offset(0.30, 0.36),
  'rElbow': Offset(0.70, 0.36),
  'lWrist': Offset(0.34, 0.50),
  'rWrist': Offset(0.66, 0.50),
  'lHip': Offset(0.42, 0.52),
  'rHip': Offset(0.58, 0.52),
  'lKnee': Offset(0.42, 0.71),
  'rKnee': Offset(0.58, 0.71),
  'lAnkle': Offset(0.42, 0.93),
  'rAnkle': Offset(0.58, 0.93),
};

const _squatBottom = <String, Offset>{
  'head': Offset(0.50, 0.21),
  'neck': Offset(0.50, 0.29),
  'lShoulder': Offset(0.37, 0.35),
  'rShoulder': Offset(0.63, 0.35),
  'lElbow': Offset(0.27, 0.50),
  'rElbow': Offset(0.73, 0.50),
  'lWrist': Offset(0.30, 0.62),
  'rWrist': Offset(0.70, 0.62),
  'lHip': Offset(0.40, 0.66),
  'rHip': Offset(0.60, 0.66),
  'lKnee': Offset(0.33, 0.74),
  'rKnee': Offset(0.67, 0.74),
  'lAnkle': Offset(0.42, 0.93),
  'rAnkle': Offset(0.58, 0.93),
};

const _pushUpTop = <String, Offset>{
  'head': Offset(0.10, 0.34),
  'neck': Offset(0.18, 0.40),
  'shoulder': Offset(0.26, 0.46),
  'elbow': Offset(0.30, 0.62),
  'wrist': Offset(0.23, 0.72),
  'hip': Offset(0.57, 0.48),
  'knee': Offset(0.74, 0.50),
  'ankle': Offset(0.88, 0.52),
};

const _pushUpBottom = <String, Offset>{
  'head': Offset(0.10, 0.51),
  'neck': Offset(0.18, 0.57),
  'shoulder': Offset(0.26, 0.63),
  'elbow': Offset(0.38, 0.69),
  'wrist': Offset(0.23, 0.74),
  'hip': Offset(0.57, 0.66),
  'knee': Offset(0.74, 0.68),
  'ankle': Offset(0.88, 0.70),
};

const _lungeStand = _squatStand;

const _lungeBottom = <String, Offset>{
  'head': Offset(0.50, 0.09),
  'neck': Offset(0.50, 0.17),
  'lShoulder': Offset(0.36, 0.24),
  'rShoulder': Offset(0.64, 0.24),
  'lElbow': Offset(0.30, 0.37),
  'rElbow': Offset(0.70, 0.37),
  'lWrist': Offset(0.34, 0.50),
  'rWrist': Offset(0.66, 0.50),
  'lHip': Offset(0.44, 0.56),
  'rHip': Offset(0.56, 0.56),
  'lKnee': Offset(0.38, 0.72),
  'rKnee': Offset(0.57, 0.84),
  'lAnkle': Offset(0.34, 0.88),
  'rAnkle': Offset(0.60, 0.96),
};

// ── Dumbbell keyframes ──────────────────────────────────────────────────────

// Bicep curl — side view: arm extended → arm curled
const _curlSideStart = <String, Offset>{
  'head': Offset(0.40, 0.08),
  'neck': Offset(0.40, 0.16),
  'shoulder': Offset(0.40, 0.24),
  'elbow': Offset(0.40, 0.42),
  'wrist': Offset(0.40, 0.58),
  'hip': Offset(0.42, 0.52),
  'knee': Offset(0.44, 0.74),
  'ankle': Offset(0.44, 0.94),
};

const _curlSideEnd = <String, Offset>{
  'head': Offset(0.40, 0.08),
  'neck': Offset(0.40, 0.16),
  'shoulder': Offset(0.40, 0.24),
  'elbow': Offset(0.40, 0.42),
  'wrist': Offset(0.32, 0.28),
  'hip': Offset(0.42, 0.52),
  'knee': Offset(0.44, 0.74),
  'ankle': Offset(0.44, 0.94),
};

// Shoulder press — front view: elbows at 90° → arms overhead
const _shoulderPressStart = <String, Offset>{
  'head': Offset(0.50, 0.07),
  'neck': Offset(0.50, 0.15),
  'lShoulder': Offset(0.36, 0.22),
  'rShoulder': Offset(0.64, 0.22),
  'lElbow': Offset(0.28, 0.30),
  'rElbow': Offset(0.72, 0.30),
  'lWrist': Offset(0.28, 0.18),
  'rWrist': Offset(0.72, 0.18),
  'lHip': Offset(0.42, 0.52),
  'rHip': Offset(0.58, 0.52),
  'lKnee': Offset(0.42, 0.71),
  'rKnee': Offset(0.58, 0.71),
  'lAnkle': Offset(0.42, 0.93),
  'rAnkle': Offset(0.58, 0.93),
};

const _shoulderPressEnd = <String, Offset>{
  'head': Offset(0.50, 0.07),
  'neck': Offset(0.50, 0.15),
  'lShoulder': Offset(0.36, 0.22),
  'rShoulder': Offset(0.64, 0.22),
  'lElbow': Offset(0.32, 0.14),
  'rElbow': Offset(0.68, 0.14),
  'lWrist': Offset(0.36, 0.04),
  'rWrist': Offset(0.64, 0.04),
  'lHip': Offset(0.42, 0.52),
  'rHip': Offset(0.58, 0.52),
  'lKnee': Offset(0.42, 0.71),
  'rKnee': Offset(0.58, 0.71),
  'lAnkle': Offset(0.42, 0.93),
  'rAnkle': Offset(0.58, 0.93),
};

// Lateral raise — front view: arms at sides → arms at shoulder height
const _lateralRaiseStart = _squatStand; // arms down

const _lateralRaiseEnd = <String, Offset>{
  'head': Offset(0.50, 0.07),
  'neck': Offset(0.50, 0.15),
  'lShoulder': Offset(0.36, 0.22),
  'rShoulder': Offset(0.64, 0.22),
  'lElbow': Offset(0.18, 0.22),
  'rElbow': Offset(0.82, 0.22),
  'lWrist': Offset(0.06, 0.22),
  'rWrist': Offset(0.94, 0.22),
  'lHip': Offset(0.42, 0.52),
  'rHip': Offset(0.58, 0.52),
  'lKnee': Offset(0.42, 0.71),
  'rKnee': Offset(0.58, 0.71),
  'lAnkle': Offset(0.42, 0.93),
  'rAnkle': Offset(0.58, 0.93),
};

// Romanian deadlift — side view: standing → hinged forward
const _rdlSideStart = <String, Offset>{
  'head': Offset(0.40, 0.08),
  'neck': Offset(0.40, 0.16),
  'shoulder': Offset(0.40, 0.24),
  'elbow': Offset(0.40, 0.38),
  'wrist': Offset(0.40, 0.50),
  'hip': Offset(0.44, 0.52),
  'knee': Offset(0.46, 0.74),
  'ankle': Offset(0.46, 0.94),
};

const _rdlSideEnd = <String, Offset>{
  'head': Offset(0.22, 0.25),
  'neck': Offset(0.28, 0.30),
  'shoulder': Offset(0.34, 0.36),
  'elbow': Offset(0.40, 0.50),
  'wrist': Offset(0.44, 0.62),
  'hip': Offset(0.50, 0.52),
  'knee': Offset(0.50, 0.74),
  'ankle': Offset(0.46, 0.94),
};

// ── Barbell keyframes ───────────────────────────────────────────────────────

// Back squat — side view: standing with bar → squat bottom
const _backSquatSideStart = <String, Offset>{
  'head': Offset(0.38, 0.08),
  'neck': Offset(0.40, 0.16),
  'shoulder': Offset(0.42, 0.22),
  'elbow': Offset(0.48, 0.24),
  'wrist': Offset(0.44, 0.20),
  'hip': Offset(0.46, 0.52),
  'knee': Offset(0.48, 0.74),
  'ankle': Offset(0.48, 0.94),
};

const _backSquatSideEnd = <String, Offset>{
  'head': Offset(0.32, 0.22),
  'neck': Offset(0.34, 0.30),
  'shoulder': Offset(0.36, 0.36),
  'elbow': Offset(0.42, 0.38),
  'wrist': Offset(0.38, 0.34),
  'hip': Offset(0.50, 0.62),
  'knee': Offset(0.42, 0.76),
  'ankle': Offset(0.48, 0.94),
};

// Bench press — side view: arms extended → arms bent
const _benchPressSideStart = <String, Offset>{
  'head': Offset(0.18, 0.46),
  'neck': Offset(0.25, 0.46),
  'shoulder': Offset(0.34, 0.46),
  'elbow': Offset(0.34, 0.32),
  'wrist': Offset(0.34, 0.18),
  'hip': Offset(0.55, 0.48),
  'knee': Offset(0.70, 0.58),
  'ankle': Offset(0.80, 0.78),
};

const _benchPressSideEnd = <String, Offset>{
  'head': Offset(0.18, 0.46),
  'neck': Offset(0.25, 0.46),
  'shoulder': Offset(0.34, 0.46),
  'elbow': Offset(0.42, 0.42),
  'wrist': Offset(0.34, 0.36),
  'hip': Offset(0.55, 0.48),
  'knee': Offset(0.70, 0.58),
  'ankle': Offset(0.80, 0.78),
};

// Deadlift — side view: hinged at floor → standing
const _deadliftSideStart = <String, Offset>{
  'head': Offset(0.24, 0.28),
  'neck': Offset(0.30, 0.34),
  'shoulder': Offset(0.36, 0.40),
  'elbow': Offset(0.38, 0.55),
  'wrist': Offset(0.40, 0.68),
  'hip': Offset(0.52, 0.52),
  'knee': Offset(0.48, 0.72),
  'ankle': Offset(0.46, 0.94),
};

const _deadliftSideEnd = <String, Offset>{
  'head': Offset(0.40, 0.08),
  'neck': Offset(0.40, 0.16),
  'shoulder': Offset(0.40, 0.24),
  'elbow': Offset(0.40, 0.38),
  'wrist': Offset(0.40, 0.50),
  'hip': Offset(0.44, 0.52),
  'knee': Offset(0.46, 0.74),
  'ankle': Offset(0.46, 0.94),
};

// Barbell row — side view: torso hinged 45°, arms hanging → pulled to chest
const _barbellRowSideStart = <String, Offset>{
  'head': Offset(0.26, 0.22),
  'neck': Offset(0.32, 0.28),
  'shoulder': Offset(0.38, 0.34),
  'elbow': Offset(0.38, 0.52),
  'wrist': Offset(0.38, 0.66),
  'hip': Offset(0.54, 0.48),
  'knee': Offset(0.52, 0.72),
  'ankle': Offset(0.50, 0.94),
};

const _barbellRowSideEnd = <String, Offset>{
  'head': Offset(0.26, 0.22),
  'neck': Offset(0.32, 0.28),
  'shoulder': Offset(0.38, 0.34),
  'elbow': Offset(0.50, 0.40),
  'wrist': Offset(0.42, 0.34),
  'hip': Offset(0.54, 0.48),
  'knee': Offset(0.52, 0.72),
  'ankle': Offset(0.50, 0.94),
};

// ── Demo registry ───────────────────────────────────────────────────────────

const _demos = <PoseType, ExerciseDemo>{
  PoseType.squat: ExerciseDemo(
    start: _squatStand,
    end: _squatBottom,
    primaryView: 'side',
    secondaryView: 'front',
    primaryMuscles: ['Quadriceps', 'Glutes'],
    secondaryMuscles: ['Hamstrings', 'Core'],
    formCue: 'Keep your chest up and knees over toes',
  ),
  PoseType.pushup: ExerciseDemo(
    start: _pushUpTop,
    end: _pushUpBottom,
    primaryView: 'side',
    primaryMuscles: ['Chest'],
    secondaryMuscles: ['Shoulders', 'Triceps'],
    formCue: 'Keep your body in a straight line',
  ),
  PoseType.lunge: ExerciseDemo(
    start: _lungeStand,
    end: _lungeBottom,
    primaryView: 'side',
    secondaryView: 'front',
    primaryMuscles: ['Quadriceps', 'Glutes'],
    secondaryMuscles: ['Hamstrings'],
    formCue: 'Front knee stays at 90 degrees',
  ),
  PoseType.curl: ExerciseDemo(
    start: _curlSideStart,
    end: _curlSideEnd,
    primaryView: 'side',
    secondaryView: 'front',
    equipmentProp: EquipmentProp.dumbbell,
    primaryMuscles: ['Biceps'],
    secondaryMuscles: ['Forearms'],
    formCue: 'Keep your elbows pinned to your sides',
  ),
  PoseType.shoulderPress: ExerciseDemo(
    start: _shoulderPressStart,
    end: _shoulderPressEnd,
    primaryView: 'front',
    secondaryView: 'side',
    equipmentProp: EquipmentProp.dumbbell,
    primaryMuscles: ['Shoulders'],
    secondaryMuscles: ['Triceps'],
    formCue: 'Press straight up, don\'t lean back',
  ),
  PoseType.lateralRaise: ExerciseDemo(
    start: _lateralRaiseStart,
    end: _lateralRaiseEnd,
    primaryView: 'front',
    equipmentProp: EquipmentProp.dumbbell,
    primaryMuscles: ['Shoulders (Lateral Deltoid)'],
    secondaryMuscles: ['Traps'],
    formCue: 'Keep a slight bend in your elbows',
  ),
  PoseType.rdl: ExerciseDemo(
    start: _rdlSideStart,
    end: _rdlSideEnd,
    primaryView: 'side',
    equipmentProp: EquipmentProp.dumbbell,
    primaryMuscles: ['Hamstrings'],
    secondaryMuscles: ['Glutes', 'Lower Back'],
    formCue: 'Push your hips back, keep legs nearly straight',
  ),
  PoseType.backSquat: ExerciseDemo(
    start: _backSquatSideStart,
    end: _backSquatSideEnd,
    primaryView: 'side',
    secondaryView: 'front',
    equipmentProp: EquipmentProp.barbell,
    primaryMuscles: ['Quadriceps'],
    secondaryMuscles: ['Glutes', 'Hamstrings'],
    formCue: 'Brace your core, sit back into the squat',
  ),
  PoseType.benchPress: ExerciseDemo(
    start: _benchPressSideStart,
    end: _benchPressSideEnd,
    primaryView: 'side',
    secondaryView: 'front',
    equipmentProp: EquipmentProp.barbell,
    primaryMuscles: ['Chest'],
    secondaryMuscles: ['Triceps', 'Shoulders'],
    formCue: 'Keep your back flat on the bench',
  ),
  PoseType.deadlift: ExerciseDemo(
    start: _deadliftSideStart,
    end: _deadliftSideEnd,
    primaryView: 'side',
    equipmentProp: EquipmentProp.barbell,
    primaryMuscles: ['Hamstrings', 'Lower Back'],
    secondaryMuscles: ['Glutes', 'Traps'],
    formCue: 'Keep your chest up and bar close to your body',
  ),
  PoseType.barbellRow: ExerciseDemo(
    start: _barbellRowSideStart,
    end: _barbellRowSideEnd,
    primaryView: 'side',
    equipmentProp: EquipmentProp.barbell,
    primaryMuscles: ['Back (Lats, Rhomboids)'],
    secondaryMuscles: ['Biceps'],
    formCue: 'Pull to your lower chest, keep torso still',
  ),
};
