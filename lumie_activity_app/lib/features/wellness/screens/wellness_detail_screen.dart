import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/sleep_models.dart';
import '../../../shared/models/wellness_models.dart';
import '../providers/wellness_provider.dart';

enum WellnessMetric { fatigue, stress }

class WellnessDetailScreen extends StatelessWidget {
  final WellnessMetric metric;

  const WellnessDetailScreen({super.key, required this.metric});

  // ─── Strings ──────────────────────────────────────────────────────────────

  String get _title => metric == WellnessMetric.fatigue ? 'Fatigue' : 'Stress';

  String _levelDescription(WellnessState state) {
    return metric == WellnessMetric.fatigue
        ? state.fatigue.fullLabel
        : state.stress.fullLabel;
  }

  Color _levelColor(WellnessState state) {
    return metric == WellnessMetric.fatigue
        ? state.fatigue.color
        : state.stress.color;
  }

  bool _hasData(WellnessState state) {
    return metric == WellnessMetric.fatigue
        ? state.fatigue.hasData
        : state.stress.hasData;
  }

  String _explanationText(WellnessState state) {
    if (metric == WellnessMetric.fatigue) {
      return switch (state.fatigue.level) {
        FatigueLevel.low =>
          'Your body is recovering well. Sleep quality and resting heart rate '
              'are within your normal range.',
        FatigueLevel.moderate =>
          'Some recovery strain detected over the last 3 nights. Consider '
              'lighter activity today and prioritise sleep.',
        FatigueLevel.elevated =>
          'Significant fatigue markers detected. Rest today and aim for '
              '8–10 hours of sleep. Avoid intense workouts.',
        _ => '',
      };
    } else {
      return switch (state.stress.level) {
        StressLevel.lower =>
          'Your stress indicators are lower than your usual baseline — '
              'great sleep and a calm heart rate.',
        StressLevel.typical =>
          'Stress indicators are within your normal range based on recent '
              'sleep and resting heart rate patterns.',
        StressLevel.higher =>
          'Elevated stress markers detected. This may reflect poor sleep '
              'quality or an elevated resting heart rate. Breathing exercises '
              'or light activity can help.',
        _ => '',
      };
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<WellnessProvider>(
      builder: (context, wellness, _) {
        final state = wellness.state;
        final ctx = wellness.context;
        return Scaffold(
          backgroundColor: AppColors.backgroundWhite,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundWhite,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: const BackButton(color: AppColors.textPrimary),
            title: Text(
              _title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(state),
                  const SizedBox(height: 20),
                  if (_hasData(state) && ctx != null) ...[
                    _buildFactorsCard(ctx),
                    const SizedBox(height: 20),
                  ],
                  if (wellness.recentSessions.isNotEmpty) ...[
                    _buildTrendCard(wellness.recentSessions),
                    const SizedBox(height: 20),
                  ],
                  if (_hasData(state)) _buildExplanationCard(state),
                  if (!_hasData(state)) _buildCalibrationCard(state),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Status card ──────────────────────────────────────────────────────────

  Widget _buildStatusCard(WellnessState state) {
    final color = _levelColor(state);
    final label = _levelDescription(state);
    final hasData = _hasData(state);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(
            metric == WellnessMetric.fatigue
                ? Icons.battery_charging_full
                : Icons.self_improvement,
            size: 40,
            color: color,
          ),
          const SizedBox(height: 12),
          Text(
            hasData
                ? label
                : (state.fatigue.level == FatigueLevel.calibrating
                      ? 'Learning your baseline'
                      : 'No data available'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (state.calculatedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              _formatRelativeTime(state.calculatedAt!),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Contributing factors ─────────────────────────────────────────────────

  Widget _buildFactorsCard(WellnessContext ctx) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contributing factors',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          _buildFactor(
            label: 'Resting HR',
            recent: '${ctx.recentRhr.round()} bpm',
            baseline: '${ctx.baselineRhr.round()} bpm',
            delta: ctx.rhrDelta,
            higherIsBad: true,
          ),
          const Divider(height: 24, color: AppColors.surfaceLight),
          _buildFactor(
            label: 'Sleep quality',
            recent: '${ctx.recentQuality.round()}%',
            baseline: '${ctx.baselineQuality.round()}%',
            delta: ctx.qualityDelta,
            higherIsBad: false,
          ),
          const Divider(height: 24, color: AppColors.surfaceLight),
          _buildFactor(
            label: 'Sleep duration',
            recent: _formatHours(ctx.recentHours),
            baseline: _formatHours(ctx.baselineHours),
            delta: ctx.hoursDelta,
            higherIsBad: false,
          ),
          const SizedBox(height: 8),
          Text(
            'Baseline from ${ctx.nightsInBaseline} nights of data.',
            style: const TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildFactor({
    required String label,
    required String recent,
    required String baseline,
    required double delta,
    required bool higherIsBad,
  }) {
    final isWorse = higherIsBad ? delta > 1 : delta < -1;
    final isBetter = higherIsBad ? delta < -1 : delta > 1;
    final Color indicatorColor;
    final IconData indicatorIcon;

    if (isWorse) {
      indicatorColor = const Color(0xFFE57373);
      indicatorIcon = higherIsBad ? Icons.arrow_upward : Icons.arrow_downward;
    } else if (isBetter) {
      indicatorColor = const Color(0xFF81C784);
      indicatorIcon = higherIsBad ? Icons.arrow_downward : Icons.arrow_upward;
    } else {
      indicatorColor = AppColors.textSecondary;
      indicatorIcon = Icons.remove;
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Baseline: $baseline',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              recent,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: indicatorColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(indicatorIcon, size: 14, color: indicatorColor),
          ],
        ),
      ],
    );
  }

  // ─── 7-night trend ────────────────────────────────────────────────────────

  Widget _buildTrendCard(List<SleepSession> sessions) {
    // Show at most 7 most recent nights, sorted oldest first for left-to-right display
    final nights = sessions.take(7).toList().reversed.toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent nights',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          ...nights.map((s) => _buildNightRow(s)),
        ],
      ),
    );
  }

  Widget _buildNightRow(SleepSession session) {
    final quality = session.sleepQualityScore;
    final Color barColor;
    if (quality >= 75) {
      barColor = const Color(0xFF81C784);
    } else if (quality >= 50) {
      barColor = const Color(0xFFFFB74D);
    } else {
      barColor = const Color(0xFFE57373);
    }

    final dateLabel = _shortDate(session.wakeTime);
    final hours = session.totalSleepTime.inHours;
    final mins = session.totalSleepTime.inMinutes % 60;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              dateLabel,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (quality / 100).clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              mins > 0 ? '${hours}h ${mins}m' : '${hours}h',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Explanation / calibration cards ──────────────────────────────────────

  Widget _buildExplanationCard(WellnessState state) {
    final text = _explanationText(state);
    if (text.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrationCard(WellnessState state) {
    final isCalibrating = metric == WellnessMetric.fatigue
        ? state.fatigue.level == FatigueLevel.calibrating
        : state.stress.level == StressLevel.calibrating;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        children: [
          Icon(
            isCalibrating
                ? Icons.nights_stay_outlined
                : Icons.ring_volume_outlined,
            size: 36,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 12),
          Text(
            isCalibrating
                ? 'Lumie is learning your baseline'
                : 'No sleep data from your ring yet',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isCalibrating
                ? 'Keep wearing your ring while you sleep. '
                      'Fatigue and stress signals appear after 5 nights of tracked sleep.'
                : 'Wear your Lumie Ring to sleep to start tracking fatigue and stress.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textLight,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inHours < 1) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  String _formatHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  String _shortDate(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}
