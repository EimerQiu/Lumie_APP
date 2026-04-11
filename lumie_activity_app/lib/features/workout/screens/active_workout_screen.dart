import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Shows a goal-setting prompt before starting, then routes exercises to
/// either camera-based detection or manual logging based on equipment type
/// and pose type. Handles supersets, circuits, rest timers, set review,
/// early exit, and the overall session flow.
class ActiveWorkoutScreen extends StatefulWidget {
  final WorkoutTemplate template;

  const ActiveWorkoutScreen({super.key, required this.template});

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

/// Holds pending camera-set data waiting for user review before committing.
class _PendingSetReview {
  int reps;
  double? weight;
  final SetCompletionStatus status;
  final String exerciseName;
  final int setNumber;
  final int totalSets;
  final String weightUnit;

  _PendingSetReview({
    required this.reps,
    required this.weight,
    required this.status,
    required this.exerciseName,
    required this.setNumber,
    required this.totalSets,
    required this.weightUnit,
  });
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  bool _navigatedToSummary = false;
  bool _goalPromptShown = false;

  // Pending set review (camera sets only)
  _PendingSetReview? _pendingReview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showGoalPrompt();
    });
  }

  void _showGoalPrompt() {
    if (_goalPromptShown) return;
    _goalPromptShown = true;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SessionGoalSheet(
        onGoalSelected: (goal) {
          Navigator.pop(ctx);
          final session = context.read<ActiveSessionProvider>();
          if (goal != null) session.setSessionGoal(goal);
          session.startSession(widget.template);
        },
      ),
    );
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
              // Session header with timers, goal, and end button
              SessionHeader(
                workoutName: widget.template.name,
                blockName: session.currentBlockName,
                elapsedSeconds: session.elapsedSeconds,
                isResting: session.isResting,
                restSecondsRemaining: session.restSecondsRemaining,
                sessionGoal: session.sessionGoal,
                onEndWorkout: () => _confirmExit(context, session),
              ),
              // Main content area
              Expanded(
                child: _pendingReview != null
                    ? _buildSetReview(session)
                    : session.isResting
                        ? RestTimerWidget(
                            secondsRemaining: session.restSecondsRemaining,
                            totalRestDuration: session.currentRestDuration,
                            timerExpired: session.restTimerExpired,
                            onSkip: session.skipRest,
                            onAdjust: session.adjustRestTime,
                            nextExerciseName:
                                session.currentTemplateExercise
                                        ?.exerciseName ??
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
        weightUnitLabel: session.weightUnit,
        onSetComplete: (reps, weight, status) {
          // Don't commit yet — show review screen first
          setState(() {
            _pendingReview = _PendingSetReview(
              reps: reps,
              weight: weight,
              status: status,
              exerciseName: exercise.exerciseName,
              setNumber: session.currentSetIndex + 1,
              totalSets: session.currentTotalSets,
              weightUnit: session.weightUnit,
            );
          });
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
      weightUnitLabel: session.weightUnit,
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

  // ── Set Review Screen (camera sets) ──────────────────────────────────────

  Widget _buildSetReview(ActiveSessionProvider session) {
    final review = _pendingReview!;
    final repsController =
        TextEditingController(text: review.reps.toString());
    final weightController = TextEditingController(
        text: review.weight?.toStringAsFixed(0) ?? '');

    return StatefulBuilder(
      builder: (context, setReviewState) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Checkmark badge
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryLemon.withAlpha(30),
              ),
              child: const Icon(Icons.check,
                  color: AppColors.primaryLemon, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'Set ${review.setNumber} of ${review.totalSets} Complete',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              review.exerciseName,
              style: TextStyle(
                color: Colors.white.withAlpha(160),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 32),
            // Editable reps
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 130,
                  child: Column(
                    children: [
                      Text(
                        'Reps detected',
                        style: TextStyle(
                          color: Colors.white.withAlpha(120),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: repsController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white.withAlpha(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withAlpha(30)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withAlpha(30)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.primaryLemon),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 130,
                  child: Column(
                    children: [
                      Text(
                        'Weight (${review.weightUnit})',
                        style: TextStyle(
                          color: Colors.white.withAlpha(120),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: weightController,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.]')),
                        ],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                        onTapOutside: (_) {
                          if (weightController.text.trim().isEmpty) {
                            weightController.text = '0';
                          }
                          FocusScope.of(context).unfocus();
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white.withAlpha(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withAlpha(30)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withAlpha(30)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: AppColors.primaryLemon),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            // Confirm button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  final reps =
                      int.tryParse(repsController.text) ?? review.reps;
                  final weight = double.tryParse(weightController.text);
                  session.completeSet(
                    actualReps: reps,
                    actualWeight: weight,
                    status: review.status,
                    wasCameraTracked: true,
                  );
                  setState(() => _pendingReview = null);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLemon,
                  foregroundColor: AppColors.textOnYellow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Confirm & Continue',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
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
            child: const Text('Save & Exit',
                style: TextStyle(color: AppColors.textOnYellow)),
          ),
        ],
      ),
    );
  }
}

// ── Session Goal Selection Sheet ─────────────────────────────────────────────

class _SessionGoalSheet extends StatefulWidget {
  final void Function(String? goal) onGoalSelected;

  const _SessionGoalSheet({required this.onGoalSelected});

  @override
  State<_SessionGoalSheet> createState() => _SessionGoalSheetState();
}

class _SessionGoalSheetState extends State<_SessionGoalSheet> {
  bool _showCustomInput = false;
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "What's your goal for today's session?",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Quick-select options
          _GoalOption(
            emoji: '\u{1F3C6}',
            label: 'Hit a PR',
            onTap: () => widget.onGoalSelected('Hit a PR'),
          ),
          const SizedBox(height: 10),
          _GoalOption(
            emoji: '\u{1F4AA}',
            label: 'Normal Training',
            onTap: () => widget.onGoalSelected('Normal Training'),
          ),
          const SizedBox(height: 10),
          _GoalOption(
            emoji: '\u{1F504}',
            label: 'Deload / Light Session',
            onTap: () => widget.onGoalSelected('Deload / Light Session'),
          ),
          const SizedBox(height: 10),
          if (_showCustomInput) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Type your goal...',
                      hintStyle:
                          TextStyle(color: Colors.white.withAlpha(80)),
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
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.primaryLemon),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (v) {
                      final goal = v.trim();
                      widget
                          .onGoalSelected(goal.isNotEmpty ? goal : null);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final goal = _customController.text.trim();
                    widget.onGoalSelected(goal.isNotEmpty ? goal : null);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLemon,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.check,
                        color: AppColors.textOnYellow),
                  ),
                ),
              ],
            ),
          ] else
            _GoalOption(
              emoji: '\u{1F3AF}',
              label: 'Custom',
              onTap: () => setState(() => _showCustomInput = true),
            ),
          const SizedBox(height: 16),
          // Skip button
          TextButton(
            onPressed: () => widget.onGoalSelected(null),
            child: Text(
              'Skip',
              style: TextStyle(
                  color: Colors.white.withAlpha(150), fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalOption extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _GoalOption({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withAlpha(20)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
