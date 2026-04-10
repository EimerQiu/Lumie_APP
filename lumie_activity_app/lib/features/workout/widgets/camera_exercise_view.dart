import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../data/exercise_keyframes.dart';
import 'stick_figure_demo.dart';

/// Camera-based exercise view with ML Kit pose detection, automatic rep
/// counting, orientation guidance, and a stick-figure demo mini PiP.
///
/// Flow: Full-screen demo (3 loops) → Active set with camera + mini PiP.
/// Demo plays on first render and resets when setIndex or exercise changes.
class CameraExerciseView extends StatefulWidget {
  final TemplateExercise exercise;
  final int setIndex;
  final int totalSets;
  final double? prefilledWeight;
  final void Function(int reps, double? weight, SetCompletionStatus status)
      onSetComplete;
  final VoidCallback onSkipDetection;

  const CameraExerciseView({
    super.key,
    required this.exercise,
    required this.setIndex,
    required this.totalSets,
    this.prefilledWeight,
    required this.onSetComplete,
    required this.onSkipDetection,
  });

  @override
  State<CameraExerciseView> createState() => _CameraExerciseViewState();
}

class _CameraExerciseViewState extends State<CameraExerciseView> {
  // Camera
  CameraController? _cameraController;
  bool _cameraInitialized = false;

  // Pose detection
  PoseDetector? _poseDetector;
  bool _isProcessingFrame = false;

  // Rep counting
  int _repCount = 0;
  bool _repDown = false;
  DateTime? _repStartTime;
  static const _minRepMillis = 1000;

  // Form feedback
  String _formFeedback = '';
  bool _formGood = true;

  // Weight
  double? _weight;
  late TextEditingController _weightController;

  // Demo phase: true = showing full-screen demo, false = active set with camera
  bool _showingDemo = true;

  // Orientation banner
  bool _showOrientationBanner = true;
  Timer? _bannerTimer;

  // Thresholds for each PoseType: (downAngle, upAngle)
  static const _thresholds = <PoseType, (double, double)>{
    PoseType.squat: (100.0, 155.0),
    PoseType.lunge: (100.0, 155.0),
    PoseType.curl: (50.0, 150.0),
    PoseType.pushup: (90.0, 155.0),
    PoseType.shoulderPress: (90.0, 160.0),
    PoseType.lateralRaise: (100.0, 155.0),
    PoseType.rdl: (70.0, 160.0),
    PoseType.backSquat: (100.0, 155.0),
    PoseType.benchPress: (90.0, 155.0),
    PoseType.deadlift: (80.0, 160.0),
    PoseType.barbellRow: (90.0, 155.0),
    PoseType.generic: (100.0, 150.0),
  };

  @override
  void initState() {
    super.initState();
    final w = widget.prefilledWeight ?? widget.exercise.defaultWeight;
    _weightController = TextEditingController(
      text: w?.toStringAsFixed(0) ?? '',
    );
    _weight = w;
    _showingDemo = getDemoForPoseType(widget.exercise.poseType) != null;
    // Camera init is deferred until demo completes (or if no demo)
    if (!_showingDemo) {
      _initCamera();
    }
    _initPoseDetector();
  }

  @override
  void didUpdateWidget(CameraExerciseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setIndex != widget.setIndex ||
        oldWidget.exercise.exerciseId != widget.exercise.exerciseId) {
      _repCount = 0;
      _repDown = false;
      _formFeedback = '';
      final w = widget.prefilledWeight ?? widget.exercise.defaultWeight;
      if (w != null) {
        _weightController.text = w.toStringAsFixed(0);
        _weight = w;
      }
      // Reset to demo phase for new set / new exercise
      final hasDemo = getDemoForPoseType(widget.exercise.poseType) != null;
      setState(() {
        _showingDemo = hasDemo;
        _showOrientationBanner = true;
      });
    }
  }

  void _onDemoComplete() {
    setState(() => _showingDemo = false);
    _showOrientationBanner = true;
    _startBannerTimer();
    // Start camera now if not already initialized
    if (!_cameraInitialized) {
      _initCamera();
    }
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showOrientationBanner = false);
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        frontCam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _cameraInitialized = true);
      _cameraController!.startImageStream(_processFrame);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  void _initPoseDetector() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(model: PoseDetectionModel.base),
    );
  }

  void _processFrame(CameraImage image) {
    if (_isProcessingFrame || _poseDetector == null) return;
    _isProcessingFrame = true;

    final inputImage = _convertCameraImage(image);
    if (inputImage == null) {
      _isProcessingFrame = false;
      return;
    }

    _poseDetector!.processImage(inputImage).then((poses) {
      if (!mounted) return;
      if (poses.isNotEmpty) {
        // Use closest person (largest bounding box)
        final pose = _closestPose(poses);
        _detectRep(pose);
      }
      _isProcessingFrame = false;
    }).catchError((_) {
      _isProcessingFrame = false;
    });
  }

  InputImage? _convertCameraImage(CameraImage image) {
    final camera = _cameraController?.description;
    if (camera == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    if (rotation == null) return null;

    final format = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Pose _closestPose(List<Pose> poses) {
    if (poses.length == 1) return poses.first;
    Pose best = poses.first;
    double bestArea = 0;
    for (final p in poses) {
      final lm = p.landmarks;
      final xs = lm.values.map((l) => l.x);
      final ys = lm.values.map((l) => l.y);
      final area = (xs.reduce(math.max) - xs.reduce(math.min)) *
          (ys.reduce(math.max) - ys.reduce(math.min));
      if (area > bestArea) {
        bestArea = area;
        best = p;
      }
    }
    return best;
  }

  void _detectRep(Pose pose) {
    final pt = widget.exercise.poseType;
    if (pt == null) return;

    final angle = _exerciseAngle(pose, pt);
    if (angle == null) {
      if (mounted) {
        setState(() {
          _formFeedback = 'Make sure your body is visible';
          _formGood = false;
        });
      }
      return;
    }

    final thresh = _thresholds[pt];
    if (thresh == null) return;

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
        if (mounted) {
          setState(() {
            _repCount++;
            _formFeedback = 'Good rep!';
            _formGood = true;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _formFeedback = angle < thresh.$1
              ? 'Good range of motion'
              : 'Good form';
          _formGood = true;
        });
      }
    }
  }

  double? _exerciseAngle(Pose pose, PoseType type) {
    final lm = pose.landmarks;
    switch (type) {
      case PoseType.curl:
      case PoseType.shoulderPress:
      case PoseType.benchPress:
      case PoseType.barbellRow:
        return _angle(
          lm[PoseLandmarkType.rightShoulder],
          lm[PoseLandmarkType.rightElbow],
          lm[PoseLandmarkType.rightWrist],
        );
      case PoseType.rdl:
      case PoseType.deadlift:
      case PoseType.generic:
        return _angle(
          lm[PoseLandmarkType.rightShoulder],
          lm[PoseLandmarkType.rightHip],
          lm[PoseLandmarkType.rightKnee],
        );
      case PoseType.squat:
      case PoseType.backSquat:
        return _angle(
          lm[PoseLandmarkType.rightHip],
          lm[PoseLandmarkType.rightKnee],
          lm[PoseLandmarkType.rightAnkle],
        );
      case PoseType.pushup:
        return _angle(
          lm[PoseLandmarkType.leftShoulder],
          lm[PoseLandmarkType.leftElbow],
          lm[PoseLandmarkType.leftWrist],
        );
      case PoseType.lunge:
        return _angle(
          lm[PoseLandmarkType.rightHip],
          lm[PoseLandmarkType.rightKnee],
          lm[PoseLandmarkType.rightAnkle],
        );
      case PoseType.lateralRaise:
        return _angle(
          lm[PoseLandmarkType.rightHip],
          lm[PoseLandmarkType.rightShoulder],
          lm[PoseLandmarkType.rightWrist],
        );
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
    final cross = abX * cbY - abY * cbX;
    final radians = math.atan2(cross.abs(), dot);
    return radians * 180 / math.pi;
  }

  String get _orientationText {
    final pt = widget.exercise.poseType;
    if (pt == null) return '';
    final demo = getDemoForPoseType(pt);
    final orient = demo?.primaryView ?? 'front';
    return orient == 'side'
        ? 'Place your phone to the SIDE for this exercise'
        : 'Face the camera DIRECTLY for this exercise';
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    _poseDetector?.close();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Demo phase: full-screen 3-loop stick figure demo ───────────────────
    if (_showingDemo && widget.exercise.poseType != null) {
      return FullScreenDemoWidget(
        poseType: widget.exercise.poseType!,
        exerciseName: widget.exercise.exerciseName,
        onComplete: _onDemoComplete,
      );
    }

    // ── Active set phase: camera + rep counting + mini PiP ────────────────
    return Stack(
      children: [
        // Camera preview
        if (_cameraInitialized && _cameraController != null)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize?.height ?? 1,
                height: _cameraController!.value.previewSize?.width ?? 1,
                child: CameraPreview(_cameraController!),
              ),
            ),
          )
        else
          Container(color: const Color(0xFF0D0D1A)),

        // Dark overlay for readability
        Positioned.fill(
          child: Container(color: Colors.black.withAlpha(100)),
        ),

        // Content overlay
        SafeArea(
          child: Column(
            children: [
              // Orientation banner
              if (_showOrientationBanner)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: AppColors.primaryLemon.withAlpha(220),
                  child: Row(
                    children: [
                      const Text('📷 ', style: TextStyle(fontSize: 16)),
                      Expanded(
                        child: Text(
                          _orientationText,
                          style: const TextStyle(
                            color: AppColors.textOnYellow,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              // Exercise info
              Text(
                widget.exercise.exerciseName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Set ${widget.setIndex + 1} of ${widget.totalSets}  ·  Target: ${widget.exercise.defaultReps} reps',
                style: TextStyle(
                    color: Colors.white.withAlpha(180), fontSize: 13),
              ),
              const SizedBox(height: 20),
              // Rep counter
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withAlpha(120),
                  border: Border.all(
                    color: AppColors.primaryLemon.withAlpha(180),
                    width: 3,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$_repCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'reps',
                      style: TextStyle(
                        color: Colors.white.withAlpha(150),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Form feedback
              if (_formFeedback.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_formGood ? Colors.green : Colors.orange)
                        .withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formFeedback,
                    style: TextStyle(
                      color: _formGood
                          ? Colors.green.shade300
                          : Colors.orange.shade300,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              // Manual rep correction buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CircleButton(
                    icon: Icons.remove,
                    onTap: () {
                      if (_repCount > 0) setState(() => _repCount--);
                    },
                  ),
                  const SizedBox(width: 24),
                  _CircleButton(
                    icon: Icons.add,
                    onTap: () => setState(() => _repCount++),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Weight input (for free weights)
              if (widget.exercise.equipmentType == 'dumbbell' ||
                  widget.exercise.equipmentType == 'barbell')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: TextField(
                    controller: _weightController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 18),
                    onChanged: (v) => _weight = double.tryParse(v),
                    decoration: InputDecoration(
                      labelText: 'Weight (lbs)',
                      labelStyle: TextStyle(
                          color: Colors.white.withAlpha(120), fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withAlpha(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.white.withAlpha(30)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.white.withAlpha(30)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Complete set button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => widget.onSetComplete(
                      _repCount > 0
                          ? _repCount
                          : widget.exercise.defaultReps,
                      _weight,
                      SetCompletionStatus.completed,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLemon,
                      foregroundColor: AppColors.textOnYellow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Complete Set',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Skip detection
              TextButton(
                onPressed: widget.onSkipDetection,
                child: Text(
                  'Skip Detection',
                  style: TextStyle(
                      color: Colors.white.withAlpha(150), fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),

        // Mini PiP stick figure demo (top-right, during active set)
        if (widget.exercise.poseType != null)
          MiniPipDemo(poseType: widget.exercise.poseType!),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withAlpha(20),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
