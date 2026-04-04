import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/sleep_service.dart';
import '../../../shared/models/sleep_models.dart';
import '../widgets/sleep_stage_chart.dart';

class SleepHistoryScreen extends StatefulWidget {
  const SleepHistoryScreen({super.key});

  @override
  State<SleepHistoryScreen> createState() => _SleepHistoryScreenState();
}

class _SleepHistoryScreenState extends State<SleepHistoryScreen> {
  final SleepService _sleepService = SleepService();

  late DateTime _focusedMonth;
  DateTime? _selectedDate;
  Map<String, SleepSession> _sessionsByDate = {};
  SleepSummary? _summary;
  bool _isLoading = true;
  String? _errorMessage;

  static const _weekdayHeaders = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadMonth(_focusedMonth);
  }

  Future<void> _loadMonth(DateTime month) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final startDate = DateTime(month.year, month.month, 1);
      final endDate = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

      final results = await Future.wait([
        _sleepService.getSleepHistory(startDate: startDate, endDate: endDate),
        _sleepService.getSleepSummary(startDate: startDate, endDate: endDate),
      ]);

      final sessions = results[0] as List<SleepSession>;
      final Map<String, SleepSession> byDate = {};
      for (final s in sessions) {
        byDate[_dateKey(s.wakeTime.toLocal())] = s;
      }

      setState(() {
        _sessionsByDate = byDate;
        _summary = results[1] as SleepSummary;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _prevMonth() {
    final m = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    setState(() {
      _focusedMonth = m;
      _selectedDate = null;
    });
    _loadMonth(m);
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() {
      _focusedMonth = next;
      _selectedDate = null;
    });
    _loadMonth(next);
  }

  bool _isCurrentMonth() {
    final now = DateTime.now();
    return _focusedMonth.year == now.year && _focusedMonth.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text('Sleep History'),
        backgroundColor: AppColors.backgroundWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildError()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCalendar(),
                      const SizedBox(height: 24),
                      _buildSelectedDayDetail(),
                      if (_summary != null) ...[
                        const SizedBox(height: 24),
                        _buildMonthlySummary(),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          const Text(
            'Failed to load sleep history',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _loadMonth(_focusedMonth),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── Calendar ─────────────────────────────────────────────────────────────

  Widget _buildCalendar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMonthHeader(),
          const SizedBox(height: 12),
          _buildWeekdayRow(),
          const SizedBox(height: 4),
          _buildDaysGrid(),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: _prevMonth,
          icon: const Icon(Icons.chevron_left),
          color: AppColors.textPrimary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        Expanded(
          child: Text(
            '${_monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        IconButton(
          onPressed: _isCurrentMonth() ? null : _nextMonth,
          icon: const Icon(Icons.chevron_right),
          color: _isCurrentMonth() ? AppColors.textLight : AppColors.textPrimary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }

  Widget _buildWeekdayRow() {
    return Row(
      children: _weekdayHeaders
          .map(
            (d) => Expanded(
              child: Text(
                d,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLight,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDaysGrid() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    // Sunday-first offset: Flutter weekday 1=Mon…7=Sun → Sun=0, Mon=1, …, Sat=6
    final startOffset = firstDay.weekday % 7;
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      children: List.generate(rows, (rowIdx) {
        return Row(
          children: List.generate(7, (colIdx) {
            final cellIdx = rowIdx * 7 + colIdx;
            final dayNum = cellIdx - startOffset + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return const Expanded(child: SizedBox(height: 48));
            }
            final date = DateTime(
              _focusedMonth.year,
              _focusedMonth.month,
              dayNum,
            );
            final isFuture = date.isAfter(today);
            final key = _dateKey(date);
            final hasData = _sessionsByDate.containsKey(key);
            final isSelected = _selectedDate != null &&
                _dateKey(_selectedDate!) == key;

            return Expanded(
              child: GestureDetector(
                onTap: isFuture
                    ? null
                    : () => setState(() => _selectedDate = date),
                child: _buildDayCell(
                  dayNum: dayNum,
                  isToday: date == today,
                  isFuture: isFuture,
                  hasData: hasData,
                  isSelected: isSelected,
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  Widget _buildDayCell({
    required int dayNum,
    required bool isToday,
    required bool isFuture,
    required bool hasData,
    required bool isSelected,
  }) {
    Color textColor;
    if (isFuture) {
      textColor = AppColors.textLight.withValues(alpha: 0.4);
    } else if (isSelected) {
      textColor = Colors.white;
    } else if (isToday) {
      textColor = AppColors.primaryLemonDark;
    } else {
      textColor = AppColors.textPrimary;
    }

    return SizedBox(
      height: 48,
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: isSelected
              ? BoxDecoration(
                  color: AppColors.primaryLemonDark,
                  shape: BoxShape.circle,
                )
              : isToday
                  ? BoxDecoration(
                      border: Border.all(color: AppColors.primaryLemonDark),
                      shape: BoxShape.circle,
                    )
                  : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$dayNum',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                  color: textColor,
                ),
              ),
              if (hasData && !isSelected)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.accentMint,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Selected day detail ───────────────────────────────────────────────────

  Widget _buildSelectedDayDetail() {
    if (_selectedDate == null) {
      return const SizedBox();
    }

    final key = _dateKey(_selectedDate!);
    final session = _sessionsByDate[key];
    final label = _formatDateLabel(_selectedDate!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        session != null
            ? _buildSessionDetail(session)
            : _buildNoDataForDay(),
      ],
    );
  }

  Widget _buildNoDataForDay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundPaper,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.bedtime_outlined, size: 40, color: AppColors.textLight),
          SizedBox(height: 8),
          Text(
            'No sleep data for this night',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Wear your Lumie Ring to track sleep',
            style: TextStyle(fontSize: 12, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDetail(SleepSession session) {
    final hours = session.totalSleepTime.inHours;
    final minutes = session.totalSleepTime.inMinutes % 60;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Duration row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${hours}h ${minutes}m',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  height: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _qualityColor(session.sleepQualityScore)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${session.sleepQualityScore.toStringAsFixed(0)}% quality',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _qualityColor(session.sleepQualityScore),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.bedtime_outlined, size: 14, color: AppColors.textLight),
              const SizedBox(width: 6),
              Text(
                '${_formatTime(session.bedtime)} – ${_formatTime(session.wakeTime)}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              if (session.restingHeartRate > 0) ...[
                const SizedBox(width: 16),
                const Icon(Icons.favorite_outline, size: 14, color: AppColors.textLight),
                const SizedBox(width: 6),
                Text(
                  '${session.restingHeartRate} bpm',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SleepStageChart(session: session),
          const SizedBox(height: 12),
          _buildStageRow('Light Sleep',
              session.getStagePercentage(SleepStage.light), AppColors.primaryLemon),
          const SizedBox(height: 6),
          _buildStageRow('Deep Sleep',
              session.getStagePercentage(SleepStage.deep), AppColors.accentMint),
          const SizedBox(height: 6),
          _buildStageRow('REM Sleep',
              session.getStagePercentage(SleepStage.rem), AppColors.accentLavender),
        ],
      ),
    );
  }

  Widget _buildStageRow(String label, double pct, Color color) {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
        ),
        Text(
          '${pct.toStringAsFixed(0)}%',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
      ],
    );
  }

  // ── Monthly summary ───────────────────────────────────────────────────────

  Widget _buildMonthlySummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.warmGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_monthNames[_focusedMonth.month - 1]} Average',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textOnYellow,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildSummaryMetric(
                  'Sleep', '${_summary!.averageSleepHours.toStringAsFixed(1)}h',
                  Icons.bedtime_outlined)),
              Expanded(child: _buildSummaryMetric(
                  'Resting HR', '${_summary!.averageRestingHR.toStringAsFixed(0)} bpm',
                  Icons.favorite_outline)),
              Expanded(child: _buildSummaryMetric(
                  'Quality', '${_summary!.averageSleepQuality.toStringAsFixed(0)}%',
                  Icons.star_outline)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 22, color: AppColors.textOnYellow),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textOnYellow)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: AppColors.textOnYellow.withValues(alpha: 0.8))),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _qualityColor(double q) {
    if (q >= 80) return AppColors.success;
    if (q >= 60) return AppColors.warning;
    return AppColors.error;
  }

  String _formatDateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    if (date == today) return 'Tonight / Today';
    if (date == today.subtract(const Duration(days: 1))) return 'Last Night';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
