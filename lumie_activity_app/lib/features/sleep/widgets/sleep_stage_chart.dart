import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/sleep_models.dart';

class SleepStageChart extends StatelessWidget {
  final SleepSession session;

  const SleepStageChart({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Horizontal bar chart showing sleep stages
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                flex: (session.getStagePercentage(SleepStage.light) * 100).round(),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primaryLemon,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: (session.getStagePercentage(SleepStage.deep) * 100).round(),
                child: Container(
                  color: AppColors.accentMint,
                ),
              ),
              Expanded(
                flex: (session.getStagePercentage(SleepStage.rem) * 100).round(),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.accentLavender,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Time labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatTime(session.bedtime),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textLight,
              ),
            ),
            Text(
              _formatTime(session.wakeTime),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
