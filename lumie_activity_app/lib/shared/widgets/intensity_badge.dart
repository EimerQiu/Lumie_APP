import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../models/activity_models.dart';

/// Badge widget for displaying activity intensity
class IntensityBadge extends StatelessWidget {
  final ActivityIntensity intensity;
  final bool isEstimated;
  final bool showLabel;
  final double? size;

  const IntensityBadge({
    super.key,
    required this.intensity,
    this.isEstimated = false,
    this.showLabel = true,
    this.size,
  });

  Color get backgroundColor {
    switch (intensity) {
      case ActivityIntensity.low:
        return AppColors.intensityLow;
      case ActivityIntensity.moderate:
        return AppColors.intensityModerate;
      case ActivityIntensity.high:
        return AppColors.intensityHigh;
    }
  }

  Gradient get gradient {
    switch (intensity) {
      case ActivityIntensity.low:
        return const LinearGradient(
          colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
        );
      case ActivityIntensity.moderate:
        return const LinearGradient(
          colors: [Color(0xFFFFFDE7), Color(0xFFFFF59D)],
        );
      case ActivityIntensity.high:
        return const LinearGradient(
          colors: [Color(0xFFFFECB3), Color(0xFFFFCC80)],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size != null ? size! / 2 : 12,
        vertical: size != null ? size! / 4 : 6,
      ),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: backgroundColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLabel)
            Text(
              intensity.displayName,
              style: TextStyle(
                fontSize: size != null ? size! / 2 : 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnYellow,
              ),
            ),
          if (isEstimated) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.edit_outlined,
              size: size != null ? size! / 2 : 12,
              color: AppColors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Visual indicator for all intensity levels
class IntensityIndicator extends StatelessWidget {
  final ActivityIntensity? currentIntensity;
  final bool isSelectable;
  final ValueChanged<ActivityIntensity>? onSelected;

  const IntensityIndicator({
    super.key,
    this.currentIntensity,
    this.isSelectable = false,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: ActivityIntensity.values.map((intensity) {
        final isSelected = currentIntensity == intensity;
        return GestureDetector(
          onTap: isSelectable ? () => onSelected?.call(intensity) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        _getColor(intensity),
                        _getColor(intensity).withValues(alpha: 0.7),
                      ],
                    )
                  : null,
              color: isSelected ? null : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _getColor(intensity) : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _getColor(intensity).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(
                  _getIcon(intensity),
                  color: isSelected ? AppColors.textOnYellow : AppColors.textSecondary,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  intensity.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? AppColors.textOnYellow : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getColor(ActivityIntensity intensity) {
    switch (intensity) {
      case ActivityIntensity.low:
        return AppColors.intensityLow;
      case ActivityIntensity.moderate:
        return AppColors.primaryLemonDark;
      case ActivityIntensity.high:
        return AppColors.accentOrange;
    }
  }

  IconData _getIcon(ActivityIntensity intensity) {
    switch (intensity) {
      case ActivityIntensity.low:
        return Icons.directions_walk;
      case ActivityIntensity.moderate:
        return Icons.directions_run;
      case ActivityIntensity.high:
        return Icons.sports;
    }
  }
}
