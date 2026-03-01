/// Task Type Selector Widget - Horizontal scrollable chips for 7 task categories

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/task_models.dart';

class TaskTypeSelector extends StatelessWidget {
  final TaskType selectedType;
  final ValueChanged<TaskType> onChanged;

  const TaskTypeSelector({
    super.key,
    required this.selectedType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: TaskType.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = TaskType.values[index];
          final isSelected = type == selectedType;

          return GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected ? AppColors.warmGradient : null,
                color: isSelected ? null : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryLemonDark
                      : AppColors.surfaceLight,
                ),
              ),
              child: Center(
                child: Text(
                  type.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.textOnYellow
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
