import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/sleep_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../ring/providers/ring_provider.dart';
import '../providers/sleep_provider.dart';
import '../widgets/sleep_stage_chart.dart';
import '../widgets/sleep_metric_card.dart';

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
    // Trigger a fresh backend read on mount (SleepProvider debounces concurrent calls).
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
      // RingProvider already started a background sleep sync (0x53 + 0x55).
      // Wait for it to finish uploading, then reload from the backend.
      _reloadAfterRingSync();
    }
    _lastConnected = connected;
  }

  Future<void> _reloadAfterRingSync() async {
    if (!mounted) return;
    // Give the background sync in RingProvider up to 10 s to complete.
    await Future.delayed(const Duration(seconds: 10));
    if (!mounted) return;
    context.read<SleepProvider>().load();
  }

  @override
  void dispose() {
    _ringProvider?.removeListener(_onRingStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SleepProvider>(
      builder: (context, sleep, _) {
        return Scaffold(
          backgroundColor: AppColors.backgroundWhite,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                _buildHeader(sleep),
                if (sleep.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (sleep.latestSleep == null)
                  _buildNoData()
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildSleepSummaryCard(sleep),
                        const SizedBox(height: 16),
                        _buildSleepStagesCard(sleep.latestSleep!),
                        const SizedBox(height: 16),
                        _buildMetricsGrid(sleep.latestSleep!),
                        const SizedBox(height: 16),
                        _buildViewHistoryButton(),
                        const SizedBox(height: 24),
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
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppColors.coolGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bedtime,
                    color: AppColors.textOnYellow,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sleep',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Text(
                        'Rest & Recovery',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (syncLabel != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              incomplete
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline,
                              size: 12,
                              color: incomplete
                                  ? AppColors.warning
                                  : AppColors.success,
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
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoData() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bedtime_outlined, size: 80, color: AppColors.textLight),
            const SizedBox(height: 16),
            const Text(
              'No sleep data recorded',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Wear your Lumie Ring to track sleep',
              style: TextStyle(fontSize: 14, color: AppColors.textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepSummaryCard(SleepProvider sleep) {
    final session = sleep.latestSleep!;
    final hours = session.totalSleepTime.inHours;
    final minutes = session.totalSleepTime.inMinutes % 60;
    final targetHours = sleep.sleepTarget?.targetDuration.inHours ?? 8;
    final targetMinutes =
        (sleep.sleepTarget?.targetDuration.inMinutes ?? 480) % 60;

    return GradientCard(
      gradient: AppColors.coolGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Last Night',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textOnYellow,
                ),
              ),
              const Spacer(),
              Text(
                _formatFullDate(session.bedtime),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textOnYellow.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${hours}h ${minutes}m',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textOnYellow,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'of ${targetHours}h ${targetMinutes}m target',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textOnYellow.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.bedtime_outlined,
                size: 16,
                color: AppColors.textOnYellow.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatTime(session.bedtime)} – ${_formatTime(session.wakeTime)}',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textOnYellow.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSleepStagesCard(SleepSession session) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
          SleepStageChart(session: session),
          const SizedBox(height: 16),
          _buildStageRow(
            'Light Sleep',
            session.getStagePercentage(SleepStage.light),
            AppColors.primaryLemon,
          ),
          const SizedBox(height: 8),
          _buildStageRow(
            'Deep Sleep',
            session.getStagePercentage(SleepStage.deep),
            AppColors.accentMint,
          ),
          const SizedBox(height: 8),
          _buildStageRow(
            'REM Sleep',
            session.getStagePercentage(SleepStage.rem),
            AppColors.accentLavender,
          ),
        ],
      ),
    );
  }

  Widget _buildStageRow(String label, double percentage, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
        ),
        Text(
          '${percentage.toStringAsFixed(0)}%',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsGrid(SleepSession session) {
    final hasRhr = session.restingHeartRate > 0;
    return Row(
      children: [
        if (hasRhr) ...[
          Expanded(
            child: SleepMetricCard(
              title: 'Resting HR',
              value: '${session.restingHeartRate}',
              unit: 'bpm',
              icon: Icons.favorite_outline,
              gradient: AppColors.warmGradient,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: SleepMetricCard(
            title: 'Sleep Quality',
            value: session.sleepQualityScore.toStringAsFixed(0),
            unit: '%',
            icon: Icons.star_outline,
            gradient: AppColors.mintGradient,
          ),
        ),
      ],
    );
  }

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

  String _formatFullDate(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  String _formatTime(DateTime dt) {
    final hour =
        dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
