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

  // ── Session ───────────────────────────────────────────────────────────────
  _SessionState _state = _SessionState.preview;
  int _exerciseIndex = 0;
  int _setIndex = 0;
  int _currentReps = 0;

  // ── Rest timer ────────────────────────────────────────────────────────────
  Timer? _restTimer;
  int _restSecondsRemaining = 0;

  // ── Rep detection ─────────────────────────────────────────────────────────
  // Hysteresis: a rep is counted when the joint angle dips below _downThresh
  // and then recovers above _upThresh.
  bool _repDown = false;

  // Per-exercise angle thresholds (degrees). Tuned for common movements.
  static const Map<PoseType, (double down, double up)> _thresholds = {
    PoseType.squat:        (100.0, 155.0),
    PoseType.lunge:        (100.0, 155.0),
    PoseType.curl:         ( 60.0, 150.0),
    PoseType.pushup:       ( 80.0, 155.0),
    PoseType.shoulderPress:(  80.0, 155.0),
    PoseType.generic:      (100.0, 150.0),
  };

  Exercise get _currentExercise =>
      widget.workoutPlan.exercises[_exerciseIndex];

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
        closest = poses.reduce(
          (a, b) => _poseArea(a) >= _poseArea(b) ? a : b,
        );
      }
      final detected = closest != null;
      setState(() => _poseDetected = detected);
      if (_state == _SessionState.activeSet && closest != null) {
        _detectRep(closest);
      }
    } catch (_) {}
    _isProcessingFrame = false;
  }

  InputImage? _toInputImage(CameraImage image) {
    if (_cameraController == null) return null;
    final rotation = InputImageRotationValue.fromRawValue(
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

  void _detectRep(Pose pose) {
    final angle = _exerciseAngle(pose, _currentExercise.poseType);
    if (angle == null) return;
    final thresh = _thresholds[_currentExercise.poseType]!;
    if (!_repDown && angle < thresh.$1) {
      _repDown = true;
    } else if (_repDown && angle > thresh.$2) {
      _repDown = false;
      _incrementRep();
    }
  }

  double? _exerciseAngle(Pose pose, PoseType type) {
    final lm = pose.landmarks;
    switch (type) {
      case PoseType.squat:
      case PoseType.lunge:
        return _angle(
          lm[PoseLandmarkType.rightHip],
          lm[PoseLandmarkType.rightKnee],
          lm[PoseLandmarkType.rightAnkle],
        );
      case PoseType.curl:
      case PoseType.shoulderPress:
        return _angle(
          lm[PoseLandmarkType.rightShoulder],
          lm[PoseLandmarkType.rightElbow],
          lm[PoseLandmarkType.rightWrist],
        );
      case PoseType.pushup:
        return _angle(
          lm[PoseLandmarkType.rightShoulder],
          lm[PoseLandmarkType.rightElbow],
          lm[PoseLandmarkType.rightWrist],
        );
      case PoseType.generic:
        return _angle(
          lm[PoseLandmarkType.rightShoulder],
          lm[PoseLandmarkType.rightHip],
          lm[PoseLandmarkType.rightKnee],
        );
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
              child:
                  const Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ),
        ),
        // Workout info card
        Positioned(
          top: 12,
          left: 56,
          right: 16,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
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
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Step into frame',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 14),
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
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            color: Colors.white70, fontSize: 13),
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
                style:
                    const TextStyle(color: Colors.white60, fontSize: 18),
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
                      AppColors.primaryLemonDark),
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
                style:
                    const TextStyle(color: Colors.white54, fontSize: 14),
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
    final totalReps =
        plan.exercises.fold(0, (s, e) => s + e.targetReps * e.sets);
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
                                color: Colors.white70, fontSize: 14),
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
                        borderRadius: BorderRadius.circular(18)),
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
          child: CircularProgressIndicator(
            color: AppColors.primaryLemonDark,
          ),
        ),
      );
    }
    final previewSize = _cameraController!.value.previewSize;
    if (previewSize == null) {
      return Container(color: Colors.black);
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }
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
