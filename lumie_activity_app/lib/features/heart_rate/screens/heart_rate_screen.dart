import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_colors.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/task_service.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/models/task_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../../manual_entry/widgets/activity_type_selector.dart';
import '../../ring/providers/ring_provider.dart';
import '../providers/heart_rate_provider.dart';
import '../screens/hr_history_screen.dart';
import '../widgets/hr_session_chart.dart';

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});

  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _disconnectConfirmDelay = Duration(seconds: 15);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  RingProvider? _ringProvider;
  Timer? _disconnectConfirmTimer;
  bool _isDisconnectedConfirmed = false;
  final GlobalKey _hrChartKey = GlobalKey();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.profile?.age == null) {
        auth.refreshProfile();
      }
    });
  }

  @override
  void dispose() {
    _disconnectConfirmTimer?.cancel();
    _ringProvider?.removeListener(_onRingConnectionChanged);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ring = context.read<RingProvider>();
    if (_ringProvider == ring) return;
    _ringProvider?.removeListener(_onRingConnectionChanged);
    _ringProvider = ring;
    _ringProvider?.addListener(_onRingConnectionChanged);
    _syncDisconnectUiState();
  }

  void _onRingConnectionChanged() {
    _syncDisconnectUiState();
  }

  void _syncDisconnectUiState() {
    final ring = _ringProvider;
    if (!mounted || ring == null) return;

    if (!ring.isPaired || ring.isConnected) {
      _disconnectConfirmTimer?.cancel();
      _disconnectConfirmTimer = null;
      if (_isDisconnectedConfirmed) {
        setState(() => _isDisconnectedConfirmed = false);
      }
      return;
    }

    if (_disconnectConfirmTimer?.isActive ?? false) return;

    _disconnectConfirmTimer = Timer(_disconnectConfirmDelay, () {
      if (!mounted) return;
      final stillDisconnected =
          _ringProvider?.isPaired == true &&
          !(_ringProvider?.isConnected ?? false);
      if (stillDisconnected && !_isDisconnectedConfirmed) {
        setState(() => _isDisconnectedConfirmed = true);
      }
    });
  }

  void _startMeasurement(HeartRateProvider provider) {
    _pulseController.repeat(reverse: true);
    provider.startMeasurement();
  }

  void _pauseMeasurement(HeartRateProvider provider) {
    _pulseController.stop();
    provider.pauseMeasurement();
  }

  void _resumeMeasurement(HeartRateProvider provider) {
    _pulseController.repeat(reverse: true);
    provider.resumeMeasurement();
  }

  void _stopMeasurement(HeartRateProvider provider) {
    _pulseController.stop();
    _pulseController.reset();

    // Capture before stopMeasurement clears state
    final startedAt = provider.measurementStartedAt;
    final endedAt = DateTime.now();
    final avgBpm = provider.sessionAvg;
    final maxBpm = provider.sessionMax;

    provider.stopMeasurement();

    if (startedAt != null && avgBpm != null) {
      _showActivityPrompt(
        startedAt: startedAt,
        endedAt: endedAt,
        avgBpm: avgBpm,
        maxBpm: maxBpm,
      );
    }
  }

  void _showActivityPrompt({
    required DateTime startedAt,
    required DateTime endedAt,
    required int avgBpm,
    int? maxBpm,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActivityPromptSheet(
        startedAt: startedAt,
        endedAt: endedAt,
        avgBpm: avgBpm,
        maxBpm: maxBpm,
        chartKey: _hrChartKey,
      ),
    );
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
          IconButton(
            icon: const Icon(Icons.history, color: AppColors.textSecondary),
            tooltip: 'Session history',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HrHistoryScreen()),
            ),
          ),
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
          final showDisconnectedInPlace =
              !ring.isConnected && _isDisconnectedConfirmed;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMeasureCard(
                  hr,
                  isRingConnected: ring.isConnected,
                  showDisconnectedInPlace: showDisconnectedInPlace,
                  onReconnect: ring.tryReconnect,
                ),
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
            Icon(
              Icons.watch_off_outlined,
              size: 64,
              color: AppColors.textLight,
            ),
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

  // ─── Daily trend card ─────────────────────────────────────────────────────

  // ─── Measure HR card ──────────────────────────────────────────────────────

  Widget _buildMeasureCard(
    HeartRateProvider hr, {
    required bool isRingConnected,
    required bool showDisconnectedInPlace,
    required VoidCallback onReconnect,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: switch (hr.measureState) {
        HrMeasureState.idle => _buildIdleState(
          hr,
          isRingConnected: isRingConnected,
          showDisconnectedInPlace: showDisconnectedInPlace,
          onReconnect: onReconnect,
        ),
        HrMeasureState.measuring => _buildMeasuringState(
          hr,
          isRingConnected: isRingConnected,
          showDisconnectedInPlace: showDisconnectedInPlace,
        ),
        HrMeasureState.paused => _buildPausedState(
          hr,
          isRingConnected: isRingConnected,
        ),
        HrMeasureState.done => _buildDoneState(hr),
      },
    );
  }

  Widget _buildIdleState(
    HeartRateProvider hr, {
    required bool isRingConnected,
    required bool showDisconnectedInPlace,
    required VoidCallback onReconnect,
  }) {
    return Column(
      children: [
        Icon(Icons.favorite_border, size: 40, color: Colors.redAccent),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: isRingConnected ? () => _startMeasurement(hr) : null,
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
        if (showDisconnectedInPlace) ...[
          const SizedBox(height: 14),
          Text(
            'Ring disconnected',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onReconnect, child: const Text('Reconnect')),
        ],
      ],
    );
  }

  Widget _buildMeasuringState(
    HeartRateProvider hr, {
    required bool isRingConnected,
    required bool showDisconnectedInPlace,
  }) {
    final elapsed = hr.timelineElapsed;
    final mm = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // BPM + pulse icon row
        if (hr.isWarmingUp && isRingConnected && !showDisconnectedInPlace)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: const Icon(
                    Icons.favorite,
                    size: 28,
                    color: Colors.redAccent,
                  ),
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
                child: const Icon(
                  Icons.favorite,
                  size: 36,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                (!isRingConnected || showDisconnectedInPlace)
                    ? '_ _'
                    : '${hr.liveHr ?? '_ _'}',
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
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : HrSessionChart(
                  readings: hr.sessionReadings,
                  backfillRanges: hr.attemptedBackfillRanges,
                ),
        ),
        const SizedBox(height: 8),
        // Session stats (only once we have data)
        if (hr.sessionReadings.isNotEmpty) _buildSessionStatsRow(hr),
        if (hr.sessionReadings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildZoneDurationBars(hr),
        ],
        const SizedBox(height: 20),
        // Pause button (no stop while measuring)
        OutlinedButton.icon(
          onPressed: () => _pauseMeasurement(hr),
          icon: const Icon(Icons.pause_rounded),
          label: const Text(
            'Pause',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPausedState(
    HeartRateProvider hr, {
    required bool isRingConnected,
  }) {
    final elapsed = hr.timelineElapsed;
    final mm = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Frozen BPM display
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Icon(Icons.favorite, size: 36, color: Colors.redAccent),
            const SizedBox(width: 12),
            Text(
              hr.liveHr != null ? '${hr.liveHr}' : '_ _',
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
        // Frozen elapsed + paused indicator
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$mm:$ss',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Paused',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Frozen chart
        SizedBox(
          height: 160,
          child: hr.sessionReadings.length < 2
              ? Center(
                  child: Text(
                    'Waiting for readings…',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : HrSessionChart(
                  readings: hr.sessionReadings,
                  backfillRanges: hr.attemptedBackfillRanges,
                ),
        ),
        const SizedBox(height: 8),
        if (hr.sessionReadings.isNotEmpty) _buildSessionStatsRow(hr),
        if (hr.sessionReadings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildZoneDurationBars(hr),
        ],
        const SizedBox(height: 20),
        // Resume + Stop buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isRingConnected ? () => _resumeMeasurement(hr) : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Resume',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _stopMeasurement(hr),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(color: AppColors.textSecondary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'Stop',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDoneState(HeartRateProvider hr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wrap chart + BPM + stats for screenshot
        RepaintBoundary(
          key: _hrChartKey,
          child: Column(
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
                  _formatElapsed(hr.timelineElapsed),
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 20),
              // Session graph
              if (hr.sessionReadings.length >= 2) ...[
                SizedBox(
                  height: 160,
                  child: HrSessionChart(readings: hr.sessionReadings),
                ),
                const SizedBox(height: 8),
              ],
              // Stats
              if (hr.sessionReadings.isNotEmpty) _buildSessionStatsRow(hr),
            ],
          ),
        ),
        // Zone bars and buttons remain outside RepaintBoundary
        if (hr.sessionReadings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildZoneDurationBars(hr),
        ],
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

  Widget _buildSessionStatsRow(HeartRateProvider hr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hr.attemptedBackfillRanges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Backfill attempted segment',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            _StatChip(label: 'Avg', value: '${hr.sessionAvg ?? '—'} BPM'),
            const SizedBox(width: 8),
            _StatChip(label: 'Min', value: '${hr.sessionMin ?? '—'} BPM'),
            const SizedBox(width: 8),
            _StatChip(label: 'Max', value: '${hr.sessionMax ?? '—'} BPM'),
          ],
        ),
      ],
    );
  }

  Widget _buildZoneDurationBars(HeartRateProvider hr) {
    final age = context.watch<AuthProvider>().profile?.age;
    final ageLabel = age?.toString() ?? 'N/A';
    final maxHr = hr.estimateMaxHeartRate(age: age);
    final zoneDurations = hr.zoneDurations(age: age);
    final maxDuration = zoneDurations.reduce((a, b) => a > b ? a : b);

    const zoneColors = [
      Color(0xFFB8B8BE),
      Color(0xFF90CFF2),
      Color(0xFF57B7E2),
      Color(0xFF45C8B8),
      Color(0xFFE7C457),
      Color(0xFFFF6B5A),
    ];

    String fmt(Duration d) {
      final totalSeconds = d.inSeconds;
      final hours = totalSeconds ~/ 3600;
      final minutes = (totalSeconds % 3600) ~/ 60;
      final seconds = totalSeconds % 60;
      if (hours > 0) {
        return '${hours}h${minutes}m${seconds}s';
      }
      if (minutes > 0) {
        return '${minutes}m${seconds}s';
      }
      return '${seconds}s';
    }

    String zoneRangeLabel(int zone) {
      final z0 = (maxHr * 0.5).round();
      final z1 = (maxHr * 0.6).round();
      final z2 = (maxHr * 0.7).round();
      final z3 = (maxHr * 0.8).round();
      final z4 = (maxHr * 0.9).round();
      switch (zone) {
        case 0:
          return '<$z0';
        case 1:
          return '$z0-$z1';
        case 2:
          return '${z1 + 1}-$z2';
        case 3:
          return '${z2 + 1}-$z3';
        case 4:
          return '${z3 + 1}-$z4';
        default:
          return '${z4 + 1}-$maxHr';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 16,
                        decoration: BoxDecoration(
                          color: zoneColors[i],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppColors.backgroundPaper,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: maxDuration == Duration.zero
                                  ? 0
                                  : zoneDurations[i].inMilliseconds /
                                        maxDuration.inMilliseconds,
                              child: Container(
                                height: 16,
                                decoration: BoxDecoration(
                                  color: zoneColors[i],
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Zone $i  ${fmt(zoneDurations[i])}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.backgroundPaper,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Age: $ageLabel\n'
            'Formula: HRmax = 208 - 0.7 × age = $maxHr\n'
            'Ranges (bpm): '
            'Z0 ${zoneRangeLabel(0)}, '
            'Z1 ${zoneRangeLabel(1)}, '
            'Z2 ${zoneRangeLabel(2)}, '
            'Z3 ${zoneRangeLabel(3)}, '
            'Z4 ${zoneRangeLabel(4)}, '
            'Z5 ${zoneRangeLabel(5)}',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
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

// ─── Activity prompt bottom sheet ────────────────────────────────────────────

class _ActivityPromptSheet extends StatefulWidget {
  final DateTime startedAt;
  final DateTime endedAt;
  final int avgBpm;
  final int? maxBpm;
  final GlobalKey? chartKey;

  const _ActivityPromptSheet({
    required this.startedAt,
    required this.endedAt,
    required this.avgBpm,
    this.maxBpm,
    this.chartKey,
  });

  @override
  State<_ActivityPromptSheet> createState() => _ActivityPromptSheetState();
}

class _ActivityPromptSheetState extends State<_ActivityPromptSheet> {
  ActivityType? _selectedType;
  ActivityIntensity? _selectedIntensity;
  bool _saving = false;

  Future<void> _save() async {
    if (_selectedType == null) return;
    setState(() => _saving = true);
    try {
      // Step 1: Save activity
      final token = AuthService().token;
      if (token == null) throw Exception('Not authenticated');
      final response = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/activity'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'activity_type_id': _selectedType!.id,
              'start_time': widget.startedAt.toUtc().toIso8601String(),
              'end_time': widget.endedAt.toUtc().toIso8601String(),
              'intensity': _selectedIntensity?.name,
              'source': ActivitySource.manual.name,
              'heart_rate_avg': widget.avgBpm,
              'heart_rate_max': widget.maxBpm,
            }),
          )
          .timeout(ApiConstants.receiveTimeout);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}');
      }

      // Step 2: Capture screenshot (graceful — null if fails)
      File? screenshotFile;
      final key = widget.chartKey;
      if (key?.currentContext != null) {
        try {
          final renderObject = key!.currentContext!.findRenderObject();
          if (renderObject is RenderRepaintBoundary) {
            final image = await renderObject.toImage(pixelRatio: 2.0).timeout(
              const Duration(seconds: 3),
              onTimeout: () => throw TimeoutException('Screenshot capture timed out'),
            );
            final byteData =
                await image.toByteData(format: ui.ImageByteFormat.png);
            if (byteData != null) {
              final compressed = await FlutterImageCompress.compressWithList(
                byteData.buffer.asUint8List(),
                minWidth: 800,
                minHeight: 400,
                quality: 85,
                format: CompressFormat.jpeg,
              );
              final dir = await getTemporaryDirectory();
              final path =
                  '${dir.path}/hr_${DateTime.now().millisecondsSinceEpoch}.jpg';
              screenshotFile = File(path);
              await screenshotFile.writeAsBytes(compressed);
            }
          }
        } catch (_) {
          // Screenshot capture failed — proceed without it
          screenshotFile = null;
        }
      }

      // Step 3: Fetch open exercise tasks
      List<Task> exerciseTasks = [];
      try {
        final taskService = TaskService();
        taskService.setToken(token);
        final taskResponse = await taskService.getTasks();
        exerciseTasks = taskResponse.tasks
            .where((t) =>
                t.taskType == TaskType.exercise &&
                t.isPending)
            .toList();
      } catch (_) {
        // Network failure or auth issue — treat as no tasks
      }

      if (!mounted) return;

      // Step 4: No matching tasks — just pop + snackbar
      if (exerciseTasks.isEmpty) {
        Navigator.pop(context);
        _showSavedSnackbar(
          context,
          activityName: '${_selectedType!.icon} ${_selectedType!.name}',
          taskCompleted: false,
        );
        return;
      }

      // Step 5: Pick task (if multiple, pick earliest closing)
      final Task targetTask;
      if (exerciseTasks.length == 1) {
        targetTask = exerciseTasks.first;
      } else {
        exerciseTasks.sort((a, b) {
          // closeDatetime is a UTC string format "2026-04-10 14:00:00" (no Z)
          String ensureUtcFormat(String dateStr) {
            final normalized = dateStr.replaceAll(' ', 'T');
            return normalized.endsWith('Z') ? normalized : '${normalized}Z';
          }

          final aDt = DateTime.parse(ensureUtcFormat(a.closeDatetime));
          final bDt = DateTime.parse(ensureUtcFormat(b.closeDatetime));
          return aDt.compareTo(bDt);
        });
        targetTask = exerciseTasks.first;
      }

      // Step 6: Show dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => _ExerciseTaskDialog(taskName: targetTask.taskName),
      ) ?? false;

      if (!mounted) return;

      // Step 7: Handle user response
      if (confirmed) {
        try {
          // Upload screenshot if available
          if (screenshotFile != null) {
            await TaskService().uploadTaskAttachments(
              taskId: targetTask.taskId,
              files: [screenshotFile],
            );
          }
          // Complete task
          await TaskService().completeTask(targetTask.taskId);

          if (mounted) {
            Navigator.pop(context);
            _showSavedSnackbar(
              context,
              activityName: '${_selectedType!.icon} ${_selectedType!.name}',
              taskName: targetTask.taskName,
              taskCompleted: true,
            );
          }
        } catch (_) {
          // Upload or complete failed — still pop and show basic snackbar
          if (mounted) {
            Navigator.pop(context);
            _showSavedSnackbar(
              context,
              activityName: '${_selectedType!.icon} ${_selectedType!.name}',
              taskCompleted: false,
            );
          }
        }
      } else {
        // User tapped Skip
        if (mounted) {
          Navigator.pop(context);
          _showSavedSnackbar(
            context,
            activityName: '${_selectedType!.icon} ${_selectedType!.name}',
            taskCompleted: false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save activity: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showSavedSnackbar(
    BuildContext ctx, {
    required String activityName,
    required bool taskCompleted,
    String? taskName,
  }) {
    final message = taskCompleted
        ? '$activityName saved · Exercise task "$taskName" completed'
        : '$activityName saved';
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final durationMins =
        widget.endedAt.difference(widget.startedAt).inMinutes.clamp(1, 9999);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Were you doing an activity?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.avgBpm} BPM avg · ${durationMins}m · log it to your timeline',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            // Activity type grid
            ActivityTypeSelector(
              selectedType: _selectedType,
              onTypeSelected: (t) => setState(() => _selectedType = t),
            ),
            const SizedBox(height: 20),
            // Intensity (optional)
            Text(
              'Intensity  (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: ActivityIntensity.values.map((level) {
                final isSelected = _selectedIntensity == level;
                final label = switch (level) {
                  ActivityIntensity.low => 'Low',
                  ActivityIntensity.moderate => 'Moderate',
                  ActivityIntensity.high => 'High',
                };
                final color = switch (level) {
                  ActivityIntensity.low => const Color(0xFF57B7E2),
                  ActivityIntensity.moderate => const Color(0xFFE7C457),
                  ActivityIntensity.high => const Color(0xFFFF6B5A),
                };
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedIntensity =
                          isSelected ? null : level),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.15)
                              : AppColors.backgroundPaper,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? color : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected ? color : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.textLight),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_selectedType == null || _saving) ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLemon,
                      foregroundColor: AppColors.textOnYellow,
                      disabledBackgroundColor:
                          AppColors.backgroundPaper,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Save Activity',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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

// ─── Exercise Task Dialog ──────────────────────────────────────────────────

class _ExerciseTaskDialog extends StatelessWidget {
  final String taskName;

  const _ExerciseTaskDialog({required this.taskName});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Complete exercise task?'),
      content: Text(
        'Mark "$taskName" as completed using this workout?',
        style: const TextStyle(fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Skip'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryLemon,
            foregroundColor: AppColors.textOnYellow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Text('Yes, complete it'),
        ),
      ],
    );
  }
}
