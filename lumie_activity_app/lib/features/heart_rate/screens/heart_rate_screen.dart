import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
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
                _buildMeasureCard(hr),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── No-ring / disconnected banners ───────────────────────────────────────

  Widget _buildNoRingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.watch_off_outlined, size: 64, color: AppColors.textLight),
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
            Icon(Icons.bluetooth_disabled, size: 64, color: AppColors.textLight),
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
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
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
    final elapsed = hr.elapsed;
    final mm = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // BPM + pulse icon row
        if (hr.isWarmingUp)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: const Icon(Icons.favorite, size: 28, color: Colors.redAccent),
                ),
                const SizedBox(width: 10),
                Text(
                  'Measuring…',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ScaleTransition(
                scale: _pulseAnimation,
                child: const Icon(Icons.favorite, size: 36, color: Colors.redAccent),
              ),
              const SizedBox(width: 12),
              Text(
                '${hr.liveHr}',
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'BPM',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        // Elapsed time
        Center(
          child: Text(
            '$mm:$ss',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Live session graph
        SizedBox(
          height: 160,
          child: hr.sessionReadings.length < 2
              ? Center(
                  child: Text(
                    'Waiting for readings…',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                )
              : _buildSessionChart(hr),
        ),
        const SizedBox(height: 8),
        // Session stats (only once we have data)
        if (hr.sessionReadings.isNotEmpty)
          _buildSessionStatsRow(hr),
        const SizedBox(height: 20),
        // Stop button
        OutlinedButton(
          onPressed: () => _stopMeasurement(hr),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: const Text(
            'Stop',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneState(HeartRateProvider hr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Final BPM
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Icon(Icons.favorite, size: 32, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text(
              hr.sessionAvg != null ? '${hr.sessionAvg}' : '—',
              style: const TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'BPM avg',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _formatElapsed(hr.elapsed),
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 20),
        // Session graph
        if (hr.sessionReadings.length >= 2) ...[
          SizedBox(height: 160, child: _buildSessionChart(hr)),
          const SizedBox(height: 8),
        ],
        // Stats
        if (hr.sessionReadings.isNotEmpty) _buildSessionStatsRow(hr),
        const SizedBox(height: 20),
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

  // ─── Session chart ────────────────────────────────────────────────────────

  Widget _buildSessionChart(HeartRateProvider hr) {
    final readings = hr.sessionReadings;
    if (readings.length < 2) return const SizedBox.shrink();

    final origin = readings.first.time;
    final spots = readings.map((p) {
      final secs = p.time.difference(origin).inSeconds.toDouble();
      return FlSpot(secs, p.smoothedBpm);
    }).toList();

    final bpms = readings.map((e) => e.smoothedBpm);
    final minBpm = bpms.reduce((a, b) => a < b ? a : b);
    final maxBpm = bpms.reduce((a, b) => a > b ? a : b);
    final yMin = ((minBpm - 10).clamp(30, 200)).toDouble();
    final yMax = ((maxBpm + 10).clamp(50, 250)).toDouble();
    final totalSecs = spots.last.x;

    return LineChart(
      LineChartData(
        minY: yMin,
        maxY: yMax,
        minX: 0,
        maxX: totalSecs > 0 ? totalSecs : 1,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (yMax - yMin) / 3,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.textLight.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
              interval: _sessionXInterval(totalSecs),
              getTitlesWidget: (value, _) {
                final m = (value ~/ 60).toString().padLeft(1, '0');
                final s = (value.toInt() % 60).toString().padLeft(2, '0');
                return Text(
                  '$m:$s',
                  style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.redAccent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.redAccent.withValues(alpha: 0.25),
                  Colors.redAccent.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItems: (spots) => spots.map((spot) {
              final m = spot.x.toInt() ~/ 60;
              final s = spot.x.toInt() % 60;
              return LineTooltipItem(
                '${spot.y.toInt()} BPM\n$m:${s.toString().padLeft(2, '0')}',
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

  double _sessionXInterval(double totalSecs) {
    if (totalSecs <= 120) return 30;
    if (totalSecs <= 600) return 120;
    if (totalSecs <= 1800) return 300;
    return 600;
  }

  Widget _buildSessionStatsRow(HeartRateProvider hr) {
    return Row(
      children: [
        _StatChip(label: 'Avg', value: '${hr.sessionAvg ?? '—'} BPM'),
        const SizedBox(width: 8),
        _StatChip(label: 'Min', value: '${hr.sessionMin ?? '—'} BPM'),
        const SizedBox(width: 8),
        _StatChip(label: 'Max', value: '${hr.sessionMax ?? '—'} BPM'),
      ],
    );
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h ${m}m ${s}s' : '${m}m ${s}s';
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
