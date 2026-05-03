// Macro ratio visualization — visual-first, no numbers, no judgment.
// PRD §10: "No judgment, No pressure, Curiosity-driven, Visual-first."
//
// One row per macro (Protein / Carbs / Fat / Fiber) with three dots showing
// the level (Low = 1 filled, Moderate = 2 filled, High = 3 filled).
// Color reuses the warm-neutral palette so nothing reads as "good" or "bad".

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';

class MacroRatioBar extends StatelessWidget {
  final MacroRatio ratio;
  final bool compact;

  const MacroRatioBar({
    super.key,
    required this.ratio,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final rows = [
      _MacroRow(label: 'Protein', level: ratio.protein, compact: compact),
      _MacroRow(label: 'Carbs', level: ratio.carbs, compact: compact),
      _MacroRow(label: 'Fat', level: ratio.fat, compact: compact),
      _MacroRow(label: 'Fiber', level: ratio.fiber, compact: compact),
    ];

    if (compact) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: rows.map((r) => SizedBox(width: 130, child: r)).toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final MacroLevel level;
  final bool compact;

  const _MacroRow({
    required this.label,
    required this.level,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: compact ? 50 : 64,
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _DotTrack(level: level),
        const SizedBox(width: 8),
        Text(
          level.displayName,
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DotTrack extends StatelessWidget {
  final MacroLevel level;
  static const double _dotSize = 8;

  const _DotTrack({required this.level});

  int get _filledCount {
    switch (level) {
      case MacroLevel.low:
        return 1;
      case MacroLevel.moderate:
        return 2;
      case MacroLevel.high:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final filled = i < _filledCount;
        return Container(
          margin: EdgeInsets.only(right: i == 2 ? 0 : 4),
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.primaryLemonDark : AppColors.surfaceLight,
          ),
        );
      }),
    );
  }
}

/// Tappable variant used in the editor — dot taps cycle the level
/// (low → moderate → high → low). The user can manually correct any macro
/// they think the AI got wrong.
class MacroRatioEditor extends StatelessWidget {
  final MacroRatio ratio;
  final ValueChanged<MacroRatio> onChanged;

  const MacroRatioEditor({
    super.key,
    required this.ratio,
    required this.onChanged,
  });

  MacroLevel _next(MacroLevel current) {
    switch (current) {
      case MacroLevel.low:
        return MacroLevel.moderate;
      case MacroLevel.moderate:
        return MacroLevel.high;
      case MacroLevel.high:
        return MacroLevel.low;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _editableRow('Protein', ratio.protein, (lvl) {
          onChanged(ratio.copyWith(protein: lvl));
        }),
        const SizedBox(height: 10),
        _editableRow('Carbs', ratio.carbs, (lvl) {
          onChanged(ratio.copyWith(carbs: lvl));
        }),
        const SizedBox(height: 10),
        _editableRow('Fat', ratio.fat, (lvl) {
          onChanged(ratio.copyWith(fat: lvl));
        }),
        const SizedBox(height: 10),
        _editableRow('Fiber', ratio.fiber, (lvl) {
          onChanged(ratio.copyWith(fiber: lvl));
        }),
      ],
    );
  }

  Widget _editableRow(
    String label,
    MacroLevel level,
    ValueChanged<MacroLevel> onTap,
  ) {
    return InkWell(
      onTap: () => onTap(_next(level)),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _DotTrack(level: level),
            const SizedBox(width: 8),
            Text(
              level.displayName,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            const Icon(Icons.touch_app_outlined,
                size: 14, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }
}
