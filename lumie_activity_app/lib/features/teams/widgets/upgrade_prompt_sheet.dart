// Upgrade Prompt Bottom Sheet - Shown when subscription limit is reached

import 'package:flutter/material.dart';
import '../../../shared/models/subscription_error.dart';

class UpgradePromptBottomSheet extends StatelessWidget {
  final String title;
  final String message;
  final String detail;
  final String actionLabel;
  final VoidCallback onUpgrade;

  const UpgradePromptBottomSheet({
    super.key,
    required this.title,
    required this.message,
    required this.detail,
    required this.actionLabel,
    required this.onUpgrade,
  });

  /// Factory constructor from SubscriptionErrorResponse
  factory UpgradePromptBottomSheet.fromError({
    required SubscriptionErrorResponse error,
    required VoidCallback onUpgrade,
  }) {
    return UpgradePromptBottomSheet(
      title: 'Upgrade to Pro',
      message: error.message,
      detail: error.detail,
      actionLabel: error.action.label,
      onUpgrade: onUpgrade,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.amber[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.workspace_premium,
              size: 48,
              color: Colors.amber[700],
            ),
          ),

          const SizedBox(height: 24),

          // Title
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // Message
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Detail
          Text(
            detail,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Upgrade button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onUpgrade,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Not now button
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Not Now',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper method to show the bottom sheet from error response
  static void show({
    required BuildContext context,
    required SubscriptionErrorResponse error,
    required VoidCallback onUpgrade,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UpgradePromptBottomSheet.fromError(
        error: error,
        onUpgrade: () {
          Navigator.of(context).pop();
          onUpgrade();
        },
      ),
    );
  }

  /// Helper method to show the bottom sheet with custom content
  static void showCustom({
    required BuildContext context,
    required String title,
    required String message,
    required String detail,
    String actionLabel = 'Upgrade to Pro',
    required VoidCallback onUpgrade,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UpgradePromptBottomSheet(
        title: title,
        message: message,
        detail: detail,
        actionLabel: actionLabel,
        onUpgrade: () {
          Navigator.of(context).pop();
          onUpgrade();
        },
      ),
    );
  }
}
