import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Quick actions section for easy navigation
class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.add_circle_outline,
                  label: 'Log Activity',
                  gradient: AppColors.warmGradient,
                  onTap: () {
                    // Navigate to manual entry
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.directions_walk,
                  label: '6-Min Walk',
                  gradient: AppColors.mintGradient,
                  onTap: () {
                    // Navigate to walk test
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.history,
                  label: 'History',
                  gradient: AppColors.coolGradient,
                  onTap: () {
                    // Navigate to history
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.insights,
                  label: 'Insights',
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
                  ),
                  onTap: () {
                    // Navigate to insights
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryLemon.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: AppColors.textOnYellow,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnYellow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
