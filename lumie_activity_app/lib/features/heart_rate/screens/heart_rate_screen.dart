import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/heart_rate_models.dart';
import '../../ring/providers/ring_provider.dart';
import '../providers/heart_rate_provider.dart';

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});

  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startMeasurement(HeartRateProvider provider) {
    _pulseController.repeat(reverse: true);
    provider.startMeasurement();
  }

  void _stopMeasurement(HeartRateProvider provider) {
    _pulseController.stop();
    _pulseController.reset();
    provider.stopMeasurement();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Heart Rate',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Consumer<HeartRateProvider>(
            builder: (_, hr, _) => IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
              tooltip: 'Refresh history',
              onPressed: hr.loadingHistory ? null : hr.fetchDailyHistory,
            ),
          ),
        ],
      ),
      body: Consumer2<RingProvider, HeartRateProvider>(
        builder: (context, ring, hr, _) {
          if (!ring.isPaired) return _buildNoRingState();
          if (!ring.isConnected) return _buildDisconnectedState(ring);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTrendCard(hr),
                if (hr.dailyReadings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildStatsRow(hr),
                ],
                const SizedBox(height: 12),
                _buildMeasureCard(hr),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── No-ring banner ───────────────────────────────────────────────────────

  Widget _buildNoRingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.watch_off_outlined,
                size: 64, color: AppColors.textLight),
            const SizedBox(height: 16),
            const Text(
              'No ring connected',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your Lumie Ring to view heart rate data.',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectedState(RingProvider ring) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled,
                size: 64, color: AppColors.textLight),
            const SizedBox(height: 16),
            const Text(
              'Ring disconnected',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure your Lumie Ring is nearby and powered on.',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ring.tryReconnect(),
              icon: const Icon(Icons.refresh),
              label: const Text('Reconnect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Daily trend card ─────────────────────────────────────────────────────

  Widget _buildTrendCard(HeartRateProvider hr) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Heart Rate",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: hr.loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : hr.dailyReadings.isEmpty
                    ? _buildEmptyChart()
                    : _buildLineChart(hr.dailyReadings),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChart() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border, size: 36, color: AppColors.textLight),
          const SizedBox(height: 8),
          Text(
            'No readings yet today',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap "Measure Heart Rate" below to get started',
            style: TextStyle(fontSize: 12, color: AppColors.textLight),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<HrDataPoint> readings) {
    final spots = readings.map((p) {
      final minuteOfDay = p.time.hour * 60.0 + p.time.minute;
      return FlSpot(minuteOfDay, p.bpm.toDouble());
    }).toList();

    final bpms = readings.map((e) => e.bpm);
    final minBpm = bpms.reduce((a, b) => a < b ? a : b);
    final maxBpm = bpms.reduce((a, b) => a > b ? a : b);
    final yMin = ((minBpm - 15).clamp(30, 200)).toDouble();
    final yMax = ((maxBpm + 15).clamp(50, 250)).toDouble();

    return LineChart(
      LineChartData(
        minY: yMin,
        maxY: yMax,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: (yMax - yMin) / 3,
              getTitlesWidget: (value, _) => Text(
                '${value.toInt()}',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 120, // every 2 hours
              getTitlesWidget: (value, _) {
                final h = value.toInt() ~/ 60;
                final m = value.toInt() % 60;
                return Text(
                  '$h:${m.toString().padLeft(2, '0')}',
                  style:
                      TextStyle(fontSize: 9, color: AppColors.textSecondary),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: spots.length > 2,
            color: Colors.redAccent,
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 3,
                color: Colors.redAccent,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.redAccent.withValues(alpha: 0.08),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItems: (spots) => spots.map((spot) {
              final h = spot.x.toInt() ~/ 60;
              final m = spot.x.toInt() % 60;
              return LineTooltipItem(
                '${spot.y.toInt()} BPM\n$h:${m.toString().padLeft(2, '0')}',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ─── Stats row ────────────────────────────────────────────────────────────

  Widget _buildStatsRow(HeartRateProvider hr) {
    return Row(
      children: [
        _StatChip(label: 'Avg', value: '${hr.todayAvg} BPM'),
        const SizedBox(width: 8),
        _StatChip(label: 'Min', value: '${hr.todayMin} BPM'),
        const SizedBox(width: 8),
        _StatChip(label: 'Max', value: '${hr.todayMax} BPM'),
      ],
    );
  }

  // ─── Measure HR card ──────────────────────────────────────────────────────

  Widget _buildMeasureCard(HeartRateProvider hr) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: switch (hr.measureState) {
        HrMeasureState.idle => _buildIdleState(hr),
        HrMeasureState.measuring => _buildMeasuringState(hr),
        HrMeasureState.done => _buildDoneState(hr),
      },
    );
  }

  Widget _buildIdleState(HeartRateProvider hr) {
    return Column(
      children: [
        Icon(Icons.favorite_border, size: 40, color: Colors.redAccent),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _startMeasurement(hr),
          icon: const Icon(Icons.favorite),
          label: const Text('Measure Heart Rate'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeasuringState(HeartRateProvider hr) {
    return Column(
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: const Icon(Icons.favorite, size: 48, color: Colors.redAccent),
        ),
        const SizedBox(height: 16),
        Text(
          hr.liveHr != null ? '${hr.liveHr} BPM' : 'Measuring...',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => _stopMeasurement(hr),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: const Text('Stop'),
        ),
      ],
    );
  }

  Widget _buildDoneState(HeartRateProvider hr) {
    return Column(
      children: [
        const Icon(Icons.favorite, size: 40, color: Colors.redAccent),
        const SizedBox(height: 12),
        Text(
          hr.finalHr != null ? '${hr.finalHr} BPM' : '—',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Measured just now',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            _pulseController.reset();
            hr.resetMeasurement();
          },
          child: const Text(
            'Measure Again',
            style: TextStyle(color: Colors.redAccent, fontSize: 15),
          ),
        ),
      ],
    );
  }
}

// ─── Stat chip widget ──────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
