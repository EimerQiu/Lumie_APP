// MacroSegmentedBar — three-segment bar for a single macro (Low | Moderate | High).
// Active segment is filled gold, others are light gray. Used in the
// detail-screen Nutrition Breakdown rows.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';

class MacroSegmentedBar extends StatelessWidget {
  /// Macro label shown on the left (e.g. "Protein").
  final String label;

  /// Current rating of this macro (Low / Moderate / High).
  final MacroLevel level;

  /// Optional callback — when set, the user can tap a segment to override
  /// the level (used in the detail-screen edit mode).
  final ValueChanged<MacroLevel>? onLevelChanged;

  const MacroSegmentedBar({
    super.key,
    required this.label,
    required this.level,
    this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
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
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textOnYellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SegmentRow(level: level, onLevelChanged: onLevelChanged),
      ],
    );
  }
}

class _SegmentRow extends StatelessWidget {
  final MacroLevel level;
  final ValueChanged<MacroLevel>? onLevelChanged;

  const _SegmentRow({required this.level, this.onLevelChanged});

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
    final active = segment == level;
    final radius = BorderRadius.horizontal(
      left: isFirst ? const Radius.circular(8) : Radius.zero,
      right: isLast ? const Radius.circular(8) : Radius.zero,
    );
    final inner = Container(
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.primaryLemonDark : AppColors.surfaceLight,
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
