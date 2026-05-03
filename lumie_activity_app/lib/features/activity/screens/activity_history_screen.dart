import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rest_days_service.dart';
import '../../../core/services/sleep_service.dart';
import '../../../core/services/steps_service.dart';
import '../../../shared/models/rest_days_models.dart';
import '../../../shared/models/sleep_models.dart';
import '../../../shared/models/user_models.dart';
import '../../settings/providers/activity_goal_provider.dart';
import '../providers/today_steps_provider.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../ring/providers/ring_provider.dart';
import '../widgets/activity_picker_sheet.dart';
import 'workout_recording_screen.dart';
import 'workout_session_screen.dart';

// Contributor-card thresholds. Tuned for our teen population — kept here so the
// classifiers below can stay literal.
const int _kSessionMinutesThreshold = 30; // ≥30 active min → counts as a "session"
const int _kWeeklyFrequencyTarget = 3;    // soft target: 3 sessions / week
const int _kWeeklyVolumeTarget = 150;     // soft target: 150 active min / week

// ─── Internal view model ──────────────────────────────────────────────────────

class _DayData {
  final DateTime date;
  final int steps;
  final int activeMinutes; // from ring exercise_time_seconds
  final int goalMinutes;
  final int goalSteps;
  final String goalReason;
  final bool goalIsReduced;

  const _DayData({
    required this.date,
    required this.steps,
    required this.activeMinutes,
    required this.goalMinutes,
    required this.goalSteps,
    required this.goalReason,
    required this.goalIsReduced,
  });

  bool goalMet(ActivityGoalType type) => type == ActivityGoalType.steps
      ? steps >= goalSteps
      : activeMinutes >= goalMinutes;

  double goalProgress(ActivityGoalType type) {
    if (type == ActivityGoalType.steps) {
      return goalSteps > 0 ? (steps / goalSteps).clamp(0.0, 1.5) : 0.0;
    }
    return goalMinutes > 0 ? (activeMinutes / goalMinutes).clamp(0.0, 1.5) : 0.0;
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({super.key});

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  int _selectedDayIndex = 0; // 0 = today, 6 = 6 days ago
  bool _isTodayRestDay = false;
  bool _isLoading = true;
  List<_DayData> _weekData = [];

  /// Resolved rest-day schedule. Drives the Recovery Time card's 7-day icon row
  /// — without this, recurring weekly rest days would always render as "active".
  RestDaySettings? _restDays;

  /// Sleep quality score per night, keyed by the local-date string the user
  /// woke up on (yyyy-MM-dd). Feeds the combined Recovery Time logic — rest +
  /// sleep — so a poor night reduces a rest day's recovery credit.
  Map<String, int> _sleepScoreByDate = const {};

  RingProvider? _ringProvider;
  bool _lastConnected = false;

  TodayStepsProvider? _stepsProvider;

  @override
  void initState() {
    super.initState();
    RestDaysService().checkTodayIsRestDay().then((value) {
      if (mounted) setState(() => _isTodayRestDay = value);
    });
    RestDaysService().getRestDays().then((settings) {
      if (mounted) setState(() => _restDays = settings);
    }).catchError((_) {
      // Non-critical — Recovery card falls back to the activity-only heuristic.
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Wire ring provider — reload backend history when ring (re)connects.
    final ringProvider = Provider.of<RingProvider>(context, listen: false);
    if (_ringProvider != ringProvider) {
      _ringProvider?.removeListener(_onRingStateChanged);
      _ringProvider = ringProvider;
      _lastConnected = ringProvider.isConnected;
      ringProvider.addListener(_onRingStateChanged);
      _loadData();
    }

    // Wire TodayStepsProvider — update today's slot when ring data arrives.
    final stepsProvider =
        Provider.of<TodayStepsProvider>(context, listen: false);
    if (_stepsProvider != stepsProvider) {
      _stepsProvider?.removeListener(_onTodayStepsChanged);
      _stepsProvider = stepsProvider;
      stepsProvider.addListener(_onTodayStepsChanged);
    }
  }

  void _onRingStateChanged() {
    if (!mounted) return;
    final connected = _ringProvider?.isConnected ?? false;
    if (connected && !_lastConnected) {
      // Ring just connected — refresh backend history (sync handled by TodayStepsProvider).
      _loadData();
    }
    _lastConnected = connected;
  }

  /// Called whenever [TodayStepsProvider] finishes a ring sync + backend fetch.
  /// Patches today's slot in [_weekData] so both screens always show the same count.
  void _onTodayStepsChanged() {
    if (!mounted || _weekData.isEmpty) return;
    final today = _stepsProvider?.today;
    if (today == null) return;
    setState(() {
      _weekData[0] = _DayData(
        date: _weekData[0].date,
        steps: today.steps,
        activeMinutes: today.activeMinutes,
        goalMinutes: _weekData[0].goalMinutes,
        goalSteps: _weekData[0].goalSteps,
        goalReason: _weekData[0].goalReason,
        goalIsReduced: _weekData[0].goalIsReduced,
      );
    });
  }

  @override
  void dispose() {
    _ringProvider?.removeListener(_onRingStateChanged);
    _stepsProvider?.removeListener(_onTodayStepsChanged);
    super.dispose();
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Ring BLE sync is owned by TodayStepsProvider — no duplicate sync here.
    // Fetch 7-day history + today's goal from backend.
    final now = DateTime.now();
    final startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));

    final history = await StepsService().getHistory(start: startDate, end: now);
    final todayGoal = await StepsService().getGoal(now);
    final sleepHistory = await SleepService()
        .getSleepHistory(startDate: startDate, endDate: now)
        .catchError((_) => <SleepSession>[]);
    final sleepScoreByDate = <String, int>{
      for (final s in sleepHistory)
        _fmtDate(s.wakeTime.toLocal()):
            s.sleepQualityScore.round().clamp(0, 100),
    };

    // 3. Build a _DayData entry for each of the last 7 days.
    //    Days with no ring data show 0 steps / 0 active minutes.
    final weekData = <_DayData>[];
    for (var i = 0; i < 7; i++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));
      final dateStr = _fmtDate(day);

      final matches = history.where((h) => h.dateStr == dateStr);
      final record = matches.isEmpty ? null : matches.first;

      int goalMinutes;
      int goalSteps;
      String goalReason;
      bool goalIsReduced;
      if (i == 0 && todayGoal != null) {
        goalMinutes = todayGoal.goalMinutes;
        goalSteps = todayGoal.goalSteps;
        goalReason = todayGoal.reason;
        goalIsReduced = todayGoal.isReduced;
      } else if (record != null) {
        goalMinutes = record.goalMinutes;
        goalSteps = record.goalSteps;
        goalReason = record.goalReason;
        goalIsReduced = record.goalIsReduced;
      } else {
        // No data for this day — use simple weekday/weekend baseline.
        goalMinutes = day.weekday >= 6 ? 45 : 60;
        goalSteps = day.weekday >= 6 ? 6000 : 8000;
        goalReason = '';
        goalIsReduced = false;
      }

      // For today (i == 0), prefer TodayStepsProvider data — it reflects the
      // latest ring sync and is the same source used by the dashboard.
      final providerToday = (i == 0) ? _stepsProvider?.today : null;
      weekData.add(
        _DayData(
          date: day,
          steps: providerToday?.steps ?? record?.steps ?? 0,
          activeMinutes:
              providerToday?.activeMinutes ?? record?.activeMinutes ?? 0,
          goalMinutes: goalMinutes,
          goalSteps: goalSteps,
          goalReason: goalReason,
          goalIsReduced: goalIsReduced,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _weekData = weekData;
        _sleepScoreByDate = sleepScoreByDate;
        _isLoading = false;
      });
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─── Workout recording ────────────────────────────────────────────────────

  void _onRecordWorkout() {
    final ring = context.read<RingProvider>();
    if (!ring.isPaired || !ring.isBluetoothOn) {
      _showRingRequiredDialog(ring);
      return;
    }
    _showActivityPicker();
  }

  void _showRingRequiredDialog(RingProvider ring) {
    final bool bluetoothOff = ring.isPaired && !ring.isBluetoothOn;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: AppColors.error),
            SizedBox(width: 8),
            Text('Ring Not Connected'),
          ],
        ),
        content: Text(
          bluetoothOff
              ? 'Turn on Bluetooth to connect your Lumie Ring for heart rate tracking.'
              : 'Your Lumie Ring is not connected.\n\nIf your ring is in the charger, remove it and make sure it\'s nearby.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
          if (!ring.isPaired)
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushNamed('/ring/manage');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLemonDark,
                foregroundColor: const Color(0xFF78350F),
              ),
              child: const Text('Connect Ring'),
            ),
        ],
      ),
    );
  }

  void _showActivityPicker() {
    final tier = context.read<AuthProvider>().subscriptionTier;
    final isPro = tier != SubscriptionTier.free;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ActivityPickerSheet(
        isPro: isPro,
        onSelected: (type) {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WorkoutRecordingScreen(activityType: type),
              fullscreenDialog: true,
            ),
          );
        },
        onWorkoutSelected: (plan) {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WorkoutSessionScreen(workoutPlan: plan),
              fullscreenDialog: true,
            ),
          );
        },
        onUpgradeTapped: () {
          Navigator.of(ctx).pop(); // close picker sheet
          Navigator.of(context).pushNamed('/subscription/upgrade').then((_) {
            // Re-open picker after returning — subscription may now be active.
            if (mounted) _showActivityPicker();
          });
        },
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final goalType = context.watch<ActivityGoalProvider>().goalType;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onRecordWorkout,
        backgroundColor: AppColors.primaryLemonDark,
        foregroundColor: const Color(0xFF78350F),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text(
          'Record Workout',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _buildWeekSelector(goalType),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 100),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        _buildSelectedDaySummary(goalType),
                        const SizedBox(height: 8),
                        _ContributorsCard(
                          week: _weekData,
                          goalType: goalType,
                          restDays: _restDays,
                          sleepScoreByDate: _sleepScoreByDate,
                        ),
                        const SizedBox(height: 8),
                        _buildActivityList(),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'Activity History',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
    );
  }

  Widget _buildWeekSelector(ActivityGoalType goalType) {
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryLemon.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(7, (index) {
          final dayData = _weekData[6 - index];
          final isSelected = _selectedDayIndex == (6 - index);
          final dayOfWeek = dayData.date.weekday % 7;

          return GestureDetector(
            onTap: () => setState(() => _selectedDayIndex = 6 - index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected ? AppColors.progressGradient : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    days[dayOfWeek],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.textOnYellow
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dayData.date.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AppColors.textOnYellow
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dayData.goalMet(goalType)
                          ? AppColors.success
                          : AppColors.surfaceLight,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSelectedDaySummary(ActivityGoalType goalType) {
    final selected = _weekData[_selectedDayIndex];
    final isViewingTodayOnRestDay = _selectedDayIndex == 0 && _isTodayRestDay;
    final goalMet = selected.goalMet(goalType);

    return GradientCard(
      gradient: AppColors.warmGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rest-day banner — gold-tinted to match the card theme.
          if (isViewingTodayOnRestDay) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.self_improvement,
                    size: 16,
                    color: AppColors.textOnYellow,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recovery day — your full data is shown below.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textOnYellow,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Date + Goal Met badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(selected.date),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textOnYellow,
                ),
              ),
              if (goalMet)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Goal Met!',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textOnYellow,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Active time + goal — always one line ("81 min / 45 min goal").
          _MetricLine(
            icon: Icons.timer_outlined,
            value: '${selected.activeMinutes} min',
            suffix: '/ ${selected.goalMinutes} min goal',
          ),
          const SizedBox(height: 8),
          // Step count — always exact, comma-separated ("9,043 steps").
          _MetricLine(
            icon: Icons.directions_walk,
            value: '${_fmtSteps(selected.steps)} steps',
          ),
          const SizedBox(height: 16),

          // Progress bar — fills against whichever goal type the user has set.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: selected.goalProgress(goalType),
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.45),
              valueColor: AlwaysStoppedAnimation<Color>(
                goalMet ? AppColors.textOnYellow : AppColors.primaryLemonDark,
              ),
            ),
          ),

          // Italic adjustment note (e.g. "Reduced — recovering from poor sleep").
          if (selected.goalReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              selected.goalReason,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textOnYellow,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Workouts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.textLight),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tap "Record Workout" to log a session with heart rate data.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    }
    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  /// Format a step count with thousands separators — e.g. `9043` → `9,043`.
  /// Never abbreviated; this screen always shows the exact number.
  static String _fmtSteps(int steps) {
    final s = steps.abs().toString();
    final buf = StringBuffer(steps < 0 ? '-' : '');
    final n = s.length;
    for (int i = 0; i < n; i++) {
      if (i > 0 && (n - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
// ─── Today card metric line ───────────────────────────────────────────────────

/// Single line on the Today card — icon + bold value + optional pale suffix
/// (used to render the "/ 45 min goal" trailing text without competing with
/// the primary value).
class _MetricLine extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? suffix;

  const _MetricLine({
    required this.icon,
    required this.value,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: AppColors.textOnYellow),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textOnYellow,
            height: 1.1,
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 6),
          Text(
            suffix!,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textOnYellow.withValues(alpha: 0.75),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Contributors card ────────────────────────────────────────────────────────

/// One Oura-style stacked card containing every contributor as a tight row:
/// bold name on the left, status value on the right, a thin gold progress bar
/// directly underneath, then a hairline divider separating the next row.
/// No per-row borders, gaps, or warning colours.
class _ContributorsCard extends StatelessWidget {
  final List<_DayData> week;
  final ActivityGoalType goalType;
  final RestDaySettings? restDays;
  final Map<String, int> sleepScoreByDate;

  const _ContributorsCard({
    required this.week,
    required this.goalType,
    required this.restDays,
    required this.sleepScoreByDate,
  });

  // ── Per-contributor logic ────────────────────────────────────────────────

  /// Days the daily activity goal was hit in the 7-day window.
  ({String value, double progress}) _meetDailyGoals() {
    final hit = week.where((d) => d.goalMet(goalType)).length;
    final progress = (hit / 7).clamp(0.0, 1.0);
    final status = hit >= 5
        ? 'Optimal'
        : hit == 4
            ? 'Good'
            : 'Keep building';
    return (value: '$hit/7 days · $status', progress: progress);
  }

  ({String value, double progress}) _trainingFrequency() {
    final sessions = week
        .where((d) => d.activeMinutes >= _kSessionMinutesThreshold)
        .length;
    final progress = (sessions / _kWeeklyFrequencyTarget).clamp(0.0, 1.0);
    final status = sessions >= _kWeeklyFrequencyTarget
        ? 'Optimal'
        : sessions >= _kWeeklyFrequencyTarget - 1
            ? 'Good'
            : 'Keep building';
    return (
      value: '$sessions/$_kWeeklyFrequencyTarget sessions · $status',
      progress: progress,
    );
  }

  ({String value, double progress}) _trainingVolume() {
    final volume = week.fold<int>(0, (sum, d) => sum + d.activeMinutes);
    final progress = (volume / _kWeeklyVolumeTarget).clamp(0.0, 1.0);
    final status = volume >= _kWeeklyVolumeTarget
        ? 'Optimal'
        : volume >= (_kWeeklyVolumeTarget * 0.6).round()
            ? 'Good'
            : 'Keep building';
    return (
      value: '$volume/$_kWeeklyVolumeTarget min · $status',
      progress: progress,
    );
  }

  /// Combined rest + sleep recovery score over the 7-day window.
  ///
  /// Each day earns a fractional credit (0.0–1.0) blending whether the day was
  /// physically restful and how well the user slept that night:
  ///   rested + good sleep   → 1.0
  ///   rested + ok sleep     → 0.7
  ///   rested + poor sleep   → 0.4   (poor sleep blunts a rest day)
  ///   active + good sleep   → 0.6   (good sleep helps even on training days)
  ///   active + ok sleep     → 0.3
  ///   active + poor sleep   → 0.0
  /// Missing sleep data falls back to a neutral mid-credit so unsynced nights
  /// don't crash the score.
  double _recoveryCreditForDay(_DayData day) {
    final rested = (restDays?.isRestDay(day.date) ?? false) ||
        day.activeMinutes < _kSessionMinutesThreshold;
    final dateStr =
        '${day.date.year}-${day.date.month.toString().padLeft(2, '0')}-${day.date.day.toString().padLeft(2, '0')}';
    final sleep = sleepScoreByDate[dateStr];
    if (rested) {
      if (sleep == null) return 0.7;
      if (sleep >= 70) return 1.0;
      if (sleep >= 50) return 0.7;
      return 0.4;
    } else {
      if (sleep == null) return 0.3;
      if (sleep >= 70) return 0.6;
      if (sleep >= 50) return 0.3;
      return 0.0;
    }
  }

  ({String value, double progress}) _recoveryTime() {
    final total = week.fold<double>(0, (sum, d) => sum + _recoveryCreditForDay(d));
    final progress = (total / 7).clamp(0.0, 1.0);
    final shown = total.round();
    final status = progress >= 0.7
        ? 'Optimal'
        : progress >= 0.4
            ? 'Good'
            : 'Keep building';
    return (value: '$shown/7 days · $status', progress: progress);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final goals = _meetDailyGoals();
    final frequency = _trainingFrequency();
    final volume = _trainingVolume();
    final recovery = _recoveryTime();

    final rows = [
      (name: 'Meet Daily Goals', value: goals.value, progress: goals.progress),
      (
        name: 'Training Frequency',
        value: frequency.value,
        progress: frequency.progress
      ),
      (name: 'Training Volume', value: volume.value, progress: volume.progress),
      (
        name: 'Recovery Time',
        value: recovery.value,
        progress: recovery.progress
      ),
    ];

    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _ContributorRow(
              name: rows[i].name,
              value: rows[i].value,
              progress: rows[i].progress,
            ),
            if (i < rows.length - 1)
              const Divider(
                height: 18,
                thickness: 0.5,
                color: AppColors.surfaceLight,
              ),
          ],
        ],
      ),
    );
  }
}

/// One contributor inside [_ContributorsCard]: bold name on the left, value on
/// the right, gold progress bar tight beneath.
class _ContributorRow extends StatelessWidget {
  final String name;
  final String value;
  final double progress;

  const _ContributorRow({
    required this.name,
    required this.value,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 5,
            backgroundColor: AppColors.surfaceLight,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.primaryLemonDark,
            ),
          ),
        ),
      ],
    );
  }
}
