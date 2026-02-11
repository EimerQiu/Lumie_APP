import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/app_colors.dart';

/// Calendar widget for selecting specific rest dates.
class RestDaysCalendar extends StatefulWidget {
  /// Currently selected rest dates.
  final List<DateTime> selectedDates;

  /// Callback when selection changes.
  final ValueChanged<List<DateTime>> onChanged;

  const RestDaysCalendar({
    super.key,
    required this.selectedDates,
    required this.onChanged,
  });

  @override
  State<RestDaysCalendar> createState() => _RestDaysCalendarState();
}

class _RestDaysCalendarState extends State<RestDaysCalendar> {
  DateTime _focusedDay = DateTime.now();

  bool _isSelected(DateTime day) {
    return widget.selectedDates.any((d) =>
        d.year == day.year && d.month == day.month && d.day == day.day);
  }

  void _toggleDate(DateTime selectedDay) {
    final newDates = List<DateTime>.from(widget.selectedDates);
    final existingIndex = newDates.indexWhere((d) =>
        d.year == selectedDay.year &&
        d.month == selectedDay.month &&
        d.day == selectedDay.day);

    if (existingIndex >= 0) {
      newDates.removeAt(existingIndex);
    } else {
      newDates.add(selectedDay);
    }

    widget.onChanged(newDates);
  }

  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      firstDay: DateTime.now(),
      lastDay: DateTime.now().add(const Duration(days: 365)),
      focusedDay: _focusedDay,
      selectedDayPredicate: _isSelected,
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _focusedDay = focusedDay;
        });
        _toggleDate(selectedDay);
      },
      calendarFormat: CalendarFormat.month,
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        leftChevronIcon: const Icon(
          Icons.chevron_left,
          color: AppColors.primaryLemonDark,
        ),
        rightChevronIcon: const Icon(
          Icons.chevron_right,
          color: AppColors.primaryLemonDark,
        ),
      ),
      daysOfWeekStyle: const DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        weekendStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      calendarStyle: CalendarStyle(
        // Selected day styling
        selectedDecoration: BoxDecoration(
          gradient: AppColors.warmGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryLemonDark.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        selectedTextStyle: const TextStyle(
          color: AppColors.textOnYellow,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),

        // Today styling
        todayDecoration: BoxDecoration(
          color: AppColors.primaryLemon.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primaryLemonDark,
            width: 2,
          ),
        ),
        todayTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),

        // Default day styling
        defaultDecoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        defaultTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
        ),

        // Weekend styling
        weekendDecoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        weekendTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
        ),

        // Outside month styling
        outsideDecoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        outsideTextStyle: const TextStyle(
          color: AppColors.textLight,
          fontSize: 15,
        ),

        // Disabled day styling
        disabledDecoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        disabledTextStyle: const TextStyle(
          color: AppColors.textLight,
          fontSize: 15,
        ),
      ),
    );
  }
}
