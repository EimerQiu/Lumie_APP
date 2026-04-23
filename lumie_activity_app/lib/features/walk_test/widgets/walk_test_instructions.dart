import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_card.dart';

/// Instructions for the 6-minute walk test
class WalkTestInstructions extends StatelessWidget {
  const WalkTestInstructions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GradientCard(
          gradient: AppColors.cardGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppColors.warmGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.directions_walk,
                      color: AppColors.textOnYellow,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '6-Minute Walk Test',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Functional fitness check-in',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'This test measures how far you can walk in 6 minutes. It helps you track your functional fitness over time.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GradientCard(
          gradient: AppColors.cardGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Before You Start',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _InstructionItem(
                number: '1',
                title: 'Find a flat path',
                description: 'Choose a flat, unobstructed walking path (hallway, track, etc.)',
                icon: Icons.straighten,
              ),
              _InstructionItem(
                number: '2',
                title: 'Wear comfortable shoes',
                description: 'Make sure you\'re wearing comfortable walking shoes',
                icon: Icons.directions_walk,
              ),
              _InstructionItem(
                number: '3',
                title: 'Rest if needed',
                description: 'You can slow down or stop if you need to rest',
                icon: Icons.self_improvement,
              ),
              _InstructionItem(
                number: '4',
                title: 'Keep your ring on',
                description: 'Your Lumie Ring will track your heart rate automatically',
                icon: Icons.watch,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GradientCard(
          gradient: const LinearGradient(
            colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
          ),
          child: const Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.success,
                size: 20,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Walk at your own pace. This is not a race - the goal is to see how far you can comfortably walk.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textOnYellow,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InstructionItem extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final IconData icon;

  const _InstructionItem({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppColors.progressGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textOnYellow,
                ),
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
                    Icon(
                      icon,
                      size: 16,
                      color: AppColors.primaryLemonDark,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
