import 'package:flutter/material.dart';
import '../../../shared/models/task_models.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback? onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;

  const TaskCard({
    super.key,
    required this.task,
    this.onTap,
    this.onComplete,
    this.onDelete,
  });

  /// Color pairs for progress gradient (from Automom)
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

  /// Light grey card base color (adapted for white background)
  static const Color _cardBase = Color(0xFFF0F0F0);

  @override
  Widget build(BuildContext context) {
    final gradientColors =
        _gradientPairs[task.taskId.hashCode.abs() % _gradientPairs.length];

    return Dismissible(
      key: Key(task.taskId),
      background: _buildSwipeBackground(
        color: Colors.green,
        icon: Icons.check_circle,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _buildSwipeBackground(
        color: Colors.red,
        icon: Icons.delete,
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onComplete?.call();
          return false;
        } else {
          return await _showDeleteConfirm(context);
        }
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onDelete?.call();
        }
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
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
                // Gradient progress fill (Automom style - fills from left)
                Positioned.fill(
                  child: FractionallySizedBox(
                    widthFactor: task.progress,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      // Left: Open time (rotated 90°)
                      _buildRotatedTime(task.openDatetime),
                      // Center: Task name
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              task.taskName,
                              style: const TextStyle(
                                fontSize: 18,
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
                      _buildRotatedTime(task.closeDatetime),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rotated time display (90° like Automom)
  /// Shows time (HH:MM) if today, or date (MM/DD) if not today
  /// Times from backend are in UTC and need to be converted to local time for display
  Widget _buildRotatedTime(String dateTimeStr) {
    String timeText;
    try {
      // Parse the UTC time string and convert to local time
      // Format is "YYYY-MM-DD HH:MM" in UTC
      final utcDateTime = DateTime.parse(dateTimeStr.replaceAll(' ', 'T') + 'Z').toLocal();

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
        // Show MM/DD for non-today dates
        timeText = '$localMonth/$localDay';
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
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeBackground({
    required Color color,
    required IconData icon,
    required Alignment alignment,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }

  Future<bool> _showDeleteConfirm(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Task'),
            content:
                Text('Are you sure you want to delete "${task.taskName}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
