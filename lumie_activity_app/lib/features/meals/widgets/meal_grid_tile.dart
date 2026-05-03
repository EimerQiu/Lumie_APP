// MealGridTile — square, image-first tile for the personal history grid.
//
// Photo dominates the upper portion (square crop). Below: a 2-line food
// preview and a compact macro-dot strip. Used in MealsHomeScreen's GridView.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';
import 'macro_ratio_widget.dart';
import 'meal_card.dart' show mealImageUrl;

class MealGridTile extends StatelessWidget {
  final Meal meal;
  final VoidCallback? onTap;

  const MealGridTile({
    super.key,
    required this.meal,
    this.onTap,
  });

  String get _foodPreview {
    if (meal.foodItems.isEmpty) return 'Meal';
    return meal.foodItems.take(3).map((f) => f.name).join(' · ');
  }

  String get _dateLabel {
    final dt = meal.createdAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mealDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(mealDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final firstImage = meal.images.isNotEmpty
        ? (meal.images.first.thumbnailUrl ?? meal.images.first.url)
        : null;

    return Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (firstImage != null)
                        Image.network(
                          mealImageUrl(firstImage),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      else
                        _placeholder(),
                      if (meal.isTeamMeal)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _badge('Team'),
                        ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: _badge(_dateLabel, dim: true),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _foodPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
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
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.primaryLemonLight,
      alignment: Alignment.center,
      child: const Icon(
        Icons.restaurant,
        color: AppColors.primaryLemonDark,
        size: 36,
      ),
    );
  }

  Widget _badge(String label, {bool dim = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: dim ? Colors.black54 : AppColors.primaryLemonDark,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
