import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/sleep_service.dart';
import '../../../shared/models/sleep_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../widgets/sleep_stage_chart.dart';
import '../widgets/sleep_metric_card.dart';

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});

  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  final SleepService _sleepService = SleepService();

  SleepSession? _latestSleep;
  SleepTarget? _sleepTarget;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSleepData();
  }

  Future<void> _loadSleepData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _sleepService.getLatestSleep(),
        _sleepService.getSleepTarget(),
      ]);

      setState(() {
        _latestSleep = results[0] as SleepSession?;
        _sleepTarget = results[1] as SleepTarget;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildHeader(),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load sleep data',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadSleepData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_latestSleep == null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bedtime_outlined,
                        size: 80,
                        color: AppColors.textLight,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No sleep data yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Wear your Lumie Ring to track sleep',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSleepSummaryCard(),
                    const SizedBox(height: 16),
                    _buildSleepStagesCard(),
                    const SizedBox(height: 16),
                    _buildMetricsGrid(),
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
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sleep',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Rest & Recovery',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
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

  Widget _buildSleepSummaryCard() {
    if (_latestSleep == null) return const SizedBox();

    final hours = _latestSleep!.totalSleepTime.inHours;
    final minutes = _latestSleep!.totalSleepTime.inMinutes % 60;
    final targetHours = _sleepTarget?.targetDuration.inHours ?? 8;
    final targetMinutes = (_sleepTarget?.targetDuration.inMinutes ?? 480) % 60;

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
                _formatDateTime(_latestSleep!.wakeTime),
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
                '${_formatTime(_latestSleep!.bedtime)} - ${_formatTime(_latestSleep!.wakeTime)}',
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

  Widget _buildSleepStagesCard() {
    if (_latestSleep == null) return const SizedBox();

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
          SleepStageChart(session: _latestSleep!),
          const SizedBox(height: 16),
          _buildStageBreakdown(),
        ],
      ),
    );
  }

  Widget _buildStageBreakdown() {
    if (_latestSleep == null) return const SizedBox();

    return Column(
      children: [
        _buildStageRow(
          'Light Sleep',
          _latestSleep!.getStagePercentage(SleepStage.light),
          AppColors.primaryLemon,
        ),
        const SizedBox(height: 8),
        _buildStageRow(
          'Deep Sleep',
          _latestSleep!.getStagePercentage(SleepStage.deep),
          AppColors.accentMint,
        ),
        const SizedBox(height: 8),
        _buildStageRow(
          'REM Sleep',
          _latestSleep!.getStagePercentage(SleepStage.rem),
          AppColors.accentLavender,
        ),
      ],
    );
  }

  Widget _buildStageRow(String label, double percentage, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
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

  Widget _buildMetricsGrid() {
    if (_latestSleep == null) return const SizedBox();

    return Row(
      children: [
        Expanded(
          child: SleepMetricCard(
            title: 'Resting HR',
            value: '${_latestSleep!.restingHeartRate}',
            unit: 'bpm',
            icon: Icons.favorite_outline,
            gradient: AppColors.warmGradient,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SleepMetricCard(
            title: 'Sleep Quality',
            value: _latestSleep!.sleepQualityScore.toStringAsFixed(0),
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
        onPressed: () {
          // Navigate to sleep history
          Navigator.pushNamed(context, '/sleep/history');
        },
        icon: const Icon(Icons.history),
        label: const Text('View Sleep History'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (date == today) {
      return 'Today';
    } else if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
