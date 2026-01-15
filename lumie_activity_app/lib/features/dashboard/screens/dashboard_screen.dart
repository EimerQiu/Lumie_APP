import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/widgets/circular_progress_indicator.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../../shared/widgets/intensity_badge.dart';
import '../../../shared/widgets/ring_status_indicator.dart';
import '../widgets/activity_summary_card.dart';
import '../widgets/quick_actions_section.dart';
import '../widgets/adaptive_goal_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Mock data for demo
  final RingStatus _ringStatus = RingStatus.connected;
  final int _batteryLevel = 78;
  final int _currentMinutes = 42;
  final int _goalMinutes = 60;
  final ActivityIntensity _dominantIntensity = ActivityIntensity.moderate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildRingStatus(),
                    const SizedBox(height: 16),
                    _buildMainActivityRing(),
                    const SizedBox(height: 24),
                    _buildTodaysSummary(),
                    const SizedBox(height: 16),
                    const AdaptiveGoalCard(
                      recommendedMinutes: 60,
                      reason: 'Based on your recent rest and activity patterns',
                      isReduced: false,
                      factors: [
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
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 60,
      floating: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.sunriseGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '☀️',
                style: TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Good Morning!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Let\'s check your activity',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildRingStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: RingStatusIndicator(
        status: _ringStatus,
        batteryLevel: _batteryLevel,
        onTap: () {
          // Navigate to ring settings
        },
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
              fontSize: 18,
              fontWeight: FontWeight.w600,
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
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
