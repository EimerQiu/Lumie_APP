/// Time Window Editor Widget - Input for a single time window in templates

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class TimeWindowEditorData {
  String name;
  TimeOfDay openTime;
  TimeOfDay closeTime;
  bool isNextDay;

  TimeWindowEditorData({
    this.name = '',
    TimeOfDay? openTime,
    TimeOfDay? closeTime,
    this.isNextDay = false,
  })  : openTime = openTime ?? const TimeOfDay(hour: 8, minute: 0),
        closeTime = closeTime ?? const TimeOfDay(hour: 9, minute: 0);

  String get openTimeStr =>
      '${openTime.hour.toString().padLeft(2, '0')}:${openTime.minute.toString().padLeft(2, '0')}';

  String get closeTimeStr =>
      '${closeTime.hour.toString().padLeft(2, '0')}:${closeTime.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson(int index) {
    return {
      'id': index,
      'name': name,
      'open_time': openTimeStr,
      'close_time': closeTimeStr,
      'is_next_day': isNextDay,
    };
  }
}

class TimeWindowEditor extends StatelessWidget {
  final int index;
  final TimeWindowEditorData data;
  final ValueChanged<TimeWindowEditorData> onChanged;
  final VoidCallback? onDelete;

  const TimeWindowEditor({
    super.key,
    required this.index,
    required this.data,
    required this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with delete button
          Row(
            children: [
              Text(
                'Window ${index + 1}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Window name
          TextField(
            onChanged: (value) {
              data.name = value;
              onChanged(data);
            },
            controller: TextEditingController(text: data.name)
              ..selection = TextSelection.collapsed(offset: data.name.length),
            decoration: const InputDecoration(
              labelText: 'Window Name',
              hintText: 'e.g. Morning, Afternoon',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),

          // Time pickers
          Row(
            children: [
              Expanded(
                child: _TimePickerButton(
                  label: 'Start',
                  time: data.openTime,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: data.openTime,
                    );
                    if (picked != null) {
                      data.openTime = picked;
                      onChanged(data);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimePickerButton(
                  label: 'End',
                  time: data.closeTime,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: data.closeTime,
                    );
                    if (picked != null) {
                      data.closeTime = picked;
                      onChanged(data);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Crosses midnight toggle
          Row(
            children: [
              Switch(
                value: data.isNextDay,
                onChanged: (value) {
                  data.isNextDay = value;
                  onChanged(data);
                },
                activeColor: AppColors.primaryLemonDark,
              ),
              const Text(
                'Crosses midnight',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimePickerButton extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimePickerButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.surfaceLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
