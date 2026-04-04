// Guided workout session screen.
// Manages the full camera-based workout flow:
//   preview → activeSet → rest → complete
//
// Camera streams to google_mlkit_pose_detection for rep counting.
// The closest detected person (largest bounding box) is always used so that
// background people are ignored.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';

// ─── Session state ─────────────────────────────────────────────────────────

enum _SessionState { preview, activeSet, rest, complete }

/// Which side of the body faces the camera for this set.
enum _CameraOrientation { front, leftSide, rightSide }

// ─── Screen ────────────────────────────────────────────────────────────────

class WorkoutSessionScreen extends StatefulWidget {
  final WorkoutPlan workoutPlan;

  const WorkoutSessionScreen({super.key, required this.workoutPlan});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  bool _cameraError = false;

  // ── Pose detection ────────────────────────────────────────────────────────
  PoseDetector? _poseDetector;
  bool _isProcessingFrame = false;
  bool _poseDetected = false; // true when at least one person is in frame
  Pose? _currentPose;
  Size _imageSize = Size.zero;

  // ── Session ───────────────────────────────────────────────────────────────
  _SessionState _state = _SessionState.preview;
  int _exerciseIndex = 0;
  int _setIndex = 0;
  int _currentReps = 0;

  // ── Rest timer ────────────────────────────────────────────────────────────
  Timer? _restTimer;
  int _restSecondsRemaining = 0;

  // ── Rep detection ─────────────────────────────────────────────────────────
  // _repDown: true once the down-phase angle threshold is crossed.
  // A rep is counted when _repDown flips true → false (bottom → top).
  bool _repDown = false;
  String _activeLungeLeg = ''; // 'L' or 'R' while a lunge is in progress

  // Real-time coaching cue shown below the rep counter.
  String _formFeedback = '';
  bool _formGood = false; // true = green "Good form", false = orange warning
  Set<PoseLandmarkType> _badLandmarks = {}; // joints highlighted red

  // Camera orientation detection.
  _CameraOrientation _orientation = _CameraOrientation.front;
  bool _orientationLocked = false;
  int _orientationFrameCount = 0;
  static const _orientationLockFrames = 15;

  // Timing guards.
  DateTime? _repStartTime; // when the down-phase was first entered
  DateTime? _lastPoseTime; // tracks 5-second pause for phase reset

  static const int _minRepMillis = 1000; // minimum ms for a valid rep cycle
  static const int _pauseResetSeconds = 5; // idle pause resets phase

  // Thresholds for exercises without dedicated detectors (curl, press, generic).
  static const Map<PoseType, (double down, double up)> _thresholds = {
    PoseType.squat: (100.0, 155.0),
    PoseType.lunge: (100.0, 155.0),
    PoseType.curl: (60.0, 150.0),
    PoseType.pushup: (90.0, 155.0),
    PoseType.shoulderPress: (80.0, 155.0),
    PoseType.generic: (100.0, 150.0),
  };

  // Required landmarks per exercise type — ≥ 50% must have likelihood ≥ 0.4.
  static const Map<PoseType, List<PoseLandmarkType>> _requiredLandmarks = {
    PoseType.squat: [
      PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle,
    ],
    PoseType.lunge: [
      PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee,
      PoseLandmarkType.leftAnkle, PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle,
    ],
    PoseType.pushup: [
      PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow,
      PoseLandmarkType.leftWrist, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
    ],
    PoseType.curl: [
      PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow,
      PoseLandmarkType.rightWrist,
    ],
    PoseType.shoulderPress: [
      PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow,
      PoseLandmarkType.rightWrist,
    ],
    PoseType.generic: [
      PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee,
    ],
  };

  Exercise get _currentExercise => widget.workoutPlan.exercises[_exerciseIndex];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initPoseDetector();
    _initCamera();
  }

  void _initPoseDetector() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(model: PoseDetectionModel.base),
    );
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = true);
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _cameraInitialized = true);
      _cameraController!.startImageStream(_onCameraFrame);
    } catch (_) {
      if (mounted) setState(() => _cameraError = true);
    }
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _poseDetector?.close();
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Camera frame processing ───────────────────────────────────────────────

  void _onCameraFrame(CameraImage image) async {
    if (_isProcessingFrame) return;
    if (_state == _SessionState.complete) return;
    _isProcessingFrame = true;
    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) {
        _isProcessingFrame = false;
        return;
      }
      final poses = await _poseDetector!.processImage(inputImage);
      if (!mounted) {
        _isProcessingFrame = false;
        return;
      }
      // Select the closest person (largest bounding box = fewest depth units away).
      Pose? closest;
      if (poses.isNotEmpty) {
        closest = poses.reduce((a, b) => _poseArea(a) >= _poseArea(b) ? a : b);
      }
      final detected = closest != null;
      setState(() {
        _poseDetected = detected;
        _currentPose = closest;
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
      if (_state == _SessionState.activeSet && closest != null) {
        _detectRep(closest);
      }
    } catch (_) {}
    _isProcessingFrame = false;
  }

  InputImage? _toInputImage(CameraImage image) {
    if (_cameraController == null) return null;
    final rotation =
        InputImageRotationValue.fromRawValue(
          _cameraController!.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    final bytes = image.planes.length == 1
        ? image.planes.first.bytes
        : _concatPlanes(image);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatPlanes(CameraImage image) {
    int total = 0;
    for (final p in image.planes) {
      total += p.bytes.length;
    }
    final out = Uint8List(total);
    int offset = 0;
    for (final p in image.planes) {
      out.setRange(offset, offset + p.bytes.length, p.bytes);
      offset += p.bytes.length;
    }
    return out;
  }

  double _poseArea(Pose pose) {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final lm in pose.landmarks.values) {
      if (lm.x < minX) minX = lm.x;
      if (lm.x > maxX) maxX = lm.x;
      if (lm.y < minY) minY = lm.y;
      if (lm.y > maxY) maxY = lm.y;
    }
    return (maxX - minX) * (maxY - minY);
  }

  // ── Rep detection ─────────────────────────────────────────────────────────

  bool _hasEnoughLandmarks(Pose pose, PoseType type) {
    final required = _requiredLandmarks[type] ?? [];
    if (required.isEmpty) return true;
    final visible = required.where((t) {
      final lm = pose.landmarks[t];
      return lm != null && lm.likelihood >= 0.4;
    }).length;
    return visible * 2 >= required.length; // ≥ 50 %
  }

  /// Returns the camera orientation inferred from landmark visibility.
  _CameraOrientation _detectOrientation(Pose pose) {
    if (_imageSize == Size.zero) return _CameraOrientation.front;
    final lm = pose.landmarks;
    final ls = lm[PoseLandmarkType.leftShoulder];
    final rs = lm[PoseLandmarkType.rightShoulder];
    if (ls == null || rs == null ||
        ls.likelihood < 0.4 || rs.likelihood < 0.4) {
      return _CameraOrientation.front;
    }
    // Wide shoulder separation → front view.
    final sep = (ls.x - rs.x).abs() / _imageSize.width;
    if (sep >= 0.15) return _CameraOrientation.front;

    // Narrow → side view: pick side with higher average landmark confidence.
    double leftSum = 0, rightSum = 0;
    int leftN = 0, rightN = 0;
    for (final t in [
      PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip,
      PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle,
    ]) {
      final l = lm[t];
      if (l != null) { leftSum += l.likelihood; leftN++; }
    }
    for (final t in [
      PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle,
    ]) {
      final l = lm[t];
      if (l != null) { rightSum += l.likelihood; rightN++; }
    }
    final leftAvg = leftN > 0 ? leftSum / leftN : 0.0;
    final rightAvg = rightN > 0 ? rightSum / rightN : 0.0;
    return leftAvg >= rightAvg
        ? _CameraOrientation.leftSide
        : _CameraOrientation.rightSide;
  }

  void _detectRep(Pose pose) {
    final type = _currentExercise.poseType;

    if (!_hasEnoughLandmarks(pose, type)) {
      _setFeedback('Make sure your full body is visible to the camera', false);
      return;
    }

    // ── Orientation lock ────────────────────────────────────────────────────
    // Sample orientation for the first N frames of each set, then lock it.
    if (!_orientationLocked) {
      _orientation = _detectOrientation(pose);
      _orientationFrameCount++;
      if (_orientationFrameCount >= _orientationLockFrames) {
        _orientationLocked = true;
      }
      // Still allow rep detection while sampling; orientation will converge.
    } else if (_repDown) {
      // Mid-set consistency check: warn if orientation drifted significantly.
      final current = _detectOrientation(pose);
      if (current != _orientation) {
        _setFeedback('Please keep your position consistent', false, {});
        return;
      }
    }

    // ── 5-second pause → reset phase (keeps counted reps) ──────────────────
    final now = DateTime.now();
    if (_lastPoseTime != null &&
        now.difference(_lastPoseTime!).inSeconds >= _pauseResetSeconds) {
      _repDown = false;
      _activeLungeLeg = '';
      _repStartTime = null;
    }
    _lastPoseTime = now;

    switch (type) {
      case PoseType.squat:
        _detectSquatRep(pose);
      case PoseType.pushup:
        _detectPushupRep(pose);
      case PoseType.lunge:
        _detectLungeRep(pose);
      default:
        _detectGenericRep(pose);
    }
  }

  // ── Squat ──────────────────────────────────────────────────────────────────

  void _detectSquatRep(Pose pose) {
    final lm = pose.landmarks;

    // Pick knee angles based on locked orientation.
    double? leftKnee, rightKnee;
    switch (_orientation) {
      case _CameraOrientation.leftSide:
        final a = _angle(lm[PoseLandmarkType.leftHip],
            lm[PoseLandmarkType.leftKnee], lm[PoseLandmarkType.leftAnkle]);
        if (a == null) return;
        leftKnee = rightKnee = a;
      case _CameraOrientation.rightSide:
        final a = _angle(lm[PoseLandmarkType.rightHip],
            lm[PoseLandmarkType.rightKnee], lm[PoseLandmarkType.rightAnkle]);
        if (a == null) return;
        leftKnee = rightKnee = a;
      case _CameraOrientation.front:
        leftKnee = _angle(lm[PoseLandmarkType.leftHip],
            lm[PoseLandmarkType.leftKnee], lm[PoseLandmarkType.leftAnkle]);
        rightKnee = _angle(lm[PoseLandmarkType.rightHip],
            lm[PoseLandmarkType.rightKnee], lm[PoseLandmarkType.rightAnkle]);
        if (leftKnee == null || rightKnee == null) return;
    }

    final avgKnee = (leftKnee + rightKnee) / 2;
    final atDepth = leftKnee <= 100 && rightKnee <= 100;
    final atTop   = leftKnee >= 155 && rightKnee >= 155;

    // Torso lean: approximate angle of spine from vertical in image plane.
    // Use visible-side landmarks based on orientation.
    bool torsoOk = true;
    final useLeft = _orientation != _CameraOrientation.rightSide;
    final useRight = _orientation != _CameraOrientation.leftSide;
    final lHip = useLeft  ? lm[PoseLandmarkType.leftHip]      : null;
    final rHip = useRight ? lm[PoseLandmarkType.rightHip]     : null;
    final lSh  = useLeft  ? lm[PoseLandmarkType.leftShoulder]  : null;
    final rSh  = useRight ? lm[PoseLandmarkType.rightShoulder] : null;
    final hipRef      = lHip ?? rHip;
    final shoulderRef = lSh  ?? rSh;
    if (hipRef != null && shoulderRef != null &&
        hipRef.likelihood >= 0.4 && shoulderRef.likelihood >= 0.4) {
      final dx = (shoulderRef.x - hipRef.x).abs();
      final dy = (hipRef.y - shoulderRef.y).abs();
      final lean = dy > 0 ? atan(dx / dy) * 180 / pi : 90.0;
      torsoOk = lean <= 45;
    }

    // Knee-over-ankle tracking (only reliable in front view).
    bool kneesTracking = true;
    if (_orientation == _CameraOrientation.front &&
        _imageSize != Size.zero) {
      final lKneeLm  = lm[PoseLandmarkType.leftKnee];
      final lAnkleLm = lm[PoseLandmarkType.leftAnkle];
      final rKneeLm  = lm[PoseLandmarkType.rightKnee];
      final rAnkleLm = lm[PoseLandmarkType.rightAnkle];
      if (lKneeLm != null && lAnkleLm != null &&
          rKneeLm != null && rAnkleLm != null &&
          lKneeLm.likelihood >= 0.4 && lAnkleLm.likelihood >= 0.4 &&
          rKneeLm.likelihood >= 0.4 && rAnkleLm.likelihood >= 0.4) {
        final threshold = _imageSize.width * 0.10;
        kneesTracking = (lKneeLm.x - lAnkleLm.x).abs() <= threshold &&
            (rKneeLm.x - rAnkleLm.x).abs() <= threshold;
      }
    }

    // Phase state machine — rep counts regardless of form quality.
    if (!_repDown && atDepth) {
      _repDown = true;
      _repStartTime = DateTime.now();
    } else if (_repDown && atTop) {
      final elapsed = _repStartTime != null
          ? DateTime.now().difference(_repStartTime!).inMilliseconds
          : _minRepMillis;
      if (elapsed >= _minRepMillis) {
        _repDown = false;
        _repStartTime = null;
        _incrementRep();
      }
    }

    // Feedback + red-highlight affected joints.
    if (!torsoOk) {
      _setFeedback('Keep your chest up', false, {
        PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      });
    } else if (!kneesTracking) {
      _setFeedback('Keep your knees over your toes', false, {
        PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle,
      });
    } else if (!atDepth && avgKnee < 155 && avgKnee > 100) {
      _setFeedback('Lower your hips more', false, {
        PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      });
    } else if (atDepth) {
      _setFeedback('Good depth — drive through your heels', true);
    } else {
      _setFeedback('Good form ✓', true);
    }
  }

  // ── Push-Up ────────────────────────────────────────────────────────────────

  void _detectPushupRep(Pose pose) {
    final lm = pose.landmarks;

    // Elbow angle(s) based on orientation.
    double? elbowA, elbowB;
    switch (_orientation) {
      case _CameraOrientation.leftSide:
        elbowA = elbowB = _angle(lm[PoseLandmarkType.leftShoulder],
            lm[PoseLandmarkType.leftElbow], lm[PoseLandmarkType.leftWrist]);
      case _CameraOrientation.rightSide:
        elbowA = elbowB = _angle(lm[PoseLandmarkType.rightShoulder],
            lm[PoseLandmarkType.rightElbow], lm[PoseLandmarkType.rightWrist]);
      case _CameraOrientation.front:
        final l = _angle(lm[PoseLandmarkType.leftShoulder],
            lm[PoseLandmarkType.leftElbow], lm[PoseLandmarkType.leftWrist]);
        final r = _angle(lm[PoseLandmarkType.rightShoulder],
            lm[PoseLandmarkType.rightElbow], lm[PoseLandmarkType.rightWrist]);
        elbowA = l ?? r;
        elbowB = r ?? l;
    }
    if (elbowA == null || elbowB == null) return;

    final avgElbow = (elbowA + elbowB) / 2;
    final atDown = elbowA <= 90 && elbowB <= 90;
    final atUp   = elbowA >= 155 && elbowB >= 155;

    // Body alignment: shoulder → hip → ankle (~180°). Use visible side.
    bool bodyAligned = true;
    PoseLandmark? shoulder, hip, ankle;
    if (_orientation != _CameraOrientation.rightSide) {
      shoulder = lm[PoseLandmarkType.leftShoulder];
      hip      = lm[PoseLandmarkType.leftHip];
      ankle    = lm[PoseLandmarkType.leftAnkle];
    } else {
      shoulder = lm[PoseLandmarkType.rightShoulder];
      hip      = lm[PoseLandmarkType.rightHip];
      ankle    = lm[PoseLandmarkType.rightAnkle];
    }
    if (shoulder != null && hip != null && ankle != null &&
        shoulder.likelihood >= 0.4 && hip.likelihood >= 0.4 &&
        ankle.likelihood >= 0.4) {
      final a = _angle(shoulder, hip, ankle);
      if (a != null) bodyAligned = a >= 160;
    }

    // Phase state machine — form issues never block the rep count.
    if (!_repDown && atDown) {
      _repDown = true;
      _repStartTime = DateTime.now();
    } else if (_repDown && atUp) {
      final elapsed = _repStartTime != null
          ? DateTime.now().difference(_repStartTime!).inMilliseconds
          : _minRepMillis;
      if (elapsed >= _minRepMillis) {
        _repDown = false;
        _repStartTime = null;
        _incrementRep();
      }
    }

    if (!bodyAligned) {
      _setFeedback('Keep your body straight', false, {
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      });
    } else if (!atDown && avgElbow < 155 && avgElbow > 90) {
      _setFeedback('Lower your chest more', false, {
        PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
      });
    } else if (atDown) {
      _setFeedback('Good depth — push back up', true);
    } else {
      _setFeedback('Good form ✓', true);
    }
  }

  // ── Lunge ──────────────────────────────────────────────────────────────────

  void _detectLungeRep(Pose pose) {
    final lm = pose.landmarks;

    // Both knees always checked regardless of orientation — in a lunge both
    // legs are visible even from the side.
    final leftKnee = _angle(lm[PoseLandmarkType.leftHip],
        lm[PoseLandmarkType.leftKnee], lm[PoseLandmarkType.leftAnkle]);
    final rightKnee = _angle(lm[PoseLandmarkType.rightHip],
        lm[PoseLandmarkType.rightKnee], lm[PoseLandmarkType.rightAnkle]);
    if (leftKnee == null || rightKnee == null) return;

    final eitherAtDepth = leftKnee <= 100 || rightKnee <= 100;
    final bothAtTop     = leftKnee >= 155 && rightKnee >= 155;

    // Torso lean check (visible-side landmarks).
    bool torsoOk = true;
    final useLeft  = _orientation != _CameraOrientation.rightSide;
    final hipRef      = useLeft
        ? lm[PoseLandmarkType.leftHip]
        : lm[PoseLandmarkType.rightHip];
    final shoulderRef = useLeft
        ? lm[PoseLandmarkType.leftShoulder]
        : lm[PoseLandmarkType.rightShoulder];
    if (hipRef != null && shoulderRef != null &&
        hipRef.likelihood >= 0.4 && shoulderRef.likelihood >= 0.4) {
      final dx = (shoulderRef.x - hipRef.x).abs();
      final dy = (hipRef.y - shoulderRef.y).abs();
      final lean = dy > 0 ? atan(dx / dy) * 180 / pi : 90.0;
      torsoOk = lean <= 40;
    }

    // Phase state machine — form issues never block the rep count.
    if (!_repDown && eitherAtDepth) {
      _repDown = true;
      _repStartTime = DateTime.now();
      _activeLungeLeg = leftKnee <= rightKnee ? 'L' : 'R';
    } else if (_repDown && bothAtTop) {
      final elapsed = _repStartTime != null
          ? DateTime.now().difference(_repStartTime!).inMilliseconds
          : _minRepMillis;
      if (elapsed >= _minRepMillis) {
        _repDown = false;
        _repStartTime = null;
        _activeLungeLeg = '';
        _incrementRep();
      }
    }

    if (!torsoOk) {
      _setFeedback('Keep your torso upright', false, {
        PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
      });
    } else if (_repDown && !bothAtTop) {
      final leg = _activeLungeLeg == 'L' ? 'Left' : 'Right';
      _setFeedback('Good — drive through your $leg heel', true);
    } else if (!eitherAtDepth && (leftKnee < 155 || rightKnee < 155)) {
      _setFeedback('Lower your hips more', false, {
        PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
      });
    } else {
      _setFeedback('Good form ✓', true);
    }
  }

  // ── Generic (curl, shoulder press, other) ──────────────────────────────────

  void _detectGenericRep(Pose pose) {
    final angle = _exerciseAngle(pose, _currentExercise.poseType);
    if (angle == null) return;
    final thresh = _thresholds[_currentExercise.poseType]!;
    if (!_repDown && angle < thresh.$1) {
      _repDown = true;
      _repStartTime = DateTime.now();
    } else if (_repDown && angle > thresh.$2) {
      final elapsed = _repStartTime != null
          ? DateTime.now().difference(_repStartTime!).inMilliseconds
          : _minRepMillis;
      if (elapsed >= _minRepMillis) {
        _repDown = false;
        _repStartTime = null;
        _incrementRep();
      }
    }
    _setFeedback(angle < thresh.$1 ? 'Good range of motion ✓' : 'Good form ✓', true);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setFeedback(String message, bool good,
      [Set<PoseLandmarkType> bad = const {}]) {
    if (_formFeedback == message &&
        _formGood == good &&
        _badLandmarks.length == bad.length &&
        _badLandmarks.containsAll(bad)) {
      return;
    }
    if (mounted) {
      setState(() {
        _formFeedback = message;
        _formGood = good;
        _badLandmarks = bad;
      });
    }
  }

  double? _exerciseAngle(Pose pose, PoseType type) {
    final lm = pose.landmarks;
    switch (type) {
      case PoseType.curl:
      case PoseType.shoulderPress:
        return _angle(lm[PoseLandmarkType.rightShoulder],
            lm[PoseLandmarkType.rightElbow], lm[PoseLandmarkType.rightWrist]);
      case PoseType.generic:
        return _angle(lm[PoseLandmarkType.rightShoulder],
            lm[PoseLandmarkType.rightHip], lm[PoseLandmarkType.rightKnee]);
      default:
        return null;
    }
  }

  double? _angle(PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) {
    if (a == null || b == null || c == null) return null;
    if (a.likelihood < 0.4 || b.likelihood < 0.4 || c.likelihood < 0.4) {
      return null;
    }
    final abX = a.x - b.x, abY = a.y - b.y;
    final cbX = c.x - b.x, cbY = c.y - b.y;
    final dot = abX * cbX + abY * cbY;
    final magAB = sqrt(abX * abX + abY * abY);
    final magCB = sqrt(cbX * cbX + cbY * cbY);
    if (magAB == 0 || magCB == 0) return 180.0;
    return acos((dot / (magAB * magCB)).clamp(-1.0, 1.0)) * 180 / pi;
  }

  // ── Session flow ──────────────────────────────────────────────────────────

  void _incrementRep() {
    if (_currentReps >= _currentExercise.targetReps) return;
    setState(() => _currentReps++);
    if (_currentReps >= _currentExercise.targetReps) {
      // Short pause so the user sees the counter hit the target.
      Future.delayed(const Duration(milliseconds: 700), _onSetComplete);
    }
  }

  void _onSetComplete() {
    if (!mounted) return;
    final isLastSet = _setIndex >= _currentExercise.sets - 1;
    final isLastExercise =
        _exerciseIndex >= widget.workoutPlan.exercises.length - 1;
    if (isLastSet && isLastExercise) {
      _endSession();
      return;
    }
    setState(() {
      _state = _SessionState.rest;
      _restSecondsRemaining = widget.workoutPlan.restDurationSeconds;
    });
    _startRestCountdown();
  }

  void _startRestCountdown() {
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _restSecondsRemaining--);
      if (_restSecondsRemaining <= 0) {
        t.cancel();
        _advanceAfterRest();
      }
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    _advanceAfterRest();
  }

  void _advanceAfterRest() {
    if (!mounted) return;
    final isLastSet = _setIndex >= _currentExercise.sets - 1;
    setState(() {
      if (isLastSet) {
        _exerciseIndex++;
        _setIndex = 0;
      } else {
        _setIndex++;
      }
      _currentReps = 0;
      _repDown = false;
      _activeLungeLeg = '';
      _repStartTime = null;
      _lastPoseTime = null;
      _formFeedback = '';
      _formGood = false;
      _badLandmarks = {};
      _orientation = _CameraOrientation.front;
      _orientationLocked = false;
      _orientationFrameCount = 0;
      _state = _SessionState.activeSet;
    });
  }

  void _endSession() {
    _cameraController?.stopImageStream();
    setState(() => _state = _SessionState.complete);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _SessionState.preview:
        return _buildPreview();
      case _SessionState.activeSet:
        return _buildActiveSet();
      case _SessionState.rest:
        return _buildRest();
      case _SessionState.complete:
        return _buildComplete();
    }
  }

  // ── Preview view ───────────────────────────────────────────────────────────

  Widget _buildPreview() {
    final plan = widget.workoutPlan;
    final first = plan.exercises.first;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCameraFeed(),
        // Close button
        Positioned(
          top: 12,
          left: 16,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ),
        ),
        // Workout info card
        Positioned(
          top: 12,
          left: 56,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.emoji}  ${plan.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'First: ${first.name} · '
                  '${first.targetReps} reps × ${first.sets} sets',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        // Pose status badge
        if (_cameraInitialized)
          Center(
            child: _poseDetected
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Step into frame',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
          ),
        // Pose detected indicator border
        if (_poseDetected)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.7),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        // Start button
        Positioned(
          bottom: 40,
          left: 32,
          right: 32,
          child: Column(
            children: [
              if (_poseDetected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Pose detected — tap Start when ready',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      setState(() => _state = _SessionState.activeSet),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLemonDark,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Start',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Active set view ────────────────────────────────────────────────────────

  Widget _buildActiveSet() {
    final exercise = _currentExercise;
    final repsLeft = exercise.targetReps - _currentReps;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCameraFeed(),
        // Exercise info overlay
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Set ${_setIndex + 1} of ${exercise.sets}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${exercise.targetReps} reps',
                  style: const TextStyle(
                    color: AppColors.primaryLemonDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Rep counter
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_currentReps',
                style: const TextStyle(
                  fontSize: 100,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              Text(
                '$repsLeft left',
                style: const TextStyle(color: Colors.white60, fontSize: 18),
              ),
            ],
          ),
        ),
        // Progress bar + status
        Positioned(
          bottom: 48,
          left: 24,
          right: 24,
          child: Column(
            children: [
              if (_formFeedback.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: (_formGood ? AppColors.success : Colors.orange)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formFeedback,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _formGood ? AppColors.success : Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Text(
                  _poseDetected ? 'Counting reps...' : 'No pose detected',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: exercise.targetReps > 0
                      ? _currentReps / exercise.targetReps
                      : 0,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(
                    AppColors.primaryLemonDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Rest view ──────────────────────────────────────────────────────────────

  Widget _buildRest() {
    final mins = _restSecondsRemaining ~/ 60;
    final secs = _restSecondsRemaining % 60;
    final timeLabel = mins > 0
        ? '$mins:${secs.toString().padLeft(2, '0')}'
        : '$_restSecondsRemaining';
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCameraFeed(),
        // Blur overlay
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),
        ),
        // Rest content
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'REST',
                style: TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                  color: AppColors.error,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                timeLabel,
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _nextLabel(),
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 40),
              TextButton(
                onPressed: _skipRest,
                child: const Text(
                  'Skip Rest',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _nextLabel() {
    final isLastSet = _setIndex >= _currentExercise.sets - 1;
    if (isLastSet) {
      final nextIdx = _exerciseIndex + 1;
      if (nextIdx < widget.workoutPlan.exercises.length) {
        return 'Next: ${widget.workoutPlan.exercises[nextIdx].name}';
      }
    }
    return 'Next: ${_currentExercise.name} — Set ${_setIndex + 2}';
  }

  // ── Complete view ──────────────────────────────────────────────────────────

  Widget _buildComplete() {
    final plan = widget.workoutPlan;
    final totalSets = plan.exercises.fold(0, (s, e) => s + e.sets);
    final totalReps = plan.exercises.fold(
      0,
      (s, e) => s + e.targetReps * e.sets,
    );
    return Column(
      children: [
        const SizedBox(height: 24),
        const Text(
          'Workout Complete',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLemon.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      plan.emoji,
                      style: const TextStyle(fontSize: 44),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  plan.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CompleteStat(
                      icon: Icons.fitness_center,
                      label: 'Exercises',
                      value: '${plan.exercises.length}',
                    ),
                    _CompleteStat(
                      icon: Icons.repeat,
                      label: 'Total Sets',
                      value: '$totalSets',
                    ),
                    _CompleteStat(
                      icon: Icons.numbers,
                      label: 'Total Reps',
                      value: '$totalReps',
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Exercise breakdown
                ...plan.exercises.map(
                  (ex) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ex.name,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          '${ex.sets} × ${ex.targetReps}',
                          style: const TextStyle(
                            color: AppColors.primaryLemonDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Save / Discard
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Save workout record to backend via API
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLemonDark,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Save Workout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Discard',
                  style: TextStyle(fontSize: 14, color: Colors.white30),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Camera feed widget ────────────────────────────────────────────────────

  Widget _buildCameraFeed() {
    if (_cameraError) {
      return Container(
        color: const Color(0xFF1A1816),
        child: const Center(
          child: Text(
            'Camera unavailable',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
      );
    }
    if (!_cameraInitialized || _cameraController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryLemonDark),
        ),
      );
    }
    final previewSize = _cameraController!.value.previewSize;
    if (previewSize == null) {
      return Container(color: Colors.black);
    }
    final rotation =
        InputImageRotationValue.fromRawValue(
          _cameraController!.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;
    final isFront =
        _cameraController!.description.lensDirection ==
        CameraLensDirection.front;

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(_cameraController!),
          ),
        ),
        if (_currentPose != null && _imageSize != Size.zero)
          CustomPaint(
            painter: _PosePainter(
              pose: _currentPose!,
              imageSize: _imageSize,
              rotation: rotation,
              isFrontCamera: isFront,
              badLandmarks: _badLandmarks,
            ),
          ),
      ],
    );
  }
}

// ─── Pose skeleton painter ────────────────────────────────────────────────────

class _PosePainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  final Set<PoseLandmarkType> badLandmarks;

  static const _connections = [
    (PoseLandmarkType.nose, PoseLandmarkType.leftEye),
    (PoseLandmarkType.nose, PoseLandmarkType.rightEye),
    (PoseLandmarkType.leftEye, PoseLandmarkType.leftEar),
    (PoseLandmarkType.rightEye, PoseLandmarkType.rightEar),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
    (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
    (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
    (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
    (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
    (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
    (PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel),
    (PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex),
    (PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex),
    (PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel),
    (PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex),
    (PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex),
    (PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb),
    (PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex),
    (PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinky),
    (PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb),
    (PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex),
    (PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinky),
  ];

  const _PosePainter({
    required this.pose,
    required this.imageSize,
    required this.rotation,
    required this.isFrontCamera,
    this.badLandmarks = const {},
  });

  // Translates a landmark's x coordinate to canvas x.
  // Follows the same formula as the official google_mlkit_flutter example.
  double _tx(double x, Size canvas) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x * canvas.width / imageSize.height;
      case InputImageRotation.rotation270deg:
        return canvas.width - x * canvas.width / imageSize.height;
      default:
        return isFrontCamera
            ? canvas.width - x * canvas.width / imageSize.width
            : x * canvas.width / imageSize.width;
    }
  }

  double _ty(double y, Size canvas) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * canvas.height / imageSize.width;
      default:
        return y * canvas.height / imageSize.height;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF00E5CC).withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final badLinePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.90)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final badDotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final dotRingPaint = Paint()
      ..color = const Color(0xFF00E5CC)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final badDotRingPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Connection lines — red if either endpoint is flagged.
    for (final (fromType, toType) in _connections) {
      final from = pose.landmarks[fromType];
      final to = pose.landmarks[toType];
      if (from == null || to == null) continue;
      if (from.likelihood < 0.5 || to.likelihood < 0.5) continue;
      final isBad = badLandmarks.contains(fromType) ||
          badLandmarks.contains(toType);
      canvas.drawLine(
        Offset(_tx(from.x, size), _ty(from.y, size)),
        Offset(_tx(to.x, size), _ty(to.y, size)),
        isBad ? badLinePaint : linePaint,
      );
    }

    // Landmark dots — red fill + ring for flagged joints.
    for (final entry in pose.landmarks.entries) {
      final lm = entry.value;
      if (lm.likelihood < 0.5) continue;
      final pt = Offset(_tx(lm.x, size), _ty(lm.y, size));
      final isBad = badLandmarks.contains(entry.key);
      canvas.drawCircle(pt, 5, isBad ? badDotPaint : dotPaint);
      canvas.drawCircle(pt, 5, isBad ? badDotRingPaint : dotRingPaint);
    }
  }

  @override
  bool shouldRepaint(_PosePainter old) =>
      old.pose != pose || old.badLandmarks != badLandmarks;
}

// ─── Stat widget for complete view ────────────────────────────────────────────

class _CompleteStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CompleteStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryLemonDark, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }
}
