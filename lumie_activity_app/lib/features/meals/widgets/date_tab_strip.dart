// DateTabStrip — top-of-screen date navigation for the Meals home.
//
// Layout: [Yesterday]  [Today]   [<Custom date>]   📅
// • Yesterday / Today are pill tabs; one is highlighted gold based on selection.
// • The custom-date pill only appears when selectedDate is neither today nor
//   yesterday, so the user always sees what day they're looking at.
// • The calendar icon opens a native showDatePicker; selecting a date triggers
//   onDateChanged.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class DateTabStrip extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  /// How far back the calendar picker is allowed to scroll. Default 90 days
  /// — enough to browse a season's worth of meals without looking infinite.
  final int firstDateDaysBack;

  const DateTabStrip({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    this.firstDateDaysBack = 90,
  });

  static DateTime _stripTime(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  bool get _isToday {
    final now = _stripTime(DateTime.now());
    return _stripTime(selectedDate) == now;
  }

  bool get _isYesterday {
    final yesterday = _stripTime(DateTime.now()).subtract(const Duration(days: 1));
    return _stripTime(selectedDate) == yesterday;
  }

  String get _customDateLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dt = selectedDate;
    return '${months[dt.month - 1]} ${dt.day}';
  }

  Future<void> _openDatePicker(BuildContext context) async {
    final now = DateTime.now();
    final first = now.subtract(Duration(days: firstDateDaysBack));
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: _stripTime(first),
      lastDate: _stripTime(now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: AppColors.primaryLemonDark,
                onPrimary: Colors.white,
                surface: AppColors.backgroundPaper,
              ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) onDateChanged(_stripTime(picked));
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = !_isToday && !_isYesterday;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          _Tab(
            label: 'Yesterday',
            selected: _isYesterday,
            onTap: () => onDateChanged(
              _stripTime(DateTime.now()).subtract(const Duration(days: 1)),
            ),
          ),
          const SizedBox(width: 8),
          _Tab(
            label: 'Today',
            selected: _isToday,
            onTap: () => onDateChanged(_stripTime(DateTime.now())),
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            _Tab(
              label: _customDateLabel,
              selected: true,
              onTap: () => _openDatePicker(context),
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Pick a date',
            onPressed: () => _openDatePicker(context),
            icon: const Icon(
              Icons.calendar_today_outlined,
              size: 22,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryLemon
          : AppColors.backgroundLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected
              ? AppColors.primaryLemonDark
              : AppColors.surfaceLight,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected
                  ? AppColors.textOnYellow
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
