import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/sleep_models.dart';
import '../../ring/providers/ring_provider.dart';
import '../providers/sleep_provider.dart';
import '../widgets/sleep_stage_chart.dart';

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});

  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  bool _lastConnected = false;
  RingProvider? _ringProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SleepProvider>().load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rp = Provider.of<RingProvider>(context, listen: false);
    if (_ringProvider != rp) {
      _ringProvider?.removeListener(_onRingStateChanged);
      _ringProvider = rp;
      _lastConnected = rp.isConnected;
      rp.addListener(_onRingStateChanged);
    }
  }

  void _onRingStateChanged() {
    if (!mounted) return;
    final connected = _ringProvider?.isConnected ?? false;
    if (connected && !_lastConnected) {
      _reloadAfterRingSync();
    }
    _lastConnected = connected;
  }

  Future<void> _reloadAfterRingSync() async {
    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 10));
    if (!mounted) return;
    context.read<SleepProvider>().load();
  }

  @override
  void dispose() {
    _ringProvider?.removeListener(_onRingStateChanged);
    super.dispose();
  }

  // ─── Formatting helpers ───────────────────────────────────────────────────

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _formatFullDate(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months   = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                       'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  /// Non-alarming quality description — never uses "bad", "poor", or "failed".
  String _qualityDescription(double score) {
    if (score >= 80) return 'Better than your recent average';
    if (score >= 65) return 'Similar to your recent average';
    if (score >= 50) return 'Slightly below your usual';
    return 'Below your usual';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<SleepProvider>(
      builder: (context, sleep, _) {
        return Scaffold(
          backgroundColor: AppColors.backgroundPaper,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                _buildHeader(sleep),
                if (sleep.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (sleep.latestSleep == null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildNoData(),
                        const SizedBox(height: 16),
                        _buildViewHistoryButton(),
                      ]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 20),
                        _buildQualityScoreCard(sleep.latestSleep!),
                        const SizedBox(height: 16),
                        _buildTimelineCard(sleep.latestSleep!),
                        const SizedBox(height: 16),
                        _buildMetricsCard(sleep.latestSleep!),
                        const SizedBox(height: 16),
                        _buildViewHistoryButton(),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(SleepProvider sleep) {
    final syncedAt = sleep.lastSyncedAt;
    String? syncLabel;
    bool incomplete = false;
    if (syncedAt != null) {
      incomplete = !sleep.lastSyncWasComplete;
      final mins = DateTime.now().difference(syncedAt).inMinutes;
      final ago = mins < 1 ? 'just now' : '${mins}m ago';
      syncLabel = incomplete ? 'Sync incomplete · $ago' : 'Synced $ago';
    }

    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        color: AppColors.backgroundPaper,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLemon,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.bedtime,
                color: AppColors.textOnYellow,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sleep',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (syncLabel != null)
                    Row(
                      children: [
                        Icon(
                          incomplete
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          size: 11,
                          color: incomplete ? AppColors.warning : AppColors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          syncLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: incomplete
                                ? AppColors.warning
                                : AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── No-data state ────────────────────────────────────────────────────────

  Widget _buildNoData() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bedtime_outlined, size: 72, color: AppColors.textLight),
          SizedBox(height: 20),
          Text(
            'No sleep data',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Wear your Lumie Ring to bed to see your sleep stages and quality score.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textLight, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ─── Quality score ────────────────────────────────────────────────────────

  Widget _buildQualityScoreCard(SleepSession session) {
    final score = session.sleepQualityScore;
    final description = _qualityDescription(score);
    final dateLabel = _formatFullDate(session.bedtime);

    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Score circle
          _ScoreRing(score: score),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sleep Quality',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.bedtime_outlined,
                        size: 14, color: AppColors.textLight),
                    const SizedBox(width: 6),
                    Text(
                      '${_formatTime(session.bedtime)} – ${_formatTime(session.wakeTime)}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Timeline + stage breakdown ───────────────────────────────────────────

  Widget _buildTimelineCard(SleepSession session) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sleep Stages',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SleepTimelineChart(session: session),
          const SizedBox(height: 20),
          _buildStageBreakdown(session),
        ],
      ),
    );
  }

  Widget _buildStageBreakdown(SleepSession session) {
    final totalMinutes = session.totalSleepTime.inMinutes;

    // Order: Awake → Light → REM → Deep (lightest to deepest per spec)
    final rows = <_StageRow>[
      _StageRow(
        stage: SleepStage.awake,
        label: 'Awake',
        color: const Color(0xFFE0E0E0),
        duration: session.timeAwake,
        pct: totalMinutes > 0
            ? (session.timeAwake.inMinutes / totalMinutes * 100).round()
            : 0,
      ),
      _StageRow(
        stage: SleepStage.light,
        label: 'Light Sleep',
        color: SleepStageColors.light,
        duration: session.getStageDuration(SleepStage.light),
        pct: session.getStagePercentage(SleepStage.light).round(),
      ),
      _StageRow(
        stage: SleepStage.rem,
        label: 'REM Sleep',
        color: SleepStageColors.rem,
        duration: session.getStageDuration(SleepStage.rem),
        pct: session.getStagePercentage(SleepStage.rem).round(),
      ),
      _StageRow(
        stage: SleepStage.deep,
        label: 'Deep Sleep',
        color: SleepStageColors.deep,
        duration: session.getStageDuration(SleepStage.deep),
        pct: session.getStagePercentage(SleepStage.deep).round(),
      ),
    ];

    return Column(
      children: rows
          .where((r) => r.duration.inMinutes > 0)
          .map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: r.color,
                        shape: BoxShape.circle,
                        border: r.stage == SleepStage.awake
                            ? Border.all(color: AppColors.surfaceLight, width: 1)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.label,
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                    Text(
                      _formatDuration(r.duration),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${r.pct}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textLight),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ─── Metrics ──────────────────────────────────────────────────────────────

  Widget _buildMetricsCard(SleepSession session) {
    final efficiency = session.sleepEfficiency;
    final wakeCount = session.wakeCount;

    final metrics = [
      _Metric(
        label: 'Total Sleep',
        value: _formatDuration(session.totalSleepTime),
        icon: Icons.bedtime_outlined,
      ),
      _Metric(
        label: 'Time in Bed',
        value: _formatDuration(session.totalTimeInBed),
        icon: Icons.hotel_outlined,
      ),
      _Metric(
        label: 'Efficiency',
        value: '${efficiency.toStringAsFixed(0)}%',
        icon: Icons.show_chart,
      ),
      _Metric(
        label: 'Sleep Window',
        value: '${_formatTime(session.bedtime)} – ${_formatTime(session.wakeTime)}',
        icon: Icons.access_time_outlined,
        wide: true,
      ),
      _Metric(
        label: 'Wake-ups',
        value: wakeCount == 0 ? 'None' : '$wakeCount',
        icon: Icons.nightlight_round,
      ),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sleep Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // 2-column grid; "wide" metrics span full width
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: metrics.map((m) {
              final halfWidth = (MediaQuery.of(context).size.width - 40 - 40 - 12) / 2;
              return SizedBox(
                width: m.wide
                    ? double.infinity
                    : halfWidth,
                child: _MetricTile(metric: m),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── History button ───────────────────────────────────────────────────────

  Widget _buildViewHistoryButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(context, '/sleep/history'),
        icon: const Icon(Icons.history),
        label: const Text('View Sleep History'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

// ─── Internal helper models ────────────────────────────────────────────────

class _StageRow {
  final SleepStage stage;
  final String label;
  final Color color;
  final Duration duration;
  final int pct;

  const _StageRow({
    required this.stage,
    required this.label,
    required this.color,
    required this.duration,
    required this.pct,
  });
}

class _Metric {
  final String label;
  final String value;
  final IconData icon;
  final bool wide;

  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    this.wide = false,
  });
}

// ─── Reusable sub-widgets ─────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}

/// Circular arc showing the sleep quality score (0–100).
class _ScoreRing extends StatelessWidget {
  final double score;

  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0.0, 100.0);

    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background track
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 6,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.backgroundLight),
            ),
          ),
          // Score arc
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: clamped / 100,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(
                _arcColor(clamped),
              ),
            ),
          ),
          // Score number
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                clamped.round().toString(),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  height: 1.0,
                ),
              ),
              const Text(
                'pts',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _arcColor(double score) {
    if (score >= 80) return const Color(0xFF4ADE80);  // green
    if (score >= 65) return const Color(0xFFF9A825);  // amber
    return const Color(0xFFF87171);                   // red
  }
}

class _MetricTile extends StatelessWidget {
  final _Metric metric;

  const _MetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(metric.icon, size: 16, color: AppColors.textLight),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  metric.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metric.value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
