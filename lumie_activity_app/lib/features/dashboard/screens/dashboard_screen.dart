import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rest_days_service.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/models/ring_models.dart';
import '../../../shared/widgets/circular_progress_indicator.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../../shared/widgets/intensity_badge.dart';
import '../../../shared/widgets/ring_status_indicator.dart';
import '../../activity/screens/activity_history_screen.dart';
import '../../ring/providers/ring_provider.dart';
import '../../sleep/screens/sleep_screen.dart';
import '../widgets/activity_summary_card.dart';
import '../widgets/quick_actions_section.dart';
import '../widgets/adaptive_goal_card.dart';
import '../widgets/rest_day_suggestion_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Mock data for demo
  final int _currentMinutes = 42;
  final int _goalMinutes = 60;
  final ActivityIntensity _dominantIntensity = ActivityIntensity.moderate;

  bool _isRestDay = false;

  @override
  void initState() {
    super.initState();
    _checkRestDaySuggestion();
    _loadRestDayStatus();
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
      print('⚠️ Failed to check rest day suggestion: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      drawer: _buildDrawer(context),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildScoreRow(),
                const SizedBox(height: 12),
                _buildMainActivityRing(),
                const SizedBox(height: 24),
                _buildTodaysSummary(),
                const SizedBox(height: 16),
                AdaptiveGoalCard(
                  recommendedMinutes: _isRestDay ? 20 : _goalMinutes,
                  currentMinutes: _currentMinutes,
                  reason: _isRestDay
                      ? 'Today is a scheduled rest day. Light movement only — let your body recover!'
                      : 'Based on your recent rest and activity patterns',
                  isReduced: _isRestDay,
                  factors: _isRestDay
                      ? ['Rest day scheduled', 'Recovery focus', 'Light movement ok']
                      : [
                          'Good sleep last night',
                          'Moderate activity yesterday',
                          'No fatigue reported',
                        ],
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
    );
  }

  Widget _buildScoreRow() {
    final scores = [
      _ScoreData(
        label: 'Fatigue',
        score: 72,
        icon: Icons.battery_charging_full,
        color: const Color(0xFF81C784),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SleepScreen()),
        ),
      ),
      _ScoreData(
        label: 'Sleep',
        score: 85,
        icon: Icons.bedtime_outlined,
        color: const Color(0xFF64B5F6),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SleepScreen()),
        ),
      ),
      _ScoreData(
        label: 'Activity',
        score: 68,
        icon: Icons.directions_run,
        color: const Color(0xFFFFB74D),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ActivityHistoryScreen()),
        ),
      ),
      _ScoreData(
        label: 'Stress',
        score: 78,
        icon: Icons.self_improvement,
        color: const Color(0xFFB39DDB),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SleepScreen()),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GradientCard(
        gradient: AppColors.cardGradient,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today\'s Scores',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: scores.map((s) => _buildScoreCard(s)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard(_ScoreData data) {
    final Color scoreColor;
    if (data.score >= 80) {
      scoreColor = const Color(0xFF81C784);
    } else if (data.score >= 60) {
      scoreColor = const Color(0xFFFFB74D);
    } else {
      scoreColor = const Color(0xFFE57373);
    }

    return GestureDetector(
      onTap: data.onTap,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CustomPaint(
                  painter: _StarPainter(color: scoreColor, strokeWidth: 1.5, progress: data.score / 100),
                ),
              ),
              Text(
                '${data.score}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, size: 11, color: data.color),
              const SizedBox(width: 3),
              Text(
                data.label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 60,
      floating: true,
      backgroundColor: AppColors.backgroundPaper,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: AppColors.textPrimary),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Good Morning',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            'Here\'s your day at a glance',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      centerTitle: false,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Consumer<RingProvider>(
            builder: (context, ring, _) {
              final connectionStatus = ring.ringInfo?.connectionStatus;
              final isConnected = connectionStatus == RingConnectionStatus.connected;
              return RingStatusIndicator(
                status: isConnected ? RingStatus.connected : RingStatus.disconnected,
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
    return GradientCard(
      gradient: AppColors.cardGradient,
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
            progress: _currentMinutes / _goalMinutes,
            currentMinutes: _currentMinutes,
            goalMinutes: _goalMinutes,
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
  }

  Widget _buildTodaysSummary() {
    return const ActivitySummaryCard(
      ringTrackedMinutes: 35,
      manualMinutes: 7,
      activitiesCount: 3,
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
      gradient: AppColors.cardGradient,
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
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.surfaceLight,
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

class _StarPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double progress; // 0.0 – 1.0

  const _StarPainter({
    required this.color,
    required this.strokeWidth,
    required this.progress,
  });

  Path _buildStarPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.width / 2;
    final inner = outer * 0.42;
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = (i * 72 - 90) * math.pi / 180;
      final innerAngle = ((i * 72 + 36) - 90) * math.pi / 180;
      final op = Offset(cx + outer * math.cos(outerAngle), cy + outer * math.sin(outerAngle));
      final ip = Offset(cx + inner * math.cos(innerAngle), cy + inner * math.sin(innerAngle));
      i == 0 ? path.moveTo(op.dx, op.dy) : path.lineTo(op.dx, op.dy);
      path.lineTo(ip.dx, ip.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final starPath = _buildStarPath(size);

    // Background track
    canvas.drawPath(
      starPath,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );

    // Progress arc trimmed to `progress` of total path length
    final metric = starPath.computeMetrics().first;
    final filled = metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));
    canvas.drawPath(
      filled,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.progress != progress;
}

class _ScoreData {
  final String label;
  final int score;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ScoreData({
    required this.label,
    required this.score,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
