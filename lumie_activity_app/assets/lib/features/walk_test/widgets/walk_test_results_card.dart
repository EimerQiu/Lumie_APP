import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/widgets/gradient_card.dart';

/// Card displaying walk test results
class WalkTestResultsCard extends StatelessWidget {
  final WalkTestResult result;
  final WalkTestResult? previousBest;

  const WalkTestResultsCard({
    super.key,
    required this.result,
    this.previousBest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Success header
        GradientCard(
          gradient: const LinearGradient(
            colors: [Color(0xFFE8F5E9), Color(0xFFA5D6A7)],
          ),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF81C784), Color(0xFF4CAF50)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Test Complete!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Great job! Here are your results.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Main result - Distance
        GradientCard(
          gradient: AppColors.sunriseGradient,
          child: Column(
            children: [
              const Text(
                'Distance Walked',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textOnYellow,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    result.distanceMeters.toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textOnYellow,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'meters',
                    style: TextStyle(
                      fontSize: 20,
                      color: AppColors.textOnYellow,
                    ),
                  ),
                ],
              ),
              if (previousBest != null) ...[
                const SizedBox(height: 8),
                _buildComparison(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Heart rate metrics
        GradientCard(
          gradient: AppColors.cardGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Heart Rate Data',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MetricItem(
                      icon: Icons.favorite_outline,
                      label: 'Average',
                      value: '${result.avgHeartRate ?? '--'} bpm',
                      color: AppColors.error,
                    ),
                  ),
                  Expanded(
                    child: _MetricItem(
                      icon: Icons.favorite,
                      label: 'Max',
                      value: '${result.maxHeartRate ?? '--'} bpm',
                      color: AppColors.error,
                    ),
                  ),
                  Expanded(
                    child: _MetricItem(
                      icon: Icons.monitor_heart_outlined,
                      label: 'Recovery',
                      value: '${result.recoveryHeartRate ?? '--'} bpm',
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Duration
        GradientCard(
          gradient: AppColors.cardGradient,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: AppColors.primaryLemonDark,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Test Duration',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                _formatDuration(result.durationSeconds),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComparison() {
    final diff = result.distanceMeters - previousBest!.distanceMeters;
    final isImproved = diff >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isImproved
            ? AppColors.success.withValues(alpha: 0.2)
            : AppColors.textLight.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isImproved ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: isImproved ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            '${diff.abs().toStringAsFixed(0)}m vs your best',
            style: TextStyle(
              fontSize: 12,
              color: isImproved ? AppColors.success : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }
}

class _MetricItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
