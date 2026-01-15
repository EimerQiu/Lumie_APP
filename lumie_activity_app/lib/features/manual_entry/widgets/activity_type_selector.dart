import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';

/// Widget for selecting activity type from predefined list
class ActivityTypeSelector extends StatelessWidget {
  final ActivityType? selectedType;
  final ValueChanged<ActivityType> onTypeSelected;

  const ActivityTypeSelector({
    super.key,
    this.selectedType,
    required this.onTypeSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Group activities by category
    final groupedTypes = <String, List<ActivityType>>{};
    for (final type in ActivityType.predefinedTypes) {
      groupedTypes.putIfAbsent(type.category, () => []).add(type);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groupedTypes.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 8),
              child: Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.value.map((type) {
                final isSelected = selectedType?.id == type.id;
                return _ActivityTypeChip(
                  type: type,
                  isSelected: isSelected,
                  onTap: () => onTypeSelected(type),
                );
              }).toList(),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _ActivityTypeChip extends StatelessWidget {
  final ActivityType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _ActivityTypeChip({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.progressGradient : null,
          color: isSelected ? null : AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.primaryLemonDark : AppColors.surfaceLight,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryLemon.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              type.icon,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 6),
            Text(
              type.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.textOnYellow : AppColors.textPrimary,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.check_circle,
                size: 16,
                color: AppColors.textOnYellow,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
