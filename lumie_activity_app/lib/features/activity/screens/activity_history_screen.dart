import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rest_days_service.dart';
import '../../../core/services/steps_service.dart';
import '../../../shared/models/user_models.dart';
import '../../settings/providers/activity_goal_provider.dart';
import '../providers/today_steps_provider.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../ring/providers/ring_provider.dart';
import '../widgets/activity_picker_sheet.dart';
import 'workout_recording_screen.dart';
import 'workout_session_screen.dart';

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

  RingProvider? _ringProvider;
  bool _lastConnected = false;

  TodayStepsProvider? _stepsProvider;

  @override
  void initState() {
    super.initState();
    RestDaysService().checkTodayIsRestDay().then((value) {
      if (mounted) setState(() => _isTodayRestDay = value);
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
                        const SizedBox(height: 16),
                        _buildWeeklyOverview(goalType),
                        const SizedBox(height: 16),
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

    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        children: [
          // Rest-day banner
          if (isViewingTodayOnRestDay) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accentMint.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.accentMint.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.self_improvement,
                    size: 16,
                    color: AppColors.accentMint,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rest Day — light movement only. Your full data is shown below.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Date + goal label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(selected.date),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              if (selected.goalMet(goalType))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Goal Met!',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Primary metric (hero) + secondary side by side — swaps with goal type
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          goalType == ActivityGoalType.steps
                              ? _fmtSteps(selected.steps)
                              : '${selected.activeMinutes}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            goalType == ActivityGoalType.steps ? 'steps' : 'min',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          goalType == ActivityGoalType.steps
                              ? Icons.directions_walk
                              : Icons.timer_outlined,
                          size: 14,
                          color: AppColors.textLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          goalType == ActivityGoalType.steps
                              ? 'Ring tracked'
                              : 'Active time',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    goalType == ActivityGoalType.steps
                        ? '${selected.activeMinutes}'
                        : _fmtSteps(selected.steps),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    goalType == ActivityGoalType.steps ? 'min active' : 'steps',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    goalType == ActivityGoalType.steps
                        ? 'Goal: ${_fmtSteps(selected.goalSteps)} steps'
                        : 'Goal: ${selected.goalMinutes} min',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: selected.goalProgress(goalType),
              minHeight: 12,
              backgroundColor: AppColors.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(
                selected.goalMet(goalType)
                    ? AppColors.success
                    : AppColors.primaryLemonDark,
              ),
            ),
          ),

          // Goal reason
          if (selected.goalReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                selected.goalReason,
                style: TextStyle(
                  fontSize: 11,
                  color: selected.goalIsReduced
                      ? AppColors.warning
                      : AppColors.textLight,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklyOverview(ActivityGoalType goalType) {
    final totalSteps = _weekData.fold<int>(0, (sum, d) => sum + d.steps);
    final totalActive = _weekData.fold<int>(
      0,
      (sum, d) => sum + d.activeMinutes,
    );
    final goalsMet = _weekData.where((d) => d.goalMet(goalType)).length;

    return GradientCard(
      gradient: AppColors.mintGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This Week',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textOnYellow,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _WeekStatItem(
                  label: 'Total Steps',
                  value: _fmtSteps(totalSteps),
                  icon: Icons.directions_walk,
                ),
              ),
              Expanded(
                child: _WeekStatItem(
                  label: 'Active Time',
                  value: '$totalActive min',
                  icon: Icons.timer,
                ),
              ),
              Expanded(
                child: _WeekStatItem(
                  label: 'Goals Met',
                  value: '$goalsMet/7',
                  icon: Icons.flag,
                ),
              ),
            ],
          ),
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

  static String _fmtSteps(int steps) {
    if (steps >= 1000) {
      final k = steps / 1000.0;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return '$steps';
  }
}
// ─── Week stat item ───────────────────────────────────────────────────────────

class _WeekStatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _WeekStatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textOnYellow, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textOnYellow,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textOnYellow.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
