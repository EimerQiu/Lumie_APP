// MealCard — compact card for grids/lists (personal history + team feed).
// Shows the first image, food names preview, and macro dots.

import 'package:flutter/material.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';
import 'macro_ratio_widget.dart';

/// Convert a relative upload path to a fully-qualified URL.
/// Backend paths look like `/api/v1/uploads/meals/...`; prepend the host.
String mealImageUrl(String raw) {
  if (raw.isEmpty) return raw;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  final origin = Uri.parse(ApiConstants.baseUrl).origin;
  final path = raw.startsWith('/') ? raw : '/$raw';
  return '$origin$path';
}

class MealCard extends StatelessWidget {
  final Meal meal;
  final VoidCallback? onTap;
  final bool showAuthor;

  const MealCard({
    super.key,
    required this.meal,
    this.onTap,
    this.showAuthor = false,
  });

  String get _foodPreview {
    if (meal.foodItems.isEmpty) return 'Meal';
    final names = meal.foodItems.take(3).map((f) => f.name).toList();
    final preview = names.join(' · ');
    if (meal.foodItems.length > 3) {
      return '$preview · +${meal.foodItems.length - 3}';
    }
    return preview;
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
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 88,
                    height: 88,
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
                    children: [
                      if (showAuthor && (meal.userName ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            meal.userName!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      Text(
                        _foodPreview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MacroRatioBar(ratio: meal.macroRatio, compact: true),
                    ],
                  ),
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
      child: const Icon(
        Icons.restaurant,
        color: AppColors.primaryLemonDark,
        size: 32,
      ),
    );
  }
}
