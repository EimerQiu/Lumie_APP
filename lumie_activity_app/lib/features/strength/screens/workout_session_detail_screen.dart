import 'package:flutter/material.dart';
import '../../../core/services/workout_prefs_service.dart';
import '../../../core/services/workout_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/workout_plan_models.dart';

/// Read-only view of a completed workout session from history.
/// Shows exercise details, attribution (user vs advisor), and
/// per-exercise strength comparison against previous best.
class WorkoutSessionDetailScreen extends StatefulWidget {
  final WorkoutSession session;

  const WorkoutSessionDetailScreen({super.key, required this.session});

  @override
  State<WorkoutSessionDetailScreen> createState() =>
      _WorkoutSessionDetailScreenState();
}

class _WorkoutSessionDetailScreenState
    extends State<WorkoutSessionDetailScreen> {
  final Map<String, Map<String, dynamic>?> _previousBests = {};
  bool _loadingHistory = true;
  String _weightUnit = 'lbs';

  @override
  void initState() {
    super.initState();
    WorkoutPrefsService.getWeightUnit()
        .then((u) { if (mounted) setState(() => _weightUnit = u); });
    _loadPreviousBests();
  }

  Future<void> _loadPreviousBests() async {
    final api = WorkoutApiService();
    for (final ex in widget.session.exercises) {
      if (_previousBests.containsKey(ex.exerciseId)) continue;
      try {
        // Fetch 2 sessions so we can compare against the one before this
        final history = await api.getExerciseHistory(ex.exerciseId, limit: 5);
        // Find the most recent entry that is NOT this session
        Map<String, dynamic>? prev;
        for (final h in history) {
          if ((h['session_id'] as String?) != widget.session.sessionId) {
            prev = h;
            break;
          }
        }
        _previousBests[ex.exerciseId] = prev;
      } catch (_) {
        _previousBests[ex.exerciseId] = null;
      }
    }
    if (mounted) setState(() => _loadingHistory = false);
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final wd = weekdays[(local.weekday - 1) % 7];
    return '$wd, ${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final prCount =
        session.exercises.expand((e) => e.sets).where((s) => s.isPr).length;

    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          session.templateName.isNotEmpty ? session.templateName : 'Workout',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date + attribution
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(session.startedAt),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                _AttributionBadge(session: session),
              ],
            ),
            const SizedBox(height: 16),

            // Stats card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.cardShadow,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatBlock(
                    label: 'Duration',
                    value: _formatDuration(session.durationSeconds),
                  ),
                  _VDivider(),
                  _StatBlock(label: 'Sets', value: '${session.totalSets}'),
                  _VDivider(),
                  _StatBlock(label: 'Reps', value: '${session.totalReps}'),
                  if (prCount > 0) ...[
                    _VDivider(),
                    _StatBlock(label: 'PRs', value: '🏆 $prCount'),
                  ],
                ],
              ),
            ),

            // Advisor attribution panel (for advisor-added workouts)
            if (session.isAdvisorAdded) ...[
              const SizedBox(height: 12),
              _AdvisorAttributionPanel(session: session),
            ],

            // User notes
            if (session.notes != null && session.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _NotesCard(label: 'Notes', text: session.notes!),
            ],

            // Advisor notes (visible to both user and advisor)
            if (session.advisorNotes != null &&
                session.advisorNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _NotesCard(
                label: 'Advisor Notes',
                text: session.advisorNotes!,
                accent: true,
              ),
            ],

            const SizedBox(height: 20),
            const Text(
              'Exercises',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            // Exercise cards with strength comparison
            ...session.exercises.map(
              (ex) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ExerciseCard(
                  exercise: ex,
                  previousSessionData: _previousBests[ex.exerciseId],
                  loadingHistory: _loadingHistory,
                  weightUnit: _weightUnit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attribution widgets ───────────────────────────────────────────────────────

class _AttributionBadge extends StatelessWidget {
  final WorkoutSession session;

  const _AttributionBadge({required this.session});

  @override
  Widget build(BuildContext context) {
    final isAdvisor = session.isAdvisorAdded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAdvisor
            ? const Color(0xFFE0F2FE)
            : AppColors.primaryLemon,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdvisor ? Icons.person_outline : Icons.person,
            size: 13,
            color: isAdvisor
                ? const Color(0xFF0369A1)
                : AppColors.textOnYellow,
          ),
          const SizedBox(width: 4),
          Text(
            isAdvisor ? 'Added by Advisor' : 'Logged by You',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isAdvisor
                  ? const Color(0xFF0369A1)
                  : AppColors.textOnYellow,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvisorAttributionPanel extends StatelessWidget {
  final WorkoutSession session;

  const _AdvisorAttributionPanel({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 18, color: Color(0xFF0369A1)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Your advisor logged this workout on your behalf. '
              'It counts toward your strength progress just like any workout you log yourself.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF0369A1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notes card ────────────────────────────────────────────────────────────────

class _NotesCard extends StatelessWidget {
  final String label;
  final String text;
  final bool accent;

  const _NotesCard({
    required this.label,
    required this.text,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent ? AppColors.primaryLemonLight : AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accent
                  ? AppColors.textOnYellow
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise card with strength comparison ────────────────────────────────────

class _ExerciseCard extends StatelessWidget {
  final CompletedExercise exercise;
  final Map<String, dynamic>? previousSessionData;
  final bool loadingHistory;
  final String weightUnit;

  const _ExerciseCard({
    required this.exercise,
    required this.previousSessionData,
    required this.loadingHistory,
    required this.weightUnit,
  });

  String _equipmentLabel(String e) {
    const map = {
      'bodyweight': 'Bodyweight',
      'dumbbell': 'Dumbbell',
      'barbell': 'Barbell',
      'machine': 'Machine',
      'cable': 'Cable',
      'band': 'Resistance Band',
    };
    return map[e.toLowerCase()] ?? e;
  }

  /// Best set from this exercise session: highest weight × reps volume.
  CompletedSet? get _bestSet {
    final completed = exercise.sets
        .where((s) => s.status != SetCompletionStatus.skipped)
        .toList();
    if (completed.isEmpty) return null;
    return completed.reduce(
        (a, b) => a.volume >= b.volume ? a : b);
  }

  /// Best set from previous session data.
  Map<String, dynamic>? get _previousBestSet {
    final sets =
        (previousSessionData?['sets'] as List<dynamic>?) ?? [];
    if (sets.isEmpty) return null;
    Map<String, dynamic>? best;
    double bestVol = 0;
    for (final s in sets) {
      final w = (s['actual_weight'] as num?)?.toDouble() ?? 0;
      final r = (s['actual_reps'] as num?)?.toInt() ?? 0;
      final vol = w * r;
      if (vol >= bestVol) {
        bestVol = vol;
        best = Map<String, dynamic>.from(s as Map);
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final completedSets = exercise.sets
        .where((s) => s.status != SetCompletionStatus.skipped)
        .toList();
    final best = _bestSet;
    final prevBest = _previousBestSet;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.exerciseName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (exercise.equipmentType.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLemon,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _equipmentLabel(exercise.equipmentType),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textOnYellow,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Sets table header
          const Row(
            children: [
              SizedBox(width: 30),
              Expanded(
                child: Text('Reps',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
              SizedBox(
                width: 80,
                child: Text('Weight',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Sets rows
          ...completedSets.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: s.isPr
                        ? const Text('🏆',
                            style: TextStyle(fontSize: 14))
                        : Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                  ),
                  Expanded(
                    child: Text(
                      '${s.actualReps} reps',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      s.actualWeight != null
                          ? '${s.actualWeight!.toStringAsFixed(s.actualWeight! % 1 == 0 ? 0 : 1)} $weightUnit'
                          : '—',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          if (exercise.sets
              .any((s) => s.status == SetCompletionStatus.skipped)) ...[
            const SizedBox(height: 4),
            Text(
              '${exercise.sets.where((s) => s.status == SetCompletionStatus.skipped).length} set(s) skipped',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textLight),
            ),
          ],

          // Strength comparison
          if (!loadingHistory && best != null && prevBest != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.surfaceLight),
            const SizedBox(height: 10),
            _StrengthComparison(
              exerciseName: exercise.exerciseName,
              currentSet: best,
              previousSet: prevBest,
              weightUnit: weightUnit,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Strength comparison row ───────────────────────────────────────────────────

class _StrengthComparison extends StatelessWidget {
  final String exerciseName;
  final CompletedSet currentSet;
  final Map<String, dynamic> previousSet;
  final String weightUnit;

  const _StrengthComparison({
    required this.exerciseName,
    required this.currentSet,
    required this.previousSet,
    required this.weightUnit,
  });

  String _setLabel(int reps, double? weight) {
    if (weight != null && weight > 0) {
      final w = weight % 1 == 0
          ? weight.toStringAsFixed(0)
          : weight.toStringAsFixed(1);
      return '$w $weightUnit × $reps';
    }
    return '$reps reps';
  }

  @override
  Widget build(BuildContext context) {
    final prevReps = (previousSet['actual_reps'] as num?)?.toInt() ?? 0;
    final prevWeight =
        (previousSet['actual_weight'] as num?)?.toDouble();

    final currentLabel =
        _setLabel(currentSet.actualReps, currentSet.actualWeight);
    final previousLabel = _setLabel(prevReps, prevWeight);

    final improved = currentSet.volume >
        (prevWeight ?? 0) * prevReps;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          improved ? Icons.trending_up : Icons.trending_flat,
          size: 16,
          color: improved
              ? const Color(0xFF16A34A)
              : AppColors.textLight,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Previous: $previousLabel',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                'Current: $currentLabel',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: improved
                      ? const Color(0xFF16A34A)
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Stat helpers ──────────────────────────────────────────────────────────────

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;

  const _StatBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textOnYellow,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textOnYellow.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.textOnYellow.withValues(alpha: 0.2),
    );
  }
}
