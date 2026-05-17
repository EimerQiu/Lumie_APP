import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/workout_prefs_service.dart';
import '../../../core/services/workout_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/workout_history_provider.dart';

/// Shows per-exercise strength progression as line charts.
/// User picks an exercise from the list, then sees weight and reps over time.
class StrengthProgressScreen extends StatefulWidget {
  const StrengthProgressScreen({super.key});

  @override
  State<StrengthProgressScreen> createState() =>
      _StrengthProgressScreenState();
}

class _StrengthProgressScreenState extends State<StrengthProgressScreen> {
  // exerciseName → sorted list of {date, maxWeight, maxReps, totalVolume}
  final Map<String, List<_DataPoint>> _historyCache = {};
  bool _loadingExercises = true;

  // Unique exercises extracted from session history
  List<_ExerciseSummary> _exercises = [];
  _ExerciseSummary? _selected;

  bool _loadingChart = false;
  _ChartMetric _metric = _ChartMetric.weight;
  String _weightUnit = 'lbs';

  @override
  void initState() {
    super.initState();
    WorkoutPrefsService.getWeightUnit()
        .then((u) { if (mounted) setState(() => _weightUnit = u); });
    _buildExerciseList();
  }

  void _buildExerciseList() {
    final provider = _historyProvider;
    if (provider == null) return;

    final seen = <String, _ExerciseSummary>{};
    for (final session in provider.sessions) {
      for (final ex in session.exercises) {
        if (!seen.containsKey(ex.exerciseId)) {
          seen[ex.exerciseId] = _ExerciseSummary(
            exerciseId: ex.exerciseId,
            name: ex.exerciseName,
            equipmentType: ex.equipmentType,
          );
        }
      }
    }

    setState(() {
      _exercises = seen.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _loadingExercises = false;
      if (_exercises.isNotEmpty) _selectExercise(_exercises.first);
    });
  }

  WorkoutHistoryProvider? get _historyProvider {
    try {
      return context.read<WorkoutHistoryProvider>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _selectExercise(_ExerciseSummary ex) async {
    setState(() {
      _selected = ex;
      _loadingChart = true;
    });

    if (!_historyCache.containsKey(ex.exerciseId)) {
      try {
        final api = WorkoutApiService();
        final history =
            await api.getExerciseHistory(ex.exerciseId, limit: 30);
        final points = <_DataPoint>[];
        for (final h in history) {
          final sets = (h['sets'] as List<dynamic>?) ?? [];
          if (sets.isEmpty) continue;
          double maxW = 0;
          int maxR = 0;
          double maxVol = 0;
          for (final s in sets) {
            final w = (s['actual_weight'] as num?)?.toDouble() ?? 0;
            final r = (s['actual_reps'] as num?)?.toInt() ?? 0;
            if (w > maxW) maxW = w;
            if (r > maxR) maxR = r;
            final v = w * r;
            if (v > maxVol) maxVol = v;
          }
          final dateStr = h['date'] as String?;
          if (dateStr == null) continue;
          points.add(_DataPoint(
            date: DateTime.parse(dateStr).toLocal(),
            maxWeight: maxW,
            maxReps: maxR,
            totalVolume: maxVol,
          ));
        }
        // Sort oldest first for charting
        points.sort((a, b) => a.date.compareTo(b.date));
        _historyCache[ex.exerciseId] = points;
      } catch (_) {
        _historyCache[ex.exerciseId] = [];
      }
    }

    if (mounted) setState(() => _loadingChart = false);
  }

  List<_DataPoint> get _currentPoints =>
      _historyCache[_selected?.exerciseId] ?? [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Progress',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loadingExercises
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primaryLemonDark))
          : _exercises.isEmpty
              ? const _EmptyProgress()
              : Row(
                  children: [
                    // Left: exercise list
                    Container(
                      width: 140,
                      color: AppColors.backgroundWhite,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _exercises.length,
                        itemBuilder: (context, i) {
                          final ex = _exercises[i];
                          final isSelected =
                              _selected?.exerciseId == ex.exerciseId;
                          return GestureDetector(
                            onTap: () => _selectExercise(ex),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primaryLemon
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                ex.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.textOnYellow
                                      : AppColors.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Right: chart panel
                    Expanded(
                      child: _loadingChart
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primaryLemonDark))
                          : _currentPoints.length < 2
                              ? const _NotEnoughData()
                              : _ChartPanel(
                                  exerciseName:
                                      _selected?.name ?? '',
                                  points: _currentPoints,
                                  metric: _metric,
                                  weightUnit: _weightUnit,
                                  onMetricChanged: (m) =>
                                      setState(() => _metric = m),
                                ),
                    ),
                  ],
                ),
    );
  }
}

// ── Chart panel ───────────────────────────────────────────────────────────────

enum _ChartMetric { weight, reps, volume }

class _ChartPanel extends StatelessWidget {
  final String exerciseName;
  final List<_DataPoint> points;
  final _ChartMetric metric;
  final String weightUnit;
  final ValueChanged<_ChartMetric> onMetricChanged;

  const _ChartPanel({
    required this.exerciseName,
    required this.points,
    required this.metric,
    required this.weightUnit,
    required this.onMetricChanged,
  });

  double _valueFor(_DataPoint p) {
    switch (metric) {
      case _ChartMetric.weight:
        return p.maxWeight;
      case _ChartMetric.reps:
        return p.maxReps.toDouble();
      case _ChartMetric.volume:
        return p.totalVolume;
    }
  }

  String get _yLabel {
    switch (metric) {
      case _ChartMetric.weight:
        return weightUnit;
      case _ChartMetric.reps:
        return 'reps';
      case _ChartMetric.volume:
        return 'vol';
    }
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final values = points.map(_valueFor).toList();
    final maxVal =
        values.reduce((a, b) => a > b ? a : b).ceilToDouble();
    final minVal =
        (values.reduce((a, b) => a < b ? a : b) * 0.85).floorToDouble();

    final spots = points.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), _valueFor(e.value));
    }).toList();

    // Best value for the stat header
    final best = values.reduce((a, b) => a > b ? a : b);
    final latest = values.last;
    final prev = values.length > 1 ? values[values.length - 2] : latest;
    final improved = latest >= prev;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exercise name
          Text(
            exerciseName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${points.length} sessions logged',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Metric toggle
          Row(
            children: [
              _MetricChip(
                label: 'Weight',
                selected: metric == _ChartMetric.weight,
                onTap: () => onMetricChanged(_ChartMetric.weight),
              ),
              const SizedBox(width: 6),
              _MetricChip(
                label: 'Reps',
                selected: metric == _ChartMetric.reps,
                onTap: () => onMetricChanged(_ChartMetric.reps),
              ),
              const SizedBox(width: 6),
              _MetricChip(
                label: 'Volume',
                selected: metric == _ChartMetric.volume,
                onTap: () => onMetricChanged(_ChartMetric.volume),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stat summary row
          Row(
            children: [
              _StatMini(
                label: 'Latest',
                value: metric == _ChartMetric.reps
                    ? '${latest.toInt()} reps'
                    : '${latest.toStringAsFixed(latest % 1 == 0 ? 0 : 1)} $_yLabel',
                trend: improved ? 1 : (latest < prev ? -1 : 0),
              ),
              const SizedBox(width: 12),
              _StatMini(
                label: 'Best',
                value: metric == _ChartMetric.reps
                    ? '${best.toInt()} reps'
                    : '${best.toStringAsFixed(best % 1 == 0 ? 0 : 1)} $_yLabel',
                trend: 0,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Line chart
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: minVal,
                maxY: maxVal * 1.05,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.surfaceLight,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _xInterval(points.length),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _shortDate(points[idx].date),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: AppColors.primaryLemonDark,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: AppColors.primaryLemonDark,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primaryLemonDark.withValues(alpha: 0.2),
                          AppColors.primaryLemonDark.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.textPrimary,
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(s.y % 1 == 0 ? 0 : 1)} $_yLabel\n${_shortDate(points[s.x.toInt()].date)}',
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),

          // Session history list
          const SizedBox(height: 24),
          const Text(
            'Session History',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...points.reversed.map((p) => _SessionHistoryRow(
                point: p,
                metric: metric,
                yLabel: _yLabel,
              )),
        ],
      ),
    );
  }

  double _xInterval(int count) {
    if (count <= 5) return 1;
    if (count <= 10) return 2;
    return (count / 5).ceilToDouble();
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MetricChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryLemonDark
              : AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primaryLemonDark
                : AppColors.surfaceLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  final int trend; // 1 up, -1 down, 0 neutral

  const _StatMini(
      {required this.label, required this.value, required this.trend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ],
          ),
          if (trend != 0) ...[
            const SizedBox(width: 6),
            Icon(
              trend > 0 ? Icons.trending_up : Icons.trending_down,
              size: 18,
              color: trend > 0
                  ? const Color(0xFF16A34A)
                  : AppColors.error,
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionHistoryRow extends StatelessWidget {
  final _DataPoint point;
  final _ChartMetric metric;
  final String yLabel;

  const _SessionHistoryRow(
      {required this.point, required this.metric, required this.yLabel});

  double get _value {
    switch (metric) {
      case _ChartMetric.weight:
        return point.maxWeight;
      case _ChartMetric.reps:
        return point.maxReps.toDouble();
      case _ChartMetric.volume:
        return point.totalVolume;
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _formatDate(point.date),
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            metric == _ChartMetric.reps
                ? '${_value.toInt()} reps'
                : '${_value.toStringAsFixed(_value % 1 == 0 ? 0 : 1)} $yLabel',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty / error states ──────────────────────────────────────────────────────

class _EmptyProgress extends StatelessWidget {
  const _EmptyProgress();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined,
                size: 52, color: AppColors.textLight),
            SizedBox(height: 16),
            Text(
              'No workouts logged yet',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              'Log a workout to start tracking your progress',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 40, color: AppColors.textLight),
            SizedBox(height: 12),
            Text(
              'Not enough data yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            SizedBox(height: 6),
            Text(
              'Log this exercise at least twice to see your progression',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class _DataPoint {
  final DateTime date;
  final double maxWeight;
  final int maxReps;
  final double totalVolume;

  const _DataPoint({
    required this.date,
    required this.maxWeight,
    required this.maxReps,
    required this.totalVolume,
  });
}

class _ExerciseSummary {
  final String exerciseId;
  final String name;
  final String equipmentType;

  const _ExerciseSummary({
    required this.exerciseId,
    required this.name,
    required this.equipmentType,
  });
}
