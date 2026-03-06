/// Scroll Wheel DateTime Picker - Cupertino-style inline dropdown picker
///
/// Supports 3 modes:
/// - DateTime: date + hour + minute + AM/PM
/// - Date only: date wheel
/// - Time only: hour + minute + AM/PM
///
/// Usage: Place ScrollDateTimePicker in your widget tree.
/// It shows a tappable button that expands an inline scroll wheel picker.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum PickerMode { dateTime, dateOnly, timeOnly }

/// Inline expandable date-time picker widget.
/// Tapping toggles the scroll wheels open/closed below the label.
class ScrollDateTimePicker extends StatefulWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? minimumDate;
  final DateTime? maximumDate;
  final PickerMode mode;
  final String? label;

  const ScrollDateTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.minimumDate,
    this.maximumDate,
    this.mode = PickerMode.dateTime,
    this.label,
  });

  @override
  State<ScrollDateTimePicker> createState() => _ScrollDateTimePickerState();
}

class _ScrollDateTimePickerState extends State<ScrollDateTimePicker>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  String _formatDisplay(DateTime dt) {
    if (widget.mode == PickerMode.timeOnly) {
      final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour12:$min $ampm';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);

    String dateStr;
    if (dateOnly == today) {
      dateStr = 'Today';
    } else if (dateOnly == today.add(const Duration(days: 1))) {
      dateStr = 'Tomorrow';
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      dateStr = 'Yesterday';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      dateStr = '${months[dt.month - 1]} ${dt.day}';
    }

    if (widget.mode == PickerMode.dateOnly) return dateStr;

    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dateStr at $hour12:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tappable button
        GestureDetector(
          onTap: _toggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: _expanded ? AppColors.primaryLemonDark : AppColors.surfaceLight,
              ),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.backgroundWhite,
            ),
            child: Row(
              children: [
                Icon(
                  widget.mode == PickerMode.timeOnly
                      ? Icons.access_time
                      : Icons.calendar_today,
                  size: 18,
                  color: AppColors.primaryLemonDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatDisplay(widget.value),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expandable picker
        SizeTransition(
          sizeFactor: _expandAnimation,
          child: _InlinePickerWheels(
            value: widget.value,
            onChanged: widget.onChanged,
            minimumDate: widget.minimumDate,
            maximumDate: widget.maximumDate,
            mode: widget.mode,
          ),
        ),
      ],
    );
  }
}

// --- Internal wheels widget ---

class _InlinePickerWheels extends StatefulWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? minimumDate;
  final DateTime? maximumDate;
  final PickerMode mode;

  const _InlinePickerWheels({
    required this.value,
    required this.onChanged,
    this.minimumDate,
    this.maximumDate,
    required this.mode,
  });

  @override
  State<_InlinePickerWheels> createState() => _InlinePickerWheelsState();
}

class _InlinePickerWheelsState extends State<_InlinePickerWheels> {
  late List<DateTime> _dates;
  late FixedExtentScrollController _dateController;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _ampmController;

  static const double _itemExtent = 44.0;
  static const double _pickerHeight = 220.0;

  @override
  void initState() {
    super.initState();
    _initDates();
    _initTimeControllers();
  }

  void _initDates() {
    final today = DateTime.now();
    final startDate = widget.minimumDate ?? today.subtract(const Duration(days: 30));
    final endDate = widget.maximumDate ?? today.add(const Duration(days: 365));
    _dates = [];
    var d = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    while (!d.isAfter(end)) {
      _dates.add(d);
      d = d.add(const Duration(days: 1));
    }

    final selectedDate = DateTime(widget.value.year, widget.value.month, widget.value.day);
    int dateIndex = _dates.indexWhere((dt) =>
        dt.year == selectedDate.year &&
        dt.month == selectedDate.month &&
        dt.day == selectedDate.day);
    if (dateIndex < 0) dateIndex = _dates.length ~/ 2;
    _dateController = FixedExtentScrollController(initialItem: dateIndex);
  }

  void _initTimeControllers() {
    final hour12 = widget.value.hour == 0
        ? 12
        : (widget.value.hour > 12 ? widget.value.hour - 12 : widget.value.hour);
    final isAm = widget.value.hour < 12;

    _hourController = FixedExtentScrollController(initialItem: hour12 - 1);
    _minuteController = FixedExtentScrollController(initialItem: widget.value.minute);
    _ampmController = FixedExtentScrollController(initialItem: isAm ? 0 : 1);
  }

  @override
  void dispose() {
    _dateController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _ampmController.dispose();
    super.dispose();
  }

  void _onWheelChanged() {
    if (widget.mode == PickerMode.dateOnly) {
      final dateIdx = _dateController.selectedItem.clamp(0, _dates.length - 1);
      final date = _dates[dateIdx];
      widget.onChanged(DateTime(date.year, date.month, date.day));
      return;
    }

    final hour12 = (_hourController.selectedItem % 12) + 1;
    final minute = _minuteController.selectedItem % 60;
    final isPm = (_ampmController.selectedItem % 2) == 1;

    int hour24;
    if (hour12 == 12) {
      hour24 = isPm ? 12 : 0;
    } else {
      hour24 = isPm ? hour12 + 12 : hour12;
    }

    if (widget.mode == PickerMode.timeOnly) {
      final now = DateTime.now();
      widget.onChanged(DateTime(now.year, now.month, now.day, hour24, minute));
      return;
    }

    // dateTime mode
    final dateIdx = _dateController.selectedItem.clamp(0, _dates.length - 1);
    final date = _dates[dateIdx];
    widget.onChanged(DateTime(date.year, date.month, date.day, hour24, minute));
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final dayName = dateOnly == today ? 'Today' : weekdays[date.weekday - 1];
    return '$dayName ${months[date.month - 1]} ${date.day}';
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required Widget Function(int index) itemBuilder,
    bool looping = false,
  }) {
    return CupertinoPicker.builder(
      scrollController: controller,
      itemExtent: _itemExtent,
      diameterRatio: 1.5,
      squeeze: 1.0,
      useMagnifier: true,
      magnification: 1.08,
      selectionOverlay: const SizedBox.shrink(),
      onSelectedItemChanged: (_) => _onWheelChanged(),
      childCount: looping ? null : itemCount,
      itemBuilder: (context, index) {
        final actualIndex = looping ? index % itemCount : index;
        if (!looping && (index < 0 || index >= itemCount)) return null;
        return Center(child: itemBuilder(actualIndex));
      },
    );
  }

  Widget _label(String text, bool isSelected) {
    return Text(
      text,
      style: TextStyle(
        fontSize: isSelected ? 20 : 15,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        color: isSelected ? AppColors.textPrimary : AppColors.textLight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _pickerHeight,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth - 8; // minus padding
          return Stack(
            children: [
              // Selection highlight bar
              Center(
                child: Container(
                  height: _itemExtent,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              // Wheels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _buildColumns(totalWidth),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sizedWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required Widget Function(int index) itemBuilder,
    required double width,
    bool looping = false,
  }) {
    return SizedBox(
      width: width,
      child: _wheel(
        controller: controller,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        looping: looping,
      ),
    );
  }

  List<Widget> _buildColumns(double totalWidth) {
    switch (widget.mode) {
      case PickerMode.dateTime:
        // date takes remaining space, time columns get fixed widths
        final timeColWidth = 50.0;
        final dateWidth = totalWidth - (timeColWidth * 3) - 8; // 8 for padding
        return [
          SizedBox(
            width: dateWidth.clamp(80, 300),
            child: _wheel(
              controller: _dateController,
              itemCount: _dates.length,
              itemBuilder: (i) => _label(
                _formatDateLabel(_dates[i]),
                i == _dateController.selectedItem,
              ),
            ),
          ),
          _sizedWheel(
            controller: _hourController,
            itemCount: 12,
            looping: true,
            width: timeColWidth,
            itemBuilder: (i) {
              final hour = (i % 12) + 1;
              final selectedHour = (_hourController.selectedItem % 12) + 1;
              return _label('$hour', hour == selectedHour);
            },
          ),
          _sizedWheel(
            controller: _minuteController,
            itemCount: 60,
            looping: true,
            width: timeColWidth,
            itemBuilder: (i) {
              final min = i % 60;
              final selectedMin = _minuteController.selectedItem % 60;
              return _label(min.toString().padLeft(2, '0'), min == selectedMin);
            },
          ),
          _sizedWheel(
            controller: _ampmController,
            itemCount: 2,
            width: timeColWidth,
            itemBuilder: (i) => _label(
              i == 0 ? 'AM' : 'PM',
              i == _ampmController.selectedItem,
            ),
          ),
        ];

      case PickerMode.dateOnly:
        return [
          SizedBox(
            width: totalWidth,
            child: _wheel(
              controller: _dateController,
              itemCount: _dates.length,
              itemBuilder: (i) => _label(
                _formatDateLabel(_dates[i]),
                i == _dateController.selectedItem,
              ),
            ),
          ),
        ];

      case PickerMode.timeOnly:
        final colWidth = (totalWidth - 16) / 3;
        return [
          const SizedBox(width: 8),
          _sizedWheel(
            controller: _hourController,
            itemCount: 12,
            looping: true,
            width: colWidth,
            itemBuilder: (i) {
              final hour = (i % 12) + 1;
              final selectedHour = (_hourController.selectedItem % 12) + 1;
              return _label('$hour', hour == selectedHour);
            },
          ),
          _sizedWheel(
            controller: _minuteController,
            itemCount: 60,
            looping: true,
            width: colWidth,
            itemBuilder: (i) {
              final min = i % 60;
              final selectedMin = _minuteController.selectedItem % 60;
              return _label(min.toString().padLeft(2, '0'), min == selectedMin);
            },
          ),
          _sizedWheel(
            controller: _ampmController,
            itemCount: 2,
            width: colWidth,
            itemBuilder: (i) => _label(
              i == 0 ? 'AM' : 'PM',
              i == _ampmController.selectedItem,
            ),
          ),
          const SizedBox(width: 8),
        ];
    }
  }
}

// --- Legacy helper functions (keep for time_window_editor compatibility) ---

/// Show time-only picker as bottom sheet fallback, returns TimeOfDay.
Future<TimeOfDay?> showScrollTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) async {
  final now = DateTime.now();
  DateTime selected = DateTime(now.year, now.month, now.day, initialTime.hour, initialTime.minute);

  final result = await showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _BottomSheetTimePicker(initialDateTime: selected),
  );
  if (result == null) return null;
  return TimeOfDay(hour: result.hour, minute: result.minute);
}

class _BottomSheetTimePicker extends StatefulWidget {
  final DateTime initialDateTime;
  const _BottomSheetTimePicker({required this.initialDateTime});

  @override
  State<_BottomSheetTimePicker> createState() => _BottomSheetTimePickerState();
}

class _BottomSheetTimePickerState extends State<_BottomSheetTimePicker> {
  late DateTime _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialDateTime;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _value),
                  child: const Text('Done', style: TextStyle(color: AppColors.primaryLemonDark, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: _InlinePickerWheels(
              value: _value,
              onChanged: (dt) => setState(() => _value = dt),
              mode: PickerMode.timeOnly,
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
