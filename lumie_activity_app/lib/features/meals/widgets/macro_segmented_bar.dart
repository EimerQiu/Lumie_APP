// MacroSegmentedBar — three-segment bar for a single macro (Low | Moderate | High).
//
// Slice 7A §2: fill is CUMULATIVE from the left:
//   Low      → segment 1 filled
//   Moderate → segments 1 + 2 filled
//   High     → all 3 segments filled
//
// Slice 7A §3: filled segments use the meal's NutritionLevel colour (passed in
// via [fillColor]) so all six breakdown rows share a single warm hue derived
// from the overall meal tier.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';

class MacroSegmentedBar extends StatelessWidget {
  /// Macro label shown on the left (e.g. "Protein").
  final String label;

  /// Current rating of this macro (Low / Moderate / High).
  final MacroLevel level;

  /// Colour used for the filled segments. Defaults to the gold accent. The
  /// detail-screen breakdown passes the meal's `nutritionLevel.color` so the
  /// six rows visually align with the overall meal tier (Slice 7A §3).
  final Color? fillColor;

  /// Optional callback — when set, the user can tap a segment to override
  /// the level (used in the detail-screen edit mode).
  final ValueChanged<MacroLevel>? onLevelChanged;

  const MacroSegmentedBar({
    super.key,
    required this.label,
    required this.level,
    this.fillColor,
    this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = fillColor ?? AppColors.primaryLemonDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        _SegmentRow(
          level: level,
          fillColor: activeColor,
          onLevelChanged: onLevelChanged,
        ),
      ],
    );
  }
}

class _SegmentRow extends StatelessWidget {
  final MacroLevel level;
  final Color fillColor;
  final ValueChanged<MacroLevel>? onLevelChanged;

  const _SegmentRow({
    required this.level,
    required this.fillColor,
    this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _segment(MacroLevel.low, isFirst: true)),
        const SizedBox(width: 4),
        Expanded(child: _segment(MacroLevel.moderate)),
        const SizedBox(width: 4),
        Expanded(child: _segment(MacroLevel.high, isLast: true)),
      ],
    );
  }

  Widget _segment(MacroLevel segment, {bool isFirst = false, bool isLast = false}) {
    // Cumulative fill: a segment is active if its position is <= the current
    // level's position. Enum is declared low → moderate → high so .index works.
    final active = segment.index <= level.index;
    final radius = BorderRadius.horizontal(
      left: isFirst ? const Radius.circular(8) : Radius.zero,
      right: isLast ? const Radius.circular(8) : Radius.zero,
    );
    final inner = Container(
      height: 8,
      decoration: BoxDecoration(
        color: active ? fillColor : AppColors.surfaceLight,
        borderRadius: radius,
      ),
    );
    final tap = onLevelChanged;
    if (tap == null) return inner;
    return InkWell(
      onTap: () => tap(segment),
      borderRadius: radius,
      child: inner,
    );
  }
}
