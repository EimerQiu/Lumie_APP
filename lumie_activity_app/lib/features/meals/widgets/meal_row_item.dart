// MealRowItem — list row for the home screen's "Logged meals" section.
//
// Layout:
//   ┌──────────────────────────────────────────┐
//   │  [thumb]   Salmon, Greens, Rice          │
//   │            Breakfast at 07:00            │
//   │                                           │
//   │   ━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━        │
//   └──────────────────────────────────────────┘
//
// The slider is the compact NutritionLevelSlider (no labels) so the level
// is immediately readable at a glance.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';
import 'meal_card.dart' show mealImageUrl;
import 'nutrition_level_slider.dart';

class MealRowItem extends StatelessWidget {
  final Meal meal;
  final VoidCallback? onTap;

  const MealRowItem({
    super.key,
    required this.meal,
    this.onTap,
  });

  String get _foodPreview {
    if (meal.foodItems.isEmpty) return meal.displayName;
    return meal.foodItems.map((f) => f.name).join(', ');
  }

  String get _mealTypeAndTime {
    final type = meal.mealType?.displayName ?? 'Meal';
    final dt = meal.effectiveTime.toLocal();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$type at $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final firstImage = meal.images.isNotEmpty
        ? (meal.images.first.thumbnailUrl ?? meal.images.first.url)
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: firstImage != null
                            ? Image.network(
                                mealImageUrl(firstImage),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _placeholder(),
                              )
                            : _placeholder(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _foodPreview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _mealTypeAndTime,
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
                const SizedBox(height: 14),
                NutritionLevelSlider(
                  level: meal.nutritionLevel ?? NutritionLevel.fair,
                  compact: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.primaryLemonLight,
      alignment: Alignment.center,
      child: const Icon(
        Icons.restaurant,
        color: AppColors.primaryLemonDark,
        size: 24,
      ),
    );
  }
}
