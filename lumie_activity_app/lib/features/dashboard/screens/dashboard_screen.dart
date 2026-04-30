import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rest_days_service.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/widgets/circular_progress_indicator.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../../shared/widgets/intensity_badge.dart';
import '../../../shared/widgets/ring_status_indicator.dart';
import '../../activity/screens/activity_history_screen.dart';
import '../../ring/providers/ring_provider.dart';
import '../../wellness/providers/wellness_provider.dart';
import '../../heart_rate/providers/heart_rate_provider.dart';
import '../../../shared/models/steps_models.dart';
import '../../activity/providers/today_steps_provider.dart';
import '../../settings/providers/activity_goal_provider.dart';
import '../../sleep/providers/sleep_provider.dart';
import '../../sleep/screens/sleep_screen.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../../wellness/screens/wellness_detail_screen.dart';
import '../../wellness/screens/stress_detail_screen.dart';
import '../../wellness/providers/stress_provider.dart';
import '../../../shared/models/stress_models.dart';
import '../../wellness/widgets/stress_timeline_chart.dart';
import '../../../core/services/ring_sync_service.dart';
import '../widgets/activity_summary_card.dart';
import '../widgets/quick_actions_section.dart';
import '../widgets/adaptive_goal_card.dart';
import '../widgets/rest_day_suggestion_sheet.dart';
import '../widgets/active_tasks_card.dart';
import '../widgets/sky_background.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  // Rest-day reduced targets (not measurements — goal values only).
  static const int _restDayGoalMinutes = 20;
  static const int _restDayGoalSteps = 2667; // ~20 min equivalent

  final ActivityIntensity _dominantIntensity = ActivityIntensity.moderate;

  bool _isRestDay = false;

  /// Activity score: today's real progress vs. the active goal.
  /// Reads from [TodayStepsProvider] so the same value drives both the
  /// score card and every other widget on this screen.
  int _activityScore(
      ActivityGoalProvider goalProv, TodayStepsProvider stepsProv) {
    if (goalProv.goalType == ActivityGoalType.steps) {
      final goal =
          _isRestDay ? _restDayGoalSteps : goalProv.effectiveGoalSteps;
      if (goal <= 0) return 0;
      return ((stepsProv.todaySteps / goal) * 100).round().clamp(0, 100);
    }
    final goal =
        _isRestDay ? _restDayGoalMinutes : goalProv.effectiveGoalMinutes;
    if (goal <= 0) return 0;
    return ((stepsProv.todayActiveMinutes / goal) * 100)
        .round()
        .clamp(0, 100);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkRestDaySuggestion();
    _loadRestDayStatus();

    // Reload ring info in case it was paired while away
    // Load tasks if not yet loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconnectRing();
      final tasksProvider = context.read<TasksProvider>();
      if (tasksProvider.state == TasksState.initial) {
        tasksProvider.loadTasks();
      }
      context.read<WellnessProvider>().load();
      context.read<StressProvider>().load();
      context.read<SleepProvider>().load();
      context.read<ActivityGoalProvider>().load();
      context.read<TodayStepsProvider>().load();
      context.read<HeartRateProvider>().fetchDailyHistory();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconnectRing();
    }
  }

  void _reconnectRing() {
    if (mounted) {
      context.read<RingProvider>().tryReconnect();
    }
  }

  Future<void> _loadRestDayStatus() async {
    try {
      final isRestDay = await RestDaysService().checkTodayIsRestDay();
      if (mounted) {
        setState(() => _isRestDay = isRestDay);
      }
    } catch (_) {
      // Non-critical — keep default false
    }
  }

  /// Check if a rest day should be suggested based on sleep quality.
  Future<void> _checkRestDaySuggestion() async {
    // Wait a bit for UI to settle
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    try {
      final suggestion = await RestDaysService().getRestDaySuggestion();

      if (mounted && suggestion.shouldSuggest) {
        RestDaySuggestionSheet.show(
          context: context,
          suggestion: suggestion,
        );
      }
    } catch (e) {
      // Silently fail - rest day suggestion is not critical
      debugPrint('⚠️ Failed to check rest day suggestion: $e');
    }
  }

  /// Mood for the dynamic sky background — derived from today's wellness
  /// signals (sleep, activity, stress) and the wall-clock hour. The widget
  /// crossfades between moods, so this can be recomputed cheaply on every build.
  SkyMood _resolveSkyMood(
    SleepProvider sleep,
    StressProvider stress,
    ActivityGoalProvider goalProv,
    TodayStepsProvider stepsProv,
  ) {
    final activity = _activityScore(goalProv, stepsProv);
    return SkyMood.fromScores(
      now: DateTime.now(),
      sleepScore: sleep.latestSleep != null ? sleep.sleepScore : null,
      activityScore: activity,
      stressScore: stress.hasData ? stress.score : null,
      isRestDay: _isRestDay,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dynamic sky/cosmos background — visible through every glassmorphic card.
        Positioned.fill(
          child: Consumer4<SleepProvider, StressProvider, ActivityGoalProvider,
              TodayStepsProvider>(
            builder: (context, sleep, stress, goalProv, stepsProv, _) {
              final mood = _resolveSkyMood(sleep, stress, goalProv, stepsProv);
              return SkyBackground(mood: mood);
            },
          ),
        ),
        Scaffold(
      backgroundColor: Colors.transparent,
      drawer: _buildDrawer(context),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildScoreRow(),
                const SizedBox(height: 12),
                const ActiveTasksCard(),
                const SizedBox(height: 12),
                if (!_isRestDay) ...[
                  _buildMainActivityRing(),
                  const SizedBox(height: 12),
                  _buildHrCard(),
                  const SizedBox(height: 12),
                  _buildStressCard(),
                  const SizedBox(height: 24),
                  Consumer<TodayStepsProvider>(
                    builder: (context, stepsProv, _) =>
                        _buildTodaysSummary(stepsProv),
                  ),
                  const SizedBox(height: 16),
                ],
                Consumer2<WellnessProvider, ActivityGoalProvider>(
                  builder: (context, wellness, goalProv, _) {
                    final stepsProv = context.watch<TodayStepsProvider>();
                    final fatigueFactor = switch (wellness.fatigue.level) {
                      _ when !wellness.fatigue.hasData => 'Baseline still learning',
                      _ => 'Fatigue: ${wellness.fatigue.fullLabel.toLowerCase()}',
                    };
                    final isSteps = goalProv.goalType == ActivityGoalType.steps;
                    final goalValue = _isRestDay
                        ? (isSteps ? _restDayGoalSteps : _restDayGoalMinutes)
                        : (isSteps
                            ? goalProv.effectiveGoalSteps
                            : goalProv.effectiveGoalMinutes);
                    final currentValue = isSteps
                        ? stepsProv.todaySteps
                        : stepsProv.todayActiveMinutes;
                    return AdaptiveGoalCard(
                      goalValue: goalValue,
                      currentValue: currentValue,
                      unitLabel: goalProv.goalType.unitLabel,
                      reason: _isRestDay
                          ? 'Today is a scheduled rest day. Light movement only — let your body recover!'
                          : 'Based on your recent rest and activity patterns',
                      isReduced: _isRestDay,
                      factors: _isRestDay
                          ? ['Rest day scheduled', 'Recovery focus', 'Light movement ok']
                          : [
                              'Good sleep last night',
                              'Moderate activity yesterday',
                              fatigueFactor,
                            ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildRecentActivities(),
                const SizedBox(height: 16),
                const QuickActionsSection(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    ),
      ],
    );
  }

  Widget _buildScoreRow() {
    return Consumer2<WellnessProvider, SleepProvider>(
      builder: (context, wellness, sleep, _) {
        final goalProv = context.watch<ActivityGoalProvider>();
        final fatigue = wellness.fatigue;
        final stress = wellness.stress;
        final hasSleepData = sleep.latestSleep != null;
        final sleepScore = hasSleepData ? sleep.sleepScore : 0;
        final hasStressData = context.watch<StressProvider>().hasData;

        final scores = [
          _ScoreData(
            label: 'Fatigue',
            score: 0,
            centerLabel: fatigue.centerLabel,
            icon: Icons.battery_charging_full,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WellnessDetailScreen(metric: WellnessMetric.fatigue),
              ),
            ),
          ),
          _ScoreData(
            label: 'Sleep',
            score: sleepScore,
            centerLabel: hasSleepData ? null : '—',
            icon: Icons.bedtime_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SleepScreen()),
            ),
          ),
          _ScoreData(
            label: 'Activity',
            score: _activityScore(goalProv, context.watch<TodayStepsProvider>()),
            icon: Icons.directions_run,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActivityHistoryScreen()),
            ),
          ),
          _ScoreData(
            label: 'Stress',
            score: hasStressData ? context.watch<StressProvider>().score : 0,
            centerLabel: hasStressData ? null : stress.centerLabel,
            icon: Icons.self_improvement,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const StressDetailScreen(),
              ),
            ),
          ),
        ];

        // No card / container / header — the four scores float directly on
        // the dynamic sky, Oura-style. Padding only widens the touch row to
        // match the rest of the column's horizontal margin.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: scores.map((s) => _buildScoreChip(s)).toList(),
          ),
        );
      },
    );
  }

  /// Single floating score "halo" — a soft frosted disk with the score
  /// number + icon inside, label below. No hard border, no shadow; the disk
  /// is just a slightly darker patch of glass over the sky.
  Widget _buildScoreChip(_ScoreData data) {
    final usesLabel = data.centerLabel != null;
    final centerText = usesLabel ? data.centerLabel! : '${data.score}';

    return GestureDetector(
      onTap: data.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipPath(
            clipper: const _StarClipper(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: 88,
                height: 88,
                // Subtle radial halo — center marginally darker than the
                // edge so the star reads as a soft glassy lens rather than
                // a hard-edged token. No border, no shadow.
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0.12),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      data.icon,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      centerText,
                      style: TextStyle(
                        fontSize: usesLabel ? 13 : 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.0,
                        // Faint shadow — keeps the value readable over a
                        // bright sky photo without needing a border on the
                        // disk itself.
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              shadows: [
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHrCard() {
    return Consumer2<RingProvider, HeartRateProvider>(
      builder: (context, ring, hr, _) {
        if (!ring.isPaired && !ring.isConnected) return const SizedBox.shrink();
        final connected = ring.isConnected;
        final bpmText = connected
            ? (hr.latestHr != null ? '${hr.latestHr} BPM' : 'Tap to measure')
            : 'Ring disconnected';
        return GradientCard(
          glass: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          onTap: () => Navigator.pushNamed(context, '/heart-rate'),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (connected ? Colors.redAccent : AppColors.textLight)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  connected ? Icons.favorite : Icons.bluetooth_disabled,
                  color: connected ? Colors.redAccent : AppColors.textLight,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Heart Rate',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    bpmText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: connected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStressCard() {
    return Consumer<StressProvider>(
      builder: (context, stress, _) {
        if (!stress.hasData && !stress.hasBaseline) {
          return const SizedBox.shrink();
        }

        final today = stress.today;
        final zone = stress.currentZone;
        final zoneColor = zone?.displayColor ??
            today?.averageZone.displayColor ??
            AppColors.textLight;
        final timeline = today?.timeline ?? [];

        return GradientCard(
          glass: true,
          padding: const EdgeInsets.all(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StressDetailScreen()),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: zoneColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.self_improvement,
                          color: zoneColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stress',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (stress.hasData && today != null)
                            Row(
                              children: [
                                Text(
                                  '${today.score}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: zone?.chartColor ??
                                        today.averageZone.chartColor,
                                    shape: BoxShape.circle,
                                    border: (zone ?? today.averageZone) ==
                                            StressZone.restored
                                        ? Border.all(
                                            color: AppColors.surfaceLight)
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  today.scoreLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: zoneColor,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              zone?.label ?? 'No data',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: zoneColor,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(
                          Icons.chevron_right, color: AppColors.textSecondary),
                    ],
                  ),
                  if (timeline.length >= 2) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: StressTimelineChart(
                        readings: timeline,
                        height: 48,
                        compact: true,
                      ),
                    ),
                  ],
                ],
              ),
        );
      },
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 60,
      floating: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: AppColors.textPrimary),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Good Morning',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Consumer<RingSyncService>(
            builder: (context, sync, _) {
              final label = sync.status.isSyncing
                  ? 'Ring data syncing...'
                  : 'Here\'s your day at a glance';
              return Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.normal,
                ),
              );
            },
          ),
        ],
      ),
      centerTitle: false,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Consumer<RingProvider>(
            builder: (context, ring, _) {
              return RingStatusIndicator(
                status: ring.isConnected ? RingStatus.connected : RingStatus.disconnected,
                batteryLevel: ring.ringInfo?.batteryLevel,
                compact: true,
                onTap: () => Navigator.pushNamed(context, '/ring/manage'),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.backgroundPaper,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'Lumie',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontFamily: 'Playfair Display',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Container(height: 2, width: 32, color: AppColors.primaryLemonDark),
            ),
            _DrawerItem(
              icon: Icons.wb_sunny_outlined,
              label: 'Today',
              onTap: () => Navigator.pop(context),
            ),
            _DrawerItem(
              icon: Icons.auto_awesome_outlined,
              label: 'Advisor',
              onTap: () {
                Navigator.pop(context);
                // Handled by bottom nav index 1
              },
            ),
            _DrawerItem(
              icon: Icons.history,
              label: 'Activity History',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityHistoryScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.bedtime_outlined,
              label: 'Sleep',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SleepScreen()));
              },
            ),
            const Divider(indent: 24, endIndent: 24),
            _DrawerItem(
              icon: Icons.event_busy_outlined,
              label: 'Rest Day Schedule',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/settings/rest-days');
              },
            ),
            _DrawerItem(
              icon: Icons.flag_outlined,
              label: 'Activity Goal',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/settings/activity-goal');
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Version 1.0',
                style: TextStyle(fontSize: 12, color: AppColors.textLight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainActivityRing() {
    return Consumer<ActivityGoalProvider>(
      builder: (context, goalProv, _) {
        final stepsProv = context.watch<TodayStepsProvider>();
        final isSteps = goalProv.goalType == ActivityGoalType.steps;
        final currentValue =
            isSteps ? stepsProv.todaySteps : stepsProv.todayActiveMinutes;
        final goalValue = isSteps
            ? goalProv.effectiveGoalSteps
            : goalProv.effectiveGoalMinutes;
        final unitLabel = goalProv.goalType.unitLabel;
        return GradientCard(
          glass: true,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Today\'s Activity',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              ActivityRing(
                progress: currentValue / goalValue,
                currentValue: currentValue,
                goalValue: goalValue,
                unitLabel: unitLabel,
                size: 180,
              ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Dominant Intensity: ',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              IntensityBadge(intensity: _dominantIntensity),
            ],
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildTodaysSummary(TodayStepsProvider stepsProv) {
    return ActivitySummaryCard(
      ringTrackedMinutes: stepsProv.todayActiveMinutes,
      manualMinutes: 0,
      activitiesCount: stepsProv.hasData ? 1 : 0,
    );
  }

  Widget _buildRecentActivities() {
    final recentActivities = [
      ActivityRecord(
        id: '1',
        activityType: ActivityType.predefinedTypes[0], // Walking
        startTime: DateTime.now().subtract(const Duration(hours: 2)),
        endTime: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)),
        durationMinutes: 15,
        intensity: ActivityIntensity.low,
        source: ActivitySource.ring,
        isEstimated: false,
        heartRateAvg: 85,
      ),
      ActivityRecord(
        id: '2',
        activityType: ActivityType.predefinedTypes[4], // Yoga
        startTime: DateTime.now().subtract(const Duration(hours: 5)),
        endTime: DateTime.now().subtract(const Duration(hours: 4, minutes: 40)),
        durationMinutes: 20,
        intensity: ActivityIntensity.moderate,
        source: ActivitySource.ring,
        isEstimated: false,
        heartRateAvg: 92,
      ),
      ActivityRecord(
        id: '3',
        activityType: ActivityType.predefinedTypes[2], // Cycling
        startTime: DateTime.now().subtract(const Duration(hours: 8)),
        endTime: DateTime.now().subtract(const Duration(hours: 7, minutes: 53)),
        durationMinutes: 7,
        intensity: ActivityIntensity.moderate,
        source: ActivitySource.manual,
        isEstimated: true,
      ),
    ];

    return GradientCard(
      glass: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Activities',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('See All'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recentActivities.map((activity) => _buildActivityItem(activity)),
        ],
      ),
    );
  }

  Widget _buildActivityItem(ActivityRecord activity) {
    final timeFormat = '${activity.startTime.hour}:${activity.startTime.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.warmGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                activity.activityType.icon,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      activity.activityType.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (activity.isEstimated) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.textLight.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Estimated',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$timeFormat • ${activity.durationMinutes} min',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (activity.intensity != null)
            IntensityBadge(
              intensity: activity.intensity!,
              isEstimated: activity.isEstimated,
              size: 20,
            ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(icon, color: AppColors.textSecondary, size: 20),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ScoreData {
  final String label;
  final int score;
  /// When set, replaces the numeric score in the chip centre (used for
  /// no-data / calibrating states like "—" or "···").
  final String? centerLabel;
  final IconData icon;
  final VoidCallback onTap;

  const _ScoreData({
    required this.label,
    required this.score,
    this.centerLabel,
    required this.icon,
    required this.onTap,
  });
}

/// 5-pointed star clipper used to shape the score chip's frosted halo.
/// Outer points sit on the bounding circle; inner notch radius is 42% of
/// the outer (matches the previous `_StarPainter` proportions so the
/// silhouette feels familiar).
class _StarClipper extends CustomClipper<Path> {
  const _StarClipper();

  @override
  Path getClip(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.shortestSide / 2;
    final inner = outer * 0.42;
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = (i * 72 - 90) * math.pi / 180;
      final innerAngle = ((i * 72 + 36) - 90) * math.pi / 180;
      final op = Offset(
        cx + outer * math.cos(outerAngle),
        cy + outer * math.sin(outerAngle),
      );
      final ip = Offset(
        cx + inner * math.cos(innerAngle),
        cy + inner * math.sin(innerAngle),
      );
      i == 0 ? path.moveTo(op.dx, op.dy) : path.lineTo(op.dx, op.dy);
      path.lineTo(ip.dx, ip.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
