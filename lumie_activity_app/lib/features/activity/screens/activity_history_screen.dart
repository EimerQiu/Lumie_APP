import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../../shared/widgets/intensity_badge.dart';

class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({super.key});

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  int _selectedDayIndex = 0;

  // Mock data for the week
  final List<DailyActivitySummary> _weekData = [
    DailyActivitySummary(
      date: DateTime.now(),
      totalActiveMinutes: 42,
      goalMinutes: 60,
      dominantIntensity: ActivityIntensity.moderate,
      activities: [],
      ringTrackedMinutes: 35,
      manualMinutes: 7,
    ),
    DailyActivitySummary(
      date: DateTime.now().subtract(const Duration(days: 1)),
      totalActiveMinutes: 65,
      goalMinutes: 60,
      dominantIntensity: ActivityIntensity.moderate,
      activities: [],
      ringTrackedMinutes: 55,
      manualMinutes: 10,
    ),
    DailyActivitySummary(
      date: DateTime.now().subtract(const Duration(days: 2)),
      totalActiveMinutes: 30,
      goalMinutes: 45,
      dominantIntensity: ActivityIntensity.low,
      activities: [],
      ringTrackedMinutes: 30,
      manualMinutes: 0,
    ),
    DailyActivitySummary(
      date: DateTime.now().subtract(const Duration(days: 3)),
      totalActiveMinutes: 55,
      goalMinutes: 60,
      dominantIntensity: ActivityIntensity.high,
      activities: [],
      ringTrackedMinutes: 50,
      manualMinutes: 5,
    ),
    DailyActivitySummary(
      date: DateTime.now().subtract(const Duration(days: 4)),
      totalActiveMinutes: 40,
      goalMinutes: 60,
      dominantIntensity: ActivityIntensity.moderate,
      activities: [],
      ringTrackedMinutes: 40,
      manualMinutes: 0,
    ),
    DailyActivitySummary(
      date: DateTime.now().subtract(const Duration(days: 5)),
      totalActiveMinutes: 72,
      goalMinutes: 60,
      dominantIntensity: ActivityIntensity.high,
      activities: [],
      ringTrackedMinutes: 62,
      manualMinutes: 10,
    ),
    DailyActivitySummary(
      date: DateTime.now().subtract(const Duration(days: 6)),
      totalActiveMinutes: 25,
      goalMinutes: 45,
      dominantIntensity: ActivityIntensity.low,
      activities: [],
      ringTrackedMinutes: 25,
      manualMinutes: 0,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              _buildWeekSelector(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildSelectedDaySummary(),
                      const SizedBox(height: 16),
                      _buildWeeklyOverview(),
                      const SizedBox(height: 16),
                      _buildActivityList(),
                    ],
                  ),
                ),
              ),
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
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildWeekSelector() {
    final days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

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
            onTap: () {
              setState(() {
                _selectedDayIndex = 6 - index;
              });
            },
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
                      color: isSelected ? AppColors.textOnYellow : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dayData.date.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.textOnYellow : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dayData.goalMet
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

  Widget _buildSelectedDaySummary() {
    final selected = _weekData[_selectedDayIndex];
    final progress = selected.goalProgress.clamp(0.0, 1.0);

    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(selected.date),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Goal: ${selected.goalMinutes} min',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (selected.goalMet) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${selected.totalActiveMinutes}',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Text(
                    'minutes',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: AppColors.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(
                selected.goalMet ? AppColors.success : AppColors.primaryLemonDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.watch, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Ring: ${selected.ringTrackedMinutes} min',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.edit_note, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Manual: ${selected.manualMinutes} min',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              IntensityBadge(intensity: selected.dominantIntensity),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyOverview() {
    final totalMinutes = _weekData.fold<int>(0, (sum, d) => sum + d.totalActiveMinutes);
    final avgMinutes = (totalMinutes / 7).round();
    final goalsMet = _weekData.where((d) => d.goalMet).length;

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
                  label: 'Total Time',
                  value: '$totalMinutes min',
                  icon: Icons.timer,
                ),
              ),
              Expanded(
                child: _WeekStatItem(
                  label: 'Daily Avg',
                  value: '$avgMinutes min',
                  icon: Icons.show_chart,
                ),
              ),
              Expanded(
                child: _WeekStatItem(
                  label: 'Goals Met',
                  value: '$goalsMet/7 days',
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
    // Mock activities for selected day
    final activities = [
      ActivityRecord(
        id: '1',
        activityType: ActivityType.predefinedTypes[0],
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
        activityType: ActivityType.predefinedTypes[4],
        startTime: DateTime.now().subtract(const Duration(hours: 5)),
        endTime: DateTime.now().subtract(const Duration(hours: 4, minutes: 40)),
        durationMinutes: 20,
        intensity: ActivityIntensity.moderate,
        source: ActivitySource.ring,
        isEstimated: false,
        heartRateAvg: 92,
      ),
    ];

    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activities',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...activities.map((activity) => _buildActivityItem(activity)),
        ],
      ),
    );
  }

  Widget _buildActivityItem(ActivityRecord activity) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceLight),
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
                          style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${activity.durationMinutes} min',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (activity.intensity != null)
            IntensityBadge(
              intensity: activity.intensity!,
              isEstimated: activity.isEstimated,
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }
}

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
