import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/stress_models.dart';
import '../providers/stress_provider.dart';
import '../widgets/stress_timeline_chart.dart';
import '../widgets/stress_week_chart.dart';

/// Full-screen stress detail page.
///
/// Shows the day's stress timeline, zone time breakdown, daily insight,
/// 7-day trend, and calibration / no-data states.
class StressDetailScreen extends StatefulWidget {
  const StressDetailScreen({super.key});

  @override
  State<StressDetailScreen> createState() => _StressDetailScreenState();
}

class _StressDetailScreenState extends State<StressDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StressProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const BackButton(color: AppColors.textPrimary),
        title: const Text(
          'Stress',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Consumer<StressProvider>(
        builder: (context, stress, _) {
          if (stress.isLoading && stress.today == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryLemonDark),
            );
          }

          // No baseline yet — calibration state
          if (!stress.hasBaseline) {
            return _buildCalibrationState(stress.baselineDays);
          }

          // No data for today
          if (!stress.hasData) {
            return _buildNoDataState();
          }

          final today = stress.today!;
          final week = stress.weekData;

          return RefreshIndicator(
            color: AppColors.primaryLemonDark,
            onRefresh: () => stress.load(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current zone badge
                  _buildCurrentZoneBadge(today),
                  const SizedBox(height: 20),

                  // Timeline chart
                  _buildTimelineSection(today),
                  const SizedBox(height: 24),

                  // Zone time breakdown
                  _buildTimeBreakdown(today),
                  const SizedBox(height: 24),

                  // Daily insight
                  if (today.insight != null) ...[
                    _buildInsightCard(today.insight!),
                    const SizedBox(height: 24),
                  ],

                  // 7-day trend
                  if (week != null && week.days.isNotEmpty) ...[
                    _buildWeekTrend(week),
                    const SizedBox(height: 24),
                  ],

                  // Zone legend
                  _buildZoneLegend(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Score + current zone badge ─────────────────────────────────────────────

  Widget _buildCurrentZoneBadge(StressDaySummary today) {
    final zone = today.currentZone;
    final avgZone = today.averageZone;
    final zoneColor = zone?.displayColor ?? avgZone.displayColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (zone?.chartColor ?? avgZone.chartColor).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: zoneColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Score circle
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: zoneColor.withValues(alpha: 0.15),
              border: Border.all(color: zoneColor, width: 2.5),
            ),
            child: Center(
              child: Text(
                '${today.score}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: zoneColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: zone?.chartColor ?? avgZone.chartColor,
                        borderRadius: BorderRadius.circular(3),
                        border: (zone ?? avgZone) == StressZone.restored
                            ? Border.all(color: AppColors.surfaceLight)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      today.scoreLabel,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: zoneColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (zone != null)
                  Text(
                    'Currently ${zone.label.toLowerCase()} — ${zone.description.toLowerCase()}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Timeline chart section ────────────────────────────────────────────────

  Widget _buildTimelineSection(StressDaySummary today) {
    return Container(
      padding: const EdgeInsets.all(16),
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
            'Today\'s Stress Timeline',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Long press to see details',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 16),
          StressTimelineChart(
            readings: today.timeline,
            height: 180,
          ),
        ],
      ),
    );
  }

  // ─── Time breakdown ────────────────────────────────────────────────────────

  Widget _buildTimeBreakdown(StressDaySummary today) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Time in Each Zone',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 12),
        // Primary: Stressed + Restored (large cards)
        Row(
          children: [
            Expanded(
              child: _ZoneStatCard(
                zone: StressZone.stressed,
                duration: today.stressedTime,
                isPrimary: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ZoneStatCard(
                zone: StressZone.restored,
                duration: today.restoredTime,
                isPrimary: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Secondary: Engaged + Relaxed (smaller cards)
        Row(
          children: [
            Expanded(
              child: _ZoneStatCard(
                zone: StressZone.engaged,
                duration: today.engagedTime,
                isPrimary: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ZoneStatCard(
                zone: StressZone.relaxed,
                duration: today.relaxedTime,
                isPrimary: false,
              ),
            ),
          ],
        ),
        // Exercise time (if any)
        if (today.activeTime.inMinutes > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.directions_run, size: 14, color: AppColors.textLight),
              const SizedBox(width: 6),
              Text(
                '${_formatDuration(today.activeTime)} exercise (excluded from stress)',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textLight,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Insight card ──────────────────────────────────────────────────────────

  Widget _buildInsightCard(String insight) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline,
            size: 18,
            color: Color(0xFFD97706),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Insight',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF78350F),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 7-day trend ───────────────────────────────────────────────────────────

  Widget _buildWeekTrend(StressWeekData week) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '7-Day Trend',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              // Reference legend
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 1,
                    color: AppColors.textLight.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '65 — Relaxed',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a day for details',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 16),
          StressWeekChart(
            days: week.days,
            height: 140,
          ),
          if (week.trendLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.trending_flat,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      week.trendLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Zone legend ───────────────────────────────────────────────────────────

  Widget _buildZoneLegend() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About Stress Zones',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          ...StressZone.values.map((zone) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: zone.chartColor,
                        borderRadius: BorderRadius.circular(3),
                        border: zone == StressZone.restored
                            ? Border.all(color: AppColors.surfaceLight)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      zone.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        zone.description,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 6),
          const Text(
            'Stress is measured using HR and HRV data from your ring, '
            'compared to your personal overnight baseline. '
            'Exercise periods are excluded.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textLight,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── No-data / calibration states ──────────────────────────────────────────

  Widget _buildCalibrationState(int daysCollected) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.nights_stay_outlined,
              size: 56,
              color: AppColors.textLight,
            ),
            const SizedBox(height: 20),
            const Text(
              'Lumie is learning your stress baseline',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Check back in a few days — stress zones appear '
              'after 5 nights of tracked sleep data.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Progress indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final filled = i < daysCollected;
                      return Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: filled
                              ? AppColors.primaryLemonDark
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: filled
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$daysCollected of 5 days collected',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.watch_off_outlined,
              size: 56,
              color: AppColors.textLight,
            ),
            const SizedBox(height: 20),
            const Text(
              'No stress data for today',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Make sure your ring is connected and synced. '
              'Stress data updates every 15 minutes while the ring is worn.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }
}

// ─── Zone stat card widget ───────────────────────────────────────────────────

class _ZoneStatCard extends StatelessWidget {
  final StressZone zone;
  final Duration duration;
  final bool isPrimary;

  const _ZoneStatCard({
    required this.zone,
    required this.duration,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final durationStr = h > 0 ? '${h}h ${m}m' : '${m}m';

    return Container(
      padding: EdgeInsets.all(isPrimary ? 16 : 12),
      decoration: BoxDecoration(
        color: zone.chartColor.withValues(alpha: isPrimary ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: zone.displayColor.withValues(alpha: isPrimary ? 0.25 : 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isPrimary ? 10 : 8,
                height: isPrimary ? 10 : 8,
                decoration: BoxDecoration(
                  color: zone.chartColor,
                  borderRadius: BorderRadius.circular(3),
                  border: zone == StressZone.restored
                      ? Border.all(color: AppColors.surfaceLight, width: 0.5)
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                zone.label,
                style: TextStyle(
                  fontSize: isPrimary ? 13 : 11,
                  fontWeight: FontWeight.w600,
                  color: zone.displayColor,
                ),
              ),
            ],
          ),
          SizedBox(height: isPrimary ? 8 : 4),
          Text(
            durationStr,
            style: TextStyle(
              fontSize: isPrimary ? 24 : 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
