// MacroContinuousBar — smooth continuous fill bar for the Nutrition Breakdown.
//
// The fill runs from the left edge to the position given by [score] (0.0–1.0).
// Three zone labels — Low · Moderate · High — are shown below the bar as
// reference markers so the user can still read the general zone.
//
// The level label (Low / Moderate / High) is shown on the right side of the
// header row in the same colour as the fill, unchanged from the previous design.
//
// Score-to-visual mapping (from the spec):
//   0.0–0.33  Low
//   0.34–0.66 Moderate
//   0.67–1.0  High
//
// When [score] is null the widget derives an approximate position from [level]:
//   low → 0.17  ·  moderate → 0.50  ·  high → 0.83

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';

class MacroSegmentedBar extends StatelessWidget {
  /// Macro label shown on the left (e.g. "Protein").
  final String label;

  /// Current categorical rating (Low / Moderate / High) — still shown as
  /// the text label on the right and used as a fallback when [score] is null.
  final MacroLevel level;

  /// Continuous fill position on a 0.0–1.0 scale. When provided the bar fills
  /// to this exact fraction; when null it falls back to the centre of [level].
  final double? score;

  /// Fill and label colour — pass the meal's `nutritionLevel.color` so all
  /// six rows share the warm hue derived from the overall meal tier.
  final Color? fillColor;

  const MacroSegmentedBar({
    super.key,
    required this.label,
    required this.level,
    this.score,
    this.fillColor,
  });

  double get _effectiveScore {
    final s = score;
    if (s != null) return s.clamp(0.0, 1.0);
    return const {
      MacroLevel.low: 0.17,
      MacroLevel.moderate: 0.50,
      MacroLevel.high: 0.83,
    }[level]!;
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = fillColor ?? AppColors.primaryLemonDark;
    final fill = _effectiveScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header: label left, categorical level right
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              level.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: activeColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Continuous fill track
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final fillWidth = (trackWidth * fill).clamp(0.0, trackWidth);
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    // Empty track
                    Container(
                      width: trackWidth,
                      color: AppColors.surfaceLight,
                    ),
                    // Filled portion
                    Container(
                      width: fillWidth,
                      color: activeColor,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        // Zone reference markers below the track
        const Row(
          children: [
            Text(
              'Low',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textLight,
                letterSpacing: 0.2,
              ),
            ),
            Spacer(),
            Text(
              'Moderate',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textLight,
                letterSpacing: 0.2,
              ),
            ),
            Spacer(),
            Text(
              'High',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textLight,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
