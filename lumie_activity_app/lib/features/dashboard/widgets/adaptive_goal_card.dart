import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_card.dart';

/// Card displaying adaptive activity goal with a gamified progress bar
class AdaptiveGoalCard extends StatelessWidget {
  final int recommendedMinutes;
  final int currentMinutes;
  final String reason;
  final bool isReduced;
  final List<String> factors;

  const AdaptiveGoalCard({
    super.key,
    required this.recommendedMinutes,
    required this.currentMinutes,
    required this.reason,
    required this.isReduced,
    required this.factors,
  });

  double get _progress =>
      (currentMinutes / recommendedMinutes).clamp(0.0, 1.0);

  String get _rankLabel {
    if (_progress >= 1.0) return 'Champion! 🏆';
    if (_progress >= 0.66) return 'Almost there!';
    if (_progress >= 0.33) return 'Keep going!';
    return 'Get started!';
  }

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
          _buildHeader(),
          const SizedBox(height: 16),
          _buildGameProgressBar(),
          const SizedBox(height: 16),
          _buildReasonBox(),
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

  Widget _buildHeader() {
    return Row(
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
            isReduced ? Icons.self_improvement : Icons.emoji_events,
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
                isReduced ? 'Rest Day Goal' : 'Today\'s Goal',
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
                Icon(Icons.arrow_downward, size: 14, color: AppColors.accentLavender),
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
    );
  }

  Widget _buildGameProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _rankLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '$currentMinutes / $recommendedMinutes min',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Progress track
        SizedBox(
          height: 32,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Background track
              Container(
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              // Filled portion
              LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  final filledWidth = barWidth * _progress;
                  return Container(
                    height: 16,
                    width: filledWidth.clamp(16.0, barWidth),
                    decoration: BoxDecoration(
                      gradient: isReduced
                          ? const LinearGradient(
                              colors: [Color(0xFFCE93D8), Color(0xFFBA68C8)],
                            )
                          : const LinearGradient(
                              colors: [
                                Color(0xFFFFEB3B),
                                Color(0xFFFFC107),
                                Color(0xFFFF9800),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryLemonDark.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Milestone markers at 33% and 66%
              LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  return Stack(
                    children: [
                      _buildMilestone(barWidth * 0.33, '⚡', _progress >= 0.33),
                      _buildMilestone(barWidth * 0.66, '⭐', _progress >= 0.66),
                    ],
                  );
                },
              ),
              // Trophy at the end
              Positioned(
                right: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: _progress >= 1.0
                        ? const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFFE0E0E0), Color(0xFFBDBDBD)],
                          ),
                    shape: BoxShape.circle,
                    boxShadow: _progress >= 1.0
                        ? [
                            BoxShadow(
                              color: Colors.amber.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: const Center(
                    child: Text('🏆', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Milestone labels
        Row(
          children: [
            const Spacer(),
            _MilestoneLabel(label: 'Starter', fraction: 0.0, progress: _progress),
            const Spacer(),
            _MilestoneLabel(label: 'Active', fraction: 0.33, progress: _progress),
            const Spacer(),
            _MilestoneLabel(label: 'Pro', fraction: 0.66, progress: _progress),
            const Spacer(),
            _MilestoneLabel(label: 'Champion', fraction: 1.0, progress: _progress),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildMilestone(double left, String emoji, bool reached) {
    return Positioned(
      left: left - 12,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: reached
              ? AppColors.backgroundWhite
              : AppColors.backgroundWhite.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(
            color: reached ? AppColors.primaryLemonDark : AppColors.surfaceLight,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(
              fontSize: 12,
              color: reached ? null : const Color(0x88000000),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReasonBox() {
    return Container(
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
            children: factors.map((f) => _FactorChip(factor: f)).toList(),
          ),
        ],
      ),
    );
  }
}

class _MilestoneLabel extends StatelessWidget {
  final String label;
  final double fraction;
  final double progress;

  const _MilestoneLabel({
    required this.label,
    required this.fraction,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final reached = progress >= fraction;
    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: reached ? FontWeight.w600 : FontWeight.normal,
        color: reached ? AppColors.textOnYellow : AppColors.textLight,
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
          Icon(_icon, size: 14, color: AppColors.textOnYellow),
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
