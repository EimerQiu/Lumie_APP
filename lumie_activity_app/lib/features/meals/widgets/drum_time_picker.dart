// DrumDateTimePicker — four-column drum-roll picker: date, hour, minute, AM/PM.
//
// Slice 7A §5: replaces the standard Material showTimePicker on both the Log
// Meal screen and the Meal Detail screen, and now supports backdating.
//
// • Date column shows "Today", "Yesterday", then short dates going back
//   [maxDaysBack] days (default 30).
// • Time columns: hour (1–12), minute (00–59), AM/PM — unchanged from before.
// • Centered value is bolder and slightly larger; surrounding values are
//   smaller and greyed out.
// • Returns the picked [DateTime] from `showDrumDateTimePicker(...)`, or null
//   if the user cancels.
//
// The legacy `showDrumTimePicker` function is kept for backward compatibility;
// new call sites should use `showDrumDateTimePicker` instead.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

// ─── Public API ──────────────────────────────────────────────────────────────

/// Open the full date + time picker as a modal bottom sheet.
/// Returns a [DateTime] with the user's chosen date and time, or null on cancel.
Future<DateTime?> showDrumDateTimePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  int maxDaysBack = 30,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _DrumDateTimeSheet(
      initialDateTime: initialDateTime.toLocal(),
      maxDaysBack: maxDaysBack,
    ),
  );
}

/// Legacy time-only picker — kept for backward compatibility.
/// Prefer [showDrumDateTimePicker] for new call sites.
Future<TimeOfDay?> showDrumTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _DrumTimeSheet(initialTime: initialTime),
  );
}

// ─── Date + time sheet ────────────────────────────────────────────────────────

class _DrumDateTimeSheet extends StatefulWidget {
  final DateTime initialDateTime;
  final int maxDaysBack;

  const _DrumDateTimeSheet({
    required this.initialDateTime,
    required this.maxDaysBack,
  });

  @override
  State<_DrumDateTimeSheet> createState() => _DrumDateTimeSheetState();
}

class _DrumDateTimeSheetState extends State<_DrumDateTimeSheet> {
  // Date column: 0 = today, 1 = yesterday, … maxDaysBack = furthest past date
  late int _dateIndex;
  // Time columns (same as before)
  late int _hourIndex;    // 0..11 → hours 1..12
  late int _minuteIndex;  // 0..59
  late int _ampmIndex;    // 0=AM, 1=PM

  late final FixedExtentScrollController _dateCtrl;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;
  late final FixedExtentScrollController _ampmCtrl;

  // Today stripped to midnight — used for date label computation.
  late final DateTime _today;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);

    // Clamp the initial date to [today, maxDaysBack ago].
    final initDate = DateTime(
      widget.initialDateTime.year,
      widget.initialDateTime.month,
      widget.initialDateTime.day,
    );
    _dateIndex = _today.difference(initDate).inDays.clamp(0, widget.maxDaysBack);

    final t = widget.initialDateTime;
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    _hourIndex = hour12 - 1;
    _minuteIndex = t.minute;
    _ampmIndex = t.hour >= 12 ? 1 : 0;

    _dateCtrl = FixedExtentScrollController(initialItem: _dateIndex);
    _hourCtrl = FixedExtentScrollController(initialItem: _hourIndex);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minuteIndex);
    _ampmCtrl = FixedExtentScrollController(initialItem: _ampmIndex);
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _ampmCtrl.dispose();
    super.dispose();
  }

  String _dateLabel(int index) {
    if (index == 0) return 'Today';
    if (index == 1) return 'Yesterday';
    final date = _today.subtract(Duration(days: index));
    return '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';
  }

  TimeOfDay _currentTime() {
    final hour12 = _hourIndex + 1;
    final hour24 = _ampmIndex == 1
        ? (hour12 == 12 ? 12 : hour12 + 12)
        : (hour12 == 12 ? 0 : hour12);
    return TimeOfDay(hour: hour24, minute: _minuteIndex);
  }

  DateTime _currentDateTime() {
    final date = _today.subtract(Duration(days: _dateIndex));
    final t = _currentTime();
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: viewInsets,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.backgroundPaper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Meal time',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // Drums
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.warmGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 200,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Date column — wider to fit "Yesterday" / "Fri 16 May"
                      Expanded(
                        flex: 4,
                        child: _DrumColumn(
                          controller: _dateCtrl,
                          itemCount: widget.maxDaysBack + 1,
                          builder: _dateLabel,
                          onChanged: (i) => setState(() => _dateIndex = i),
                          fontSize: 16,
                          selectedFontSize: 19,
                        ),
                      ),
                      // Thin vertical rule between date and time
                      const _DrumVerticalRule(),
                      Expanded(
                        flex: 2,
                        child: _DrumColumn(
                          controller: _hourCtrl,
                          itemCount: 12,
                          builder: (i) => (i + 1).toString().padLeft(2, '0'),
                          onChanged: (i) => setState(() => _hourIndex = i),
                        ),
                      ),
                      const _DrumSeparator(),
                      Expanded(
                        flex: 2,
                        child: _DrumColumn(
                          controller: _minuteCtrl,
                          itemCount: 60,
                          builder: (i) => i.toString().padLeft(2, '0'),
                          onChanged: (i) => setState(() => _minuteIndex = i),
                        ),
                      ),
                      const _DrumVerticalRule(),
                      Expanded(
                        flex: 2,
                        child: _DrumColumn(
                          controller: _ampmCtrl,
                          itemCount: 2,
                          builder: (i) => i == 0 ? 'AM' : 'PM',
                          onChanged: (i) => setState(() => _ampmIndex = i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, _currentDateTime()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryLemonDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Legacy time-only sheet (unchanged) ──────────────────────────────────────

class _DrumTimeSheet extends StatefulWidget {
  final TimeOfDay initialTime;
  const _DrumTimeSheet({required this.initialTime});

  @override
  State<_DrumTimeSheet> createState() => _DrumTimeSheetState();
}

class _DrumTimeSheetState extends State<_DrumTimeSheet> {
  late int _hourIndex;
  late int _minuteIndex;
  late int _ampmIndex;

  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;
  late final FixedExtentScrollController _ampmCtrl;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTime;
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    _hourIndex = hour12 - 1;
    _minuteIndex = t.minute;
    _ampmIndex = t.hour >= 12 ? 1 : 0;
    _hourCtrl = FixedExtentScrollController(initialItem: _hourIndex);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minuteIndex);
    _ampmCtrl = FixedExtentScrollController(initialItem: _ampmIndex);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _ampmCtrl.dispose();
    super.dispose();
  }

  TimeOfDay _currentTime() {
    final hour12 = _hourIndex + 1;
    final hour24 = _ampmIndex == 1
        ? (hour12 == 12 ? 12 : hour12 + 12)
        : (hour12 == 12 ? 0 : hour12);
    return TimeOfDay(hour: hour24, minute: _minuteIndex);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: viewInsets,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.backgroundPaper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Meal time',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.warmGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 200,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _DrumColumn(
                          controller: _hourCtrl,
                          itemCount: 12,
                          builder: (i) => (i + 1).toString().padLeft(2, '0'),
                          onChanged: (i) => setState(() => _hourIndex = i),
                        ),
                      ),
                      const _DrumSeparator(),
                      Expanded(
                        child: _DrumColumn(
                          controller: _minuteCtrl,
                          itemCount: 60,
                          builder: (i) => i.toString().padLeft(2, '0'),
                          onChanged: (i) => setState(() => _minuteIndex = i),
                        ),
                      ),
                      const _DrumSeparator(),
                      Expanded(
                        child: _DrumColumn(
                          controller: _ampmCtrl,
                          itemCount: 2,
                          builder: (i) => i == 0 ? 'AM' : 'PM',
                          onChanged: (i) => setState(() => _ampmIndex = i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _currentTime()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryLemonDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared drum widgets ──────────────────────────────────────────────────────

class _DrumColumn extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int) builder;
  final ValueChanged<int> onChanged;
  final double fontSize;
  final double selectedFontSize;

  const _DrumColumn({
    required this.controller,
    required this.itemCount,
    required this.builder,
    required this.onChanged,
    this.fontSize = 18,
    this.selectedFontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      physics: const FixedExtentScrollPhysics(),
      perspective: 0.003,
      diameterRatio: 1.6,
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final selected = controller.hasClients
                  ? controller.selectedItem == index
                  : index == controller.initialItem;
              return Center(
                child: Text(
                  builder(index),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: selected ? selectedFontSize : fontSize,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.textOnYellow
                        : AppColors.textLight,
                    height: 1.0,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DrumSeparator extends StatelessWidget {
  const _DrumSeparator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textOnYellow,
        ),
      ),
    );
  }
}

/// Thin vertical rule used between the date column and the time block.
class _DrumVerticalRule extends StatelessWidget {
  const _DrumVerticalRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.textOnYellow.withValues(alpha: 0.25),
    );
  }
}
