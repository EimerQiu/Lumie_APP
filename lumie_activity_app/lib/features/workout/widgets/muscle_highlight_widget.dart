import 'package:flutter/material.dart';

/// Displays primary and secondary muscle group labels with color-coded chips.
///
/// Primary muscles are shown in a bright accent color (yellow/orange).
/// Secondary muscles are shown in a lighter shade.
/// Used below the stick figure demo and in the expanded PiP overlay.
class MuscleHighlightWidget extends StatelessWidget {
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final bool compact;

  const MuscleHighlightWidget({
    super.key,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (primaryMuscles.isEmpty && secondaryMuscles.isEmpty) {
      return const SizedBox.shrink();
    }

    final chipSize = compact ? 10.0 : 12.0;
    final labelSize = compact ? 10.0 : 11.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 24,
        vertical: compact ? 4 : 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (primaryMuscles.isNotEmpty)
            _MuscleRow(
              label: 'Primary',
              muscles: primaryMuscles,
              color: const Color(0xFFFBBF24), // bright yellow
              chipSize: chipSize,
              labelSize: labelSize,
            ),
          if (secondaryMuscles.isNotEmpty) ...[
            SizedBox(height: compact ? 2 : 4),
            _MuscleRow(
              label: 'Secondary',
              muscles: secondaryMuscles,
              color: Colors.white.withAlpha(120), // lighter shade
              chipSize: chipSize,
              labelSize: labelSize,
            ),
          ],
        ],
      ),
    );
  }
}

class _MuscleRow extends StatelessWidget {
  final String label;
  final List<String> muscles;
  final Color color;
  final double chipSize;
  final double labelSize;

  const _MuscleRow({
    required this.label,
    required this.muscles,
    required this.color,
    required this.chipSize,
    required this.labelSize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white.withAlpha(100),
            fontSize: labelSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            children: muscles.map((m) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  m,
                  style: TextStyle(
                    color: color,
                    fontSize: chipSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
