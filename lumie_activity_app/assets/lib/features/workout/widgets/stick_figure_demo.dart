import 'package:flutter/material.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../data/exercise_keyframes.dart';
import 'stick_figure_painter.dart';
import 'muscle_highlight_widget.dart';

/// Full-screen stick figure demo shown before each set.
///
/// Plays 3 loops of the primary-view animation, then calls [onComplete].
/// Shows exercise name, muscle highlights, and a beginner form cue.
/// User can skip with "Skip Demo" and swipe between primary/secondary views.
class FullScreenDemoWidget extends StatefulWidget {
  final PoseType poseType;
  final String exerciseName;
  final VoidCallback onComplete;

  const FullScreenDemoWidget({
    super.key,
    required this.poseType,
    required this.exerciseName,
    required this.onComplete,
  });

  @override
  State<FullScreenDemoWidget> createState() => _FullScreenDemoWidgetState();
}

class _FullScreenDemoWidgetState extends State<FullScreenDemoWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _loopCount = 0;
  int _viewIndex = 0; // 0 = primary, 1 = secondary

  ExerciseDemo? get _demo => getDemoForPoseType(widget.poseType);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _controller.addStatusListener(_onAnimStatus);
    _controller.forward();
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _loopCount++;
      if (_loopCount >= 3) {
        widget.onComplete();
      } else {
        _controller.reset();
        _controller.forward();
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final demo = _demo;
    if (demo == null) {
      // No demo for this exercise — skip immediately
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onComplete());
      return const SizedBox.shrink();
    }

    final hasSecondary = demo.secondaryView != null;

    return Container(
      color: const Color(0xFF0D0D1A),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar: exercise name + loop counter
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.exerciseName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Demo ${_loopCount + 1}/3',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // View label tabs (swipeable)
            if (hasSecondary)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ViewTab(
                      label: '${demo.primaryView == 'side' ? 'Side' : 'Front'} View',
                      active: _viewIndex == 0,
                      onTap: () => setState(() => _viewIndex = 0),
                    ),
                    const SizedBox(width: 12),
                    _ViewTab(
                      label: '${demo.secondaryView == 'side' ? 'Side' : 'Front'} View',
                      active: _viewIndex == 1,
                      onTap: () => setState(() => _viewIndex = 1),
                    ),
                  ],
                ),
              ),

            // Stick figure animation
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: hasSecondary
                    ? (d) {
                        if (d.primaryVelocity != null) {
                          if (d.primaryVelocity! < -200 && _viewIndex == 0) {
                            setState(() => _viewIndex = 1);
                          } else if (d.primaryVelocity! > 200 &&
                              _viewIndex == 1) {
                            setState(() => _viewIndex = 0);
                          }
                        }
                      }
                    : null,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (_, _) {
                    final pose = _currentPose(demo);
                    return Center(
                      child: CustomPaint(
                        size: const Size(260, 360),
                        painter: StickFigurePainter(
                          pose: pose,
                          equipmentProp: demo.equipmentProp,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Muscle highlights
            MuscleHighlightWidget(
              primaryMuscles: demo.primaryMuscles,
              secondaryMuscles: demo.secondaryMuscles,
            ),

            // Form cue
            if (demo.formCue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text(
                  demo.formCue,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withAlpha(180),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            // Skip button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: TextButton(
                onPressed: widget.onComplete,
                child: Text(
                  'Skip Demo',
                  style: TextStyle(
                      color: Colors.white.withAlpha(120), fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, Offset> _currentPose(ExerciseDemo demo) {
    // Map t: 0→0.5 descend, 0.5→1.0 ascend
    final t = _controller.value;
    final raw = t <= 0.5 ? t / 0.5 : (1.0 - t) / 0.5;
    final phase = Curves.easeInOut.transform(raw);
    return lerpPose(demo.start, demo.end, phase);
  }
}

// ── Mini PiP demo (during active set) ─────────────────────────────────────────

/// Small looping stick figure animation in the corner during active sets.
/// Tap to expand to a larger overlay, tap again to shrink.
class MiniPipDemo extends StatefulWidget {
  final PoseType poseType;

  const MiniPipDemo({super.key, required this.poseType});

  @override
  State<MiniPipDemo> createState() => _MiniPipDemoState();
}

class _MiniPipDemoState extends State<MiniPipDemo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _expanded = false;

  ExerciseDemo? get _demo => getDemoForPoseType(widget.poseType);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final demo = _demo;
    if (demo == null) return const SizedBox.shrink();

    if (_expanded) {
      return _buildExpanded(demo);
    }
    return _buildMini(demo);
  }

  Widget _buildMini(ExerciseDemo demo) {
    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        onTap: () => setState(() => _expanded = true),
        child: Container(
          width: 88,
          height: 118,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withAlpha(30)),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, _) {
              final pose = _currentPose(demo);
              return CustomPaint(
                painter: StickFigurePainter(
                  pose: pose,
                  equipmentProp: demo.equipmentProp,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(ExerciseDemo demo) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _expanded = false),
        child: Container(
          color: Colors.black.withAlpha(200),
          child: Center(
            child: Container(
              width: 260,
              height: 380,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // View label
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${demo.primaryView == 'side' ? 'Side' : 'Front'} View',
                      style: TextStyle(
                        color: Colors.white.withAlpha(150),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, _) {
                        final pose = _currentPose(demo);
                        return CustomPaint(
                          size: const Size(220, 300),
                          painter: StickFigurePainter(
                            pose: pose,
                            equipmentProp: demo.equipmentProp,
                          ),
                        );
                      },
                    ),
                  ),
                  // Muscle info
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: MuscleHighlightWidget(
                      primaryMuscles: demo.primaryMuscles,
                      secondaryMuscles: demo.secondaryMuscles,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, Offset> _currentPose(ExerciseDemo demo) {
    final t = _controller.value;
    final raw = t <= 0.5 ? t / 0.5 : (1.0 - t) / 0.5;
    final phase = Curves.easeInOut.transform(raw);
    return lerpPose(demo.start, demo.end, phase);
  }
}

// ── Machine demo stub ─────────────────────────────────────────────────────────

/// Stub widget for machine exercises. Returns empty — ready for future
/// implementation without refactoring the surrounding session screen.
class MachineDemo extends StatelessWidget {
  const MachineDemo({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ── View tab ──────────────────────────────────────────────────────────────────

class _ViewTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ViewTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? Colors.white.withAlpha(60) : Colors.white.withAlpha(15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white.withAlpha(100),
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
