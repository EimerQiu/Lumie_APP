// DrumTimePicker — three-column drum-roll style time picker.
//
// Slice 7A §5: replaces the standard Material showTimePicker on both the Log
// Meal screen and the Meal Detail screen.
//
// • Three independent scrollable columns: hour (1–12), minute (00–59), AM/PM.
// • Centered value is bolder and slightly larger; values above/below are
//   smaller and greyed out.
// • Rounded card with a soft warm background matching Lumie's theme.
// • Returns the picked [TimeOfDay] from `showDrumTimePicker(...)`, or null if
//   the user cancels — same call signature as `showTimePicker`.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Open the picker as a modal bottom sheet. Mirrors `showTimePicker(...)`'s
/// return shape so call sites can swap it in transparently.
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

class _DrumTimeSheet extends StatefulWidget {
  final TimeOfDay initialTime;
  const _DrumTimeSheet({required this.initialTime});

  @override
  State<_DrumTimeSheet> createState() => _DrumTimeSheetState();
}

class _DrumTimeSheetState extends State<_DrumTimeSheet> {
  late int _hourIndex;    // 0..11 → hours 1..12
  late int _minuteIndex;  // 0..59
  late int _ampmIndex;    // 0=AM, 1=PM

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

class _DrumColumn extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int) builder;
  final ValueChanged<int> onChanged;

  const _DrumColumn({
    required this.controller,
    required this.itemCount,
    required this.builder,
    required this.onChanged,
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
              // The currently-centered value is bigger + bolder + amber-warm;
              // surrounding values fade to a calm grey.
              final selected = controller.hasClients
                  ? controller.selectedItem == index
                  : index == controller.initialItem;
              return Center(
                child: Text(
                  builder(index),
                  style: TextStyle(
                    fontSize: selected ? 24 : 18,
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
