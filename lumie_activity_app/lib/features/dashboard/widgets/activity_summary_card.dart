import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_card.dart';

/// Card showing activity time breakdown
class ActivitySummaryCard extends StatelessWidget {
  final int ringTrackedMinutes;
  final int manualMinutes;
  final int activitiesCount;

  const ActivitySummaryCard({
    super.key,
    required this.ringTrackedMinutes,
    required this.manualMinutes,
    required this.activitiesCount,
  });

  int get totalMinutes => ringTrackedMinutes + manualMinutes;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activity Time Breakdown',
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
                child: _StatItem(
                  icon: Icons.watch,
                  label: 'Ring Tracked',
                  value: '$ringTrackedMinutes min',
                  gradient: AppColors.mintGradient,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatItem(
                  icon: Icons.edit_note,
                  label: 'Manual',
                  value: '$manualMinutes min',
                  gradient: AppColors.coolGradient,
                  isEstimated: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildProgressBar(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$activitiesCount activities recorded',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                'Total: $totalMinutes min',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final ringPercent = totalMinutes > 0 ? ringTrackedMinutes / totalMinutes : 0.0;

    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            flex: (ringPercent * 100).toInt(),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF80CBC4), Color(0xFF4DB6AC)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Expanded(
            flex: ((1 - ringPercent) * 100).toInt(),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF90CAF9), Color(0xFF64B5F6)],
                ),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Gradient gradient;
  final bool isEstimated;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    this.isEstimated = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: AppColors.textOnYellow,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textOnYellow,
                ),
              ),
              if (isEstimated) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.info_outline,
                  size: 12,
                  color: AppColors.textSecondary,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textOnYellow,
            ),
          ),
        ],
      ),
    );
  }
}
