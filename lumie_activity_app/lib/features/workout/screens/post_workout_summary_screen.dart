import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';
import '../providers/active_session_provider.dart';
import '../widgets/body_map_widget.dart';

/// Post-workout summary screen showing stats, PRs, body map,
/// overload advice, session notes, and editable set entries.
class PostWorkoutSummaryScreen extends StatefulWidget {
  const PostWorkoutSummaryScreen({super.key});

  @override
  State<PostWorkoutSummaryScreen> createState() =>
      _PostWorkoutSummaryScreenState();
}

class _PostWorkoutSummaryScreenState extends State<PostWorkoutSummaryScreen>
    with SingleTickerProviderStateMixin {
  bool _saving = false;
  bool _saved = false;
  final _notesController = TextEditingController();
  late AnimationController _prAnimController;

  @override
  void initState() {
    super.initState();
    _prAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    _prAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ActiveSessionProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Workout Complete',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero stats
            _StatsCard(
              duration: session.formattedDuration,
              totalSets: session.totalSetsCompleted,
              totalReps: session.totalRepsCompleted,
              totalVolume: session.totalVolume,
            ),
            const SizedBox(height: 16),

            // PR celebration banner (shown after save detects PRs)
            if (session.sessionPRs.isNotEmpty) ...[
              _PRBanner(prs: session.sessionPRs),
              const SizedBox(height: 16),
            ],

            // Body map
            _SectionTitle('Muscles Worked'),
            const SizedBox(height: 8),
            BodyMapWidget(exercises: session.completedExercises),
            const SizedBox(height: 20),

            // Exercise breakdown
            _SectionTitle('Exercise Breakdown'),
            const SizedBox(height: 8),
            ...session.completedExercises.asMap().entries.map((entry) {
              return _ExerciseBreakdownCard(
                exerciseIndex: entry.key,
                exercise: entry.value,
                onEditSet: (setIdx, reps, weight, status) {
                  session.updateSet(
                    entry.key,
                    setIdx,
                    actualReps: reps,
                    actualWeight: weight,
                    status: status,
                  );
                },
              );
            }),

            // Overload advice (shown after save if available)
            if (session.overloadSuggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionTitle('Progressive Overload'),
              const SizedBox(height: 8),
              ...session.overloadSuggestions.map((s) => _OverloadCard(
                    suggestion: s,
                  )),
            ],

            // Session notes
            const SizedBox(height: 20),
            _SectionTitle('Session Notes'),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              onChanged: session.setSessionNotes,
              decoration: InputDecoration(
                hintText: 'How did the workout feel? Any adjustments needed?',
                hintStyle: TextStyle(
                    color: AppColors.textLight, fontSize: 13),
                filled: true,
                fillColor: AppColors.backgroundLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _saving || _saved ? null : _saveAndClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLemon,
              foregroundColor: AppColors.textOnYellow,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _saved
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check, size: 20),
                          SizedBox(width: 8),
                          Text('Saved!',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      )
                    : const Text('Save & Close',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  Future<void> _saveAndClose() async {
    setState(() => _saving = true);
    final session = context.read<ActiveSessionProvider>();
    final result = await session.saveSession();
    if (result != null && session.sessionPRs.isNotEmpty) {
      _prAnimController.forward();
    }
    setState(() {
      _saving = false;
      _saved = true;
    });
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }
}

// ── Stats Card ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final String duration;
  final int totalSets;
  final int totalReps;
  final double totalVolume;

  const _StatsCard({
    required this.duration,
    required this.totalSets,
    required this.totalReps,
    required this.totalVolume,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.warmGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(label: 'Duration', value: duration),
          _StatItem(label: 'Sets', value: '$totalSets'),
          _StatItem(label: 'Reps', value: '$totalReps'),
          _StatItem(
            label: 'Volume',
            value: totalVolume >= 1000
                ? '${(totalVolume / 1000).toStringAsFixed(1)}k'
                : totalVolume.toStringAsFixed(0),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textOnYellow,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textOnYellow.withAlpha(180),
          ),
        ),
      ],
    );
  }
}

// ── PR Celebration Banner ─────────────────────────────────────────────────────

class _PRBanner extends StatelessWidget {
  final List<Map<String, dynamic>> prs;

  const _PRBanner({required this.prs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFBBF24).withAlpha(60),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🏆', style: TextStyle(fontSize: 24)),
              SizedBox(width: 8),
              Text(
                'Personal Records!',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF78350F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...prs.map((pr) {
            final exerciseName =
                (pr['exercise_name'] as String?) ?? 'Unknown';
            final prType = (pr['pr_type'] as String?) ?? '';
            final value = (pr['value'] as num?)?.toDouble() ?? 0;
            final previous =
                (pr['previous_value'] as num?)?.toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Text('⭐ ',
                      style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      '$exerciseName — ${_prLabel(prType, value)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF78350F),
                      ),
                    ),
                  ),
                  if (previous != null)
                    Text(
                      '(was ${previous.toStringAsFixed(0)})',
                      style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFF78350F).withAlpha(150),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static String _prLabel(String type, double value) {
    switch (type) {
      case 'max_weight':
        return '${value.toStringAsFixed(0)} lbs (Weight)';
      case 'max_reps':
        return '${value.toStringAsFixed(0)} reps (Reps)';
      case 'max_volume':
        return '${value.toStringAsFixed(0)} lbs (Volume)';
      default:
        return value.toStringAsFixed(0);
    }
  }
}

// ── Overload Advice Card ──────────────────────────────────────────────────────

class _OverloadCard extends StatelessWidget {
  final OverloadSuggestion suggestion;

  const _OverloadCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final isWeight = suggestion.suggestionType == 'increase_weight';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWeight
              ? Colors.green.shade200
              : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isWeight
                  ? Colors.green.shade50
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isWeight ? Icons.trending_up : Icons.repeat,
              size: 18,
              color: isWeight
                  ? Colors.green.shade700
                  : Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.exerciseName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  suggestion.reasoning,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                '${suggestion.currentValue.toStringAsFixed(0)} →',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textLight),
              ),
              Text(
                suggestion.suggestedValue.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isWeight
                      ? Colors.green.shade700
                      : Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary));
  }
}

// ── Exercise breakdown card ───────────────────────────────────────────────────

class _ExerciseBreakdownCard extends StatelessWidget {
  final int exerciseIndex;
  final CompletedExercise exercise;
  final void Function(
          int setIdx, int reps, double? weight, SetCompletionStatus? status)
      onEditSet;

  const _ExerciseBreakdownCard({
    required this.exerciseIndex,
    required this.exercise,
    required this.onEditSet,
  });

  @override
  Widget build(BuildContext context) {
    final hasAnyPR = exercise.sets.any((s) => s.isPr);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasAnyPR
            ? const Color(0xFFFFFBEB)
            : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: hasAnyPR
            ? Border.all(color: Colors.amber.shade300, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasAnyPR)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('🏆', style: TextStyle(fontSize: 14)),
                ),
              Expanded(
                child: Text(
                  exercise.exerciseName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${exercise.totalVolume.toStringAsFixed(0)} lbs',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Set rows
          ...exercise.sets.asMap().entries.map((entry) {
            final s = entry.value;
            final isPr = s.isPr || s.status == SetCompletionStatus.pr;
            final isFailed = s.status == SetCompletionStatus.failed;
            final isSkipped = s.status == SetCompletionStatus.skipped;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onTap: isSkipped
                    ? null
                    : () => _showEditDialog(context, entry.key, s),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${entry.key + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isPr)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withAlpha(50),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('PR',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.amber)),
                      ),
                    Expanded(
                      child: Text(
                        isSkipped
                            ? 'Skipped'
                            : s.actualWeight != null && s.actualWeight! > 0
                                ? '${s.actualWeight!.toStringAsFixed(0)} lbs x ${s.actualReps}'
                                : '${s.actualReps} reps',
                        style: TextStyle(
                          fontSize: 13,
                          color: isSkipped
                              ? AppColors.textLight
                              : isFailed
                                  ? Colors.red.shade400
                                  : AppColors.textPrimary,
                          decoration: isFailed
                              ? TextDecoration.lineThrough
                              : null,
                          fontStyle: isSkipped
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ),
                    if (s.notes != null && s.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.sticky_note_2_outlined,
                            size: 14, color: AppColors.textLight),
                      ),
                    Icon(
                      isSkipped
                          ? Icons.remove
                          : isFailed
                              ? Icons.close
                              : Icons.check,
                      size: 16,
                      color: isSkipped
                          ? AppColors.textLight
                          : isFailed
                              ? Colors.red.shade400
                              : Colors.green,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, int setIdx, CompletedSet set) {
    final repsController =
        TextEditingController(text: set.actualReps.toString());
    final weightController = TextEditingController(
        text: set.actualWeight?.toStringAsFixed(0) ?? '');
    var selectedStatus = set.status;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit Set ${setIdx + 1}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Weight (lbs)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: repsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Reps'),
              ),
              const SizedBox(height: 12),
              // Status selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatusChip(
                    label: 'Done',
                    icon: Icons.check,
                    color: Colors.green,
                    selected:
                        selectedStatus == SetCompletionStatus.completed,
                    onTap: () => setDialogState(() =>
                        selectedStatus = SetCompletionStatus.completed),
                  ),
                  _StatusChip(
                    label: 'Failed',
                    icon: Icons.close,
                    color: Colors.red,
                    selected:
                        selectedStatus == SetCompletionStatus.failed,
                    onTap: () => setDialogState(() =>
                        selectedStatus = SetCompletionStatus.failed),
                  ),
                  _StatusChip(
                    label: 'PR',
                    icon: Icons.emoji_events,
                    color: Colors.amber,
                    selected: selectedStatus == SetCompletionStatus.pr,
                    onTap: () => setDialogState(
                        () => selectedStatus = SetCompletionStatus.pr),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                onEditSet(
                  setIdx,
                  int.tryParse(repsController.text) ?? set.actualReps,
                  double.tryParse(weightController.text),
                  selectedStatus,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status chip for edit dialog ───────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : AppColors.surfaceLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? color : AppColors.textLight),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
