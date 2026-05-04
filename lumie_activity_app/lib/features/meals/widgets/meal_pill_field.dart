// MealPillField — tappable two-line pill used for Meal Type and Time on
// both the Log Meal screen and the Meal Detail screen. Small label on top,
// gold icon + value row beneath, with a chevron when interactive.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class MealPillField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  /// When true (default), shows the chevron. Pass false to render a static,
  /// non-tappable display variant.
  final bool enabled;

  const MealPillField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primaryLemonDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (enabled)
                  const Icon(Icons.expand_more,
                      size: 18, color: AppColors.textLight),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
