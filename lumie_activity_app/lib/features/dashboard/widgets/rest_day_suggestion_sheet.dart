import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rest_days_service.dart';
import '../../../shared/models/rest_days_models.dart';
import '../../../shared/widgets/gradient_card.dart';

/// Bottom sheet for suggesting a rest day based on poor sleep quality.
class RestDaySuggestionSheet extends StatelessWidget {
  final RestDaySuggestion suggestion;
  final VoidCallback onAccept;

  const RestDaySuggestionSheet({
    super.key,
    required this.suggestion,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppColors.coolGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryLemonDark.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.bedtime_outlined,
              size: 48,
              color: AppColors.textOnYellow,
            ),
          ),
          const SizedBox(height: 24),

          // Title
          const Text(
            'Poor Sleep Detected',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Sleep quality indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.nights_stay,
                  size: 20,
                  color: AppColors.error,
                ),
                const SizedBox(width: 8),
                Text(
                  'Sleep Quality: ${suggestion.sleepQuality.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Message
          Text(
            suggestion.message,
            style: const TextStyle(
              fontSize: 17,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Set Rest Day button
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              text: 'Set Today as Rest Day',
              onPressed: onAccept,
              icon: Icons.check_circle_outline,
              gradient: AppColors.coolGradient,
            ),
          ),
          const SizedBox(height: 12),

          // Dismiss button
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Not Today',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Show the rest day suggestion bottom sheet.
  static void show({
    required BuildContext context,
    required RestDaySuggestion suggestion,
  }) {
    if (!suggestion.shouldSuggest) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RestDaySuggestionSheet(
        suggestion: suggestion,
        onAccept: () async {
          Navigator.of(context).pop();

          try {
            await RestDaysService().setTodayAsRestDay();

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Today set as rest day'),
                  backgroundColor: AppColors.primaryLemonDark,
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to set rest day'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        },
      ),
    );
  }
}
