// NutritionLevelSlider — 4-point slider Limited → Fair → Good → Nutritious
// with a gold dot positioned at the meal's level.
//
// Two variants:
//   • full (default): 36px tall track + 4 labels underneath
//   • compact:        slim 14px track, no labels — used inside list rows

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/meal_models.dart';

class NutritionLevelSlider extends StatelessWidget {
  final NutritionLevel level;
  final bool compact;

  const NutritionLevelSlider({
    super.key,
    required this.level,
    this.compact = false,
  });

  static const _labels = ['Limited', 'Fair', 'Good', 'Nutritious'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Track(level: level, compact: compact),
        if (!compact) ...[
          const SizedBox(height: 8),
          _LabelsRow(active: level),
        ],
      ],
    );
  }
}

class _Track extends StatelessWidget {
  final NutritionLevel level;
  final bool compact;

  const _Track({required this.level, required this.compact});

  @override
  Widget build(BuildContext context) {
    final trackHeight = compact ? 4.0 : 6.0;
    final dotSize = compact ? 12.0 : 16.0;
    // Slice 7A §3: dot + active fill use the level's warm palette colour.
    final accent = level.color;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Treat the dot as if its center walks the track from 0%..100% — so
        // both endpoints sit fully on-screen. Internal "usable" width is
        // shrunk by the dot diameter; track is drawn with dotSize/2 padding.
        final usable = constraints.maxWidth - dotSize;
        final dotLeft = (usable * level.fraction).clamp(0.0, usable);

        return SizedBox(
          height: dotSize,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Background track
              Padding(
                padding: EdgeInsets.symmetric(horizontal: dotSize / 2),
                child: Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(trackHeight),
                  ),
                ),
              ),
              // Filled portion (level-tinted) from 0 → dot center
              Padding(
                padding: EdgeInsets.symmetric(horizontal: dotSize / 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: level.fraction.clamp(0.0001, 1.0),
                    child: Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(trackHeight),
                      ),
                    ),
                  ),
                ),
              ),
              // Dot
              Positioned(
                left: dotLeft,
                child: Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LabelsRow extends StatelessWidget {
  final NutritionLevel active;

  const _LabelsRow({required this.active});

  @override
  Widget build(BuildContext context) {
    final labels = NutritionLevelSlider._labels;
    return Row(
      children: List.generate(labels.length, (i) {
        final isActive = i == active.index;
        // Slice 7A §3: the active label takes the level's warm palette colour.
        final activeColor = NutritionLevel.values[i].color;
        return Expanded(
          child: Align(
            alignment: _alignmentForIndex(i, labels.length),
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? activeColor : AppColors.textLight,
              ),
            ),
          ),
        );
      }),
    );
  }

  Alignment _alignmentForIndex(int i, int total) {
    if (i == 0) return Alignment.centerLeft;
    if (i == total - 1) return Alignment.centerRight;
    return Alignment.center;
  }
}
