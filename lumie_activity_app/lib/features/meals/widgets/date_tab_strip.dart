// DateTabStrip — horizontally scrollable date timeline for the Meals home.
//
// Shows a continuous strip of date pills, one per day, scrollable
// left (further back in history) and right (toward today). Today's pill is
// always the rightmost; the strip never scrolls forward past today.
//
// Each pill shows the three-letter day abbreviation and the date number.
// When a date has at least one logged meal a small gold dot appears below
// the number. The currently-selected pill is highlighted in the app's
// gold/yellow colour.
//
// The original Yesterday / Today tab layout and calendar icon are removed.
// The scroll-list is the navigation.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class DateTabStrip extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  /// Dates that have at least one meal logged — used to paint the dot indicator.
  final Set<DateTime> datesWithMeals;

  /// How many days back the timeline extends. Default 365 — a full year of
  /// scrollable history without feeling infinite.
  final int historyDays;

  const DateTabStrip({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    this.datesWithMeals = const {},
    this.historyDays = 365,
  });

  @override
  State<DateTabStrip> createState() => _DateTabStripState();
}

class _DateTabStripState extends State<DateTabStrip> {
  late final ScrollController _scrollController;
  static const double _pillWidth = 52.0;
  static const double _pillSpacing = 8.0;
  static const double _pillStep = _pillWidth + _pillSpacing;

  static DateTime _stripTime(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  DateTime get _today => _stripTime(DateTime.now());

  /// Index of `date` in the list, where index 0 = the oldest date and the
  /// last index = today.
  int _indexOfDate(DateTime date) {
    final days = _today.difference(_stripTime(date)).inDays;
    return (widget.historyDays - days).clamp(0, widget.historyDays);
  }

  double _scrollOffsetForIndex(int index, double viewportWidth) {
    // Centre the pill in the viewport.
    final targetCenter = index * _pillStep + _pillWidth / 2;
    return (targetCenter - viewportWidth / 2).clamp(0.0, double.infinity);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _jumpToSelected();
    });
  }

  void _jumpToSelected() {
    if (!_scrollController.hasClients) return;
    final vw = _scrollController.position.viewportDimension;
    final idx = _indexOfDate(widget.selectedDate);
    final offset = _scrollOffsetForIndex(idx, vw);
    _scrollController.jumpTo(offset);
  }

  void _animateToSelected() {
    if (!_scrollController.hasClients) return;
    final vw = _scrollController.position.viewportDimension;
    final idx = _indexOfDate(widget.selectedDate);
    final offset = _scrollOffsetForIndex(idx, vw);
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(covariant DateTabStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedDate != widget.selectedDate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateToSelected();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Total pill count: historyDays past days + today = historyDays + 1.
    final count = widget.historyDays + 1;
    final totalWidth = count * _pillWidth + (count - 1) * _pillSpacing;

    return SizedBox(
      height: 68,
      child: ScrollConfiguration(
        // Enable momentum scrolling on all platforms (useful on desktop/web).
        behavior: ScrollConfiguration.of(context).copyWith(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SizedBox(
            width: totalWidth,
            child: Row(
              children: List.generate(count, (i) {
                // i == 0  → oldest date  |  i == count-1 → today
                final date = _today.subtract(Duration(days: count - 1 - i));
                final selected = _stripTime(widget.selectedDate) == date;
                final hasMeals = widget.datesWithMeals.contains(date);
                return _DatePill(
                  date: date,
                  selected: selected,
                  hasMeals: hasMeals,
                  onTap: () => widget.onDateChanged(date),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Single date pill ────────────────────────────────────────────────────────

class _DatePill extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final bool hasMeals;
  final VoidCallback onTap;

  const _DatePill({
    required this.date,
    required this.selected,
    required this.hasMeals,
    required this.onTap,
  });

  static const List<String> _days = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  String get _dayAbbr => _days[date.weekday - 1];

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: _DateTabStripState._pillSpacing),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: _DateTabStripState._pillWidth,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryLemon
                : AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primaryLemonDark
                  : AppColors.surfaceLight,
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _dayAbbr,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: selected
                      ? AppColors.textOnYellow
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.textOnYellow
                      : (_isToday
                          ? AppColors.primaryLemonDark
                          : AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 3),
              // Dot indicator: gold when the selected pill has meals, muted
              // dot for unselected dates with meals, transparent otherwise.
              AnimatedOpacity(
                opacity: hasMeals ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? AppColors.primaryLemonDark
                        : AppColors.textLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
