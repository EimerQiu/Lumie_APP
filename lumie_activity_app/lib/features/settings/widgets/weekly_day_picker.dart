import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Widget for selecting weekly rest days (Monday-Sunday).
class WeeklyDayPicker extends StatelessWidget {
  /// Currently selected days (0=Monday, 6=Sunday).
  final List<int> selectedDays;

  /// Callback when selection changes.
  final ValueChanged<List<int>> onChanged;

  /// Short day labels for compact display.
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// Full day names for accessibility.
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  const WeeklyDayPicker({
    super.key,
    required this.selectedDays,
    required this.onChanged,
  });

  void _toggleDay(int day) {
    final newDays = List<int>.from(selectedDays);
    if (newDays.contains(day)) {
      newDays.remove(day);
    } else {
      newDays.add(day);
    }
    onChanged(newDays);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (index) {
        final isSelected = selectedDays.contains(index);

        return Semantics(
          label: _dayNames[index],
          selected: isSelected,
          button: true,
          child: GestureDetector(
            onTap: () => _toggleDay(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: isSelected ? AppColors.warmGradient : null,
                color: isSelected ? null : AppColors.surfaceLight,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primaryLemonDark.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  _dayLabels[index],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? AppColors.textOnYellow
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
