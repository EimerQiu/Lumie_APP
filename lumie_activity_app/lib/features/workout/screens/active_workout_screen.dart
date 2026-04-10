import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../providers/active_session_provider.dart';
import '../widgets/camera_exercise_view.dart';
import '../widgets/manual_exercise_view.dart';
import '../widgets/rest_timer_widget.dart';
import '../widgets/session_header.dart';
import 'post_workout_summary_screen.dart';

/// Main active workout session screen.
///
/// Routes exercises to either camera-based detection or manual logging
/// based on equipment type and pose type. Handles supersets, circuits,
/// rest timers, and the overall session flow.
class ActiveWorkoutScreen extends StatefulWidget {
  final WorkoutTemplate template;

  const ActiveWorkoutScreen({super.key, required this.template});

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  bool _navigatedToSummary = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ActiveSessionProvider>().startSession(widget.template);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ActiveSessionProvider>();

    if (session.isComplete && !_navigatedToSummary) {
      _navigatedToSummary = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const PostWorkoutSummaryScreen(),
          ),
        );
      });
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primaryLemon)),
      );
    }

    if (!session.isActive) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primaryLemon)),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit(context, session);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: SafeArea(
          child: Column(
            children: [
              // Session header with timers
              SessionHeader(
                workoutName: widget.template.name,
                blockName: session.currentBlockName,
                elapsedSeconds: session.elapsedSeconds,
                isResting: session.isResting,
                restSecondsRemaining: session.restSecondsRemaining,
              ),
              // Main content area
              Expanded(
                child: session.isResting
                    ? RestTimerWidget(
                        secondsRemaining: session.restSecondsRemaining,
                        totalRestDuration: session.currentRestDuration,
                        onSkip: session.skipRest,
                        onAdjust: session.adjustRestTime,
                        nextExerciseName:
                            session.currentTemplateExercise?.exerciseName ??
                                '',
                        nextSetIndex: session.currentSetIndex + 1,
                        totalSets: session.currentTotalSets,
                      )
                    : _buildExerciseView(session),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseView(ActiveSessionProvider session) {
    final exercise = session.currentTemplateExercise;
    if (exercise == null) return const SizedBox.shrink();

    final useCamera = session.currentUseCamera;
    final prefilledWeight = session.currentPrefilledWeight;

    if (useCamera) {
      return CameraExerciseView(
        exercise: exercise,
        setIndex: session.currentSetIndex,
        totalSets: session.currentTotalSets,
        prefilledWeight: prefilledWeight,
        onSetComplete: (reps, weight, status) {
          session.completeSet(
            actualReps: reps,
            actualWeight: weight,
            status: status,
            wasCameraTracked: true,
          );
        },
        onSkipDetection: () {
          session.toggleDetectionSkip(session.currentExerciseIndex);
        },
      );
    }

    return ManualExerciseView(
      exercise: exercise,
      setIndex: session.currentSetIndex,
      totalSets: session.currentTotalSets,
      prefilledWeight: prefilledWeight,
      onSetComplete: (reps, weight, status, notes) {
        session.completeSet(
          actualReps: reps,
          actualWeight: weight,
          status: status,
          notes: notes,
        );
      },
      onEnableCamera: exercise.poseType != null &&
              exercise.equipmentType != 'machine'
          ? () => session.toggleDetectionSkip(session.currentExerciseIndex)
          : null,
    );
  }

  void _confirmExit(BuildContext context, ActiveSessionProvider session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Workout?'),
        content: const Text(
            'Do you want to save your progress, or discard the workout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Going'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              showDialog(
                context: context,
                builder: (ctx2) => AlertDialog(
                  title: const Text('Discard Workout?'),
                  content: const Text(
                      'All sets logged in this session will be lost.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx2),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx2);
                        session.cancelSession();
                        Navigator.pop(context);
                      },
                      child: const Text('Discard',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
            child: Text('Discard',
                style: TextStyle(color: Colors.red.shade300)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              session.finishEarly();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLemon),
            child: const Text('Finish & Save',
                style: TextStyle(color: AppColors.textOnYellow)),
          ),
        ],
      ),
    );
  }
}
