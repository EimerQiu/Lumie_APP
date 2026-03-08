import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../tasks/providers/tasks_provider.dart';

class ActiveTasksCard extends StatelessWidget {
  const ActiveTasksCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TasksProvider>(
      builder: (context, provider, _) {
        // Hide completely when: never loaded, loading with no data, or empty
        if (provider.state == TasksState.initial) return const SizedBox.shrink();
        if (provider.isLoading && provider.activeTasks.isEmpty) {
          return const SizedBox.shrink();
        }
        if (provider.activeTasks.isEmpty) return const SizedBox.shrink();

        final tasks = provider.activeTasks;
        final displayTasks = tasks.take(3).toList();
        final extraCount = tasks.length - displayTasks.length;

        return GradientCard(
          gradient: AppColors.cardGradient,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, tasks.length),
              const SizedBox(height: 12),
              ...displayTasks.map((t) => _TaskRowItem(task: t)),
              if (extraCount > 0) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/tasks'),
                  child: Text(
                    '... and $extraCount more',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryLemonDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Row(
      children: [
        const Text(
          'Med-Reminder',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/tasks'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryLemonDark,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'See All',
            style: TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _TaskRowItem extends StatelessWidget {
  final Task task;

  const _TaskRowItem({required this.task});

  /// Gradient color pairs (from TaskCard)
  static const List<List<Color>> _gradientPairs = [
    [Color(0xFFFF3B30), Color(0xFFFF2D55)], // Red -> Pink
    [Color(0xFF007AFF), Color(0xFF5AC8FA)], // Blue -> Teal
    [Color(0xFFFF3B30), Color(0xFFFF9500)], // Red -> Orange
    [Color(0xFF34C759), Color(0xFFFFCC00)], // Green -> Yellow
    [Color(0xFFFF2D55), Color(0xFF5856D6)], // Pink -> Purple
    [Color(0xFF5AC8FA), Color(0xFF34C759)], // Teal -> Green
    [Color(0xFF007AFF), Color(0xFF5856D6)], // Blue -> Purple
    [Color(0xFFFF9500), Color(0xFFFFCC00)], // Orange -> Yellow
    [Color(0xFFFF2D55), Color(0xFFFF3B30)], // Pink -> Red
    [Color(0xFF5AC8FA), Color(0xFF007AFF)], // Teal -> Blue
    [Color(0xFFFF9500), Color(0xFFFF3B30)], // Orange -> Red
    [Color(0xFFFFCC00), Color(0xFF34C759)], // Yellow -> Green
    [Color(0xFF5856D6), Color(0xFFFF2D55)], // Purple -> Pink
    [Color(0xFF34C759), Color(0xFF5AC8FA)], // Green -> Teal
    [Color(0xFF5856D6), Color(0xFF007AFF)], // Purple -> Blue
    [Color(0xFFFFCC00), Color(0xFFFF9500)], // Yellow -> Orange
  ];

  static const Color _cardBase = Color(0xFFF0F0F0);

  @override
  Widget build(BuildContext context) {
    final gradientColors =
        _gradientPairs[task.taskId.hashCode.abs() % _gradientPairs.length];

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/tasks'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 55,
        decoration: BoxDecoration(
          color: _cardBase,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Gradient progress fill (fills from left)
              Positioned.fill(
                child: FractionallySizedBox(
                  widthFactor: task.progress,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          gradientColors[0].withValues(alpha: 0.65),
                          gradientColors[1].withValues(alpha: 0.65),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  children: [
                    // Left: Open time (rotated 90°)
                    _buildRotatedTime(task.openDatetime, isEnd: false),
                    // Center: Task name
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            task.taskName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1917),
                            ),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Right: Close time (rotated 90°)
                    _buildRotatedTime(task.closeDatetime, isEnd: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rotated time display (90° like TaskCard)
  /// Shows time (HH:MM) if today, or date (MM/DD) if not today
  Widget _buildRotatedTime(String dateTimeStr, {bool isEnd = false}) {
    String timeText;
    try {
      final utcDateTime =
          DateTime.parse(dateTimeStr.replaceAll(' ', 'T') + 'Z').toLocal();

      final localYear = utcDateTime.year;
      final localMonth = utcDateTime.month.toString().padLeft(2, '0');
      final localDay = utcDateTime.day.toString().padLeft(2, '0');
      final localHour = utcDateTime.hour.toString().padLeft(2, '0');
      final localMinute = utcDateTime.minute.toString().padLeft(2, '0');

      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final displayDateStr = '$localYear-$localMonth-$localDay';

      if (displayDateStr == todayStr) {
        timeText = '$localHour:$localMinute'; // HH:MM
      } else {
        timeText = '$localMonth/$localDay'; // MM/DD
      }
    } catch (_) {
      timeText = dateTimeStr;
    }

    return SizedBox(
      width: 35,
      height: 46,
      child: Center(
        child: RotatedBox(
          quarterTurns: 1,
          child: Text(
            timeText,
            style: TextStyle(
              fontSize: 10,
              color: isEnd ? const Color(0xFF666666) : Colors.white,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}
