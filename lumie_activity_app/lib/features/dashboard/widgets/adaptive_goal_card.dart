import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_card.dart';

/// Card displaying adaptive activity goal information
class AdaptiveGoalCard extends StatelessWidget {
  final int recommendedMinutes;
  final String reason;
  final bool isReduced;
  final List<String> factors;

  const AdaptiveGoalCard({
    super.key,
    required this.recommendedMinutes,
    required this.reason,
    required this.isReduced,
    required this.factors,
  });

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      gradient: isReduced
          ? const LinearGradient(
              colors: [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
            )
          : AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: isReduced
                      ? const LinearGradient(
                          colors: [Color(0xFFCE93D8), Color(0xFFBA68C8)],
                        )
                      : AppColors.progressGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isReduced ? Icons.self_improvement : Icons.flag_outlined,
                  color: AppColors.textOnYellow,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isReduced ? 'Adjusted Goal Today' : 'Today\'s Goal',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$recommendedMinutes minutes',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isReduced)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accentLavender.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_downward,
                        size: 14,
                        color: AppColors.accentLavender,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Rest Day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.accentLavender,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.backgroundWhite.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: AppColors.primaryLemonDark,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Why this goal?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: factors.map((factor) => _FactorChip(factor: factor)).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'This is a suggestion, not a requirement. Listen to your body.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactorChip extends StatelessWidget {
  final String factor;

  const _FactorChip({required this.factor});

  IconData get _icon {
    if (factor.toLowerCase().contains('sleep')) return Icons.bedtime_outlined;
    if (factor.toLowerCase().contains('activity')) return Icons.directions_run;
    if (factor.toLowerCase().contains('fatigue')) return Icons.battery_alert;
    if (factor.toLowerCase().contains('recovery')) return Icons.healing;
    return Icons.check_circle_outline;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: AppColors.warmGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icon,
            size: 14,
            color: AppColors.textOnYellow,
          ),
          const SizedBox(width: 4),
          Text(
            factor,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textOnYellow,
            ),
          ),
        ],
      ),
    );
  }
}
