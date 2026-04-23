import 'package:flutter/material.dart';
import '../../../shared/widgets/scroll_datetime_picker.dart';

/// Widget for selecting start and end time using inline scroll pickers
class TimePickerWidget extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;
  final ValueChanged<DateTime> onStartTimeChanged;
  final ValueChanged<DateTime> onEndTimeChanged;

  const TimePickerWidget({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScrollDateTimePicker(
          value: startTime,
          minimumDate: DateTime.now().subtract(const Duration(days: 7)),
          maximumDate: DateTime.now(),
          onChanged: onStartTimeChanged,
          label: 'Start Time',
        ),
        const SizedBox(height: 12),
        ScrollDateTimePicker(
          value: endTime,
          minimumDate: DateTime.now().subtract(const Duration(days: 7)),
          maximumDate: DateTime.now(),
          onChanged: onEndTimeChanged,
          label: 'End Time',
        ),
      ],
    );
  }
}
