import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/hr_session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/heart_rate_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/hr_session_chart.dart';

class HrSessionDetailScreen extends StatefulWidget {
  final HrSessionSummary session;

  const HrSessionDetailScreen({super.key, required this.session});

  @override
  State<HrSessionDetailScreen> createState() => _HrSessionDetailScreenState();
}

class _HrSessionDetailScreenState extends State<HrSessionDetailScreen> {
  List<HrSessionPoint>? _readings;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTimeseries();
  }

  Future<void> _loadTimeseries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ts = await HrSessionService()
          .getSessionTimeseries(widget.session.sessionId);
      if (mounted) setState(() => _readings = ts.readings);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final age = context.read<AuthProvider>().profile?.age;

    return Scaffold(
      backgroundColor: AppColors.backgroundPaper,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPaper,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _appBarTitle(session.startedAt),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummaryCard(session),
            const SizedBox(height: 16),
            _buildChartCard(),
            if (_readings != null && _readings!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildZoneCard(age),
            ],
          ],
        ),
      ),
    );
  }

  // ── Summary card ──────────────────────────────────────────────────────────

  Widget _buildSummaryCard(HrSessionSummary session) {
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
          // Time range
          Text(
            '${_timeStr(session.startedAt)} – ${_timeStr(session.endedAt)}',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                _durationStr(session.durationSeconds),
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Icon(Icons.grain, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${session.readingCount} readings',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Avg BPM hero
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.favorite, size: 32, color: Colors.redAccent),
              const SizedBox(width: 10),
              Text(
                '${session.avgBpm}',
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
          const SizedBox(height: 16),
          // Min / Max chips
          Row(
            children: [
              _StatChip(label: 'Min', value: '${session.minBpm} BPM'),
              const SizedBox(width: 8),
              _StatChip(label: 'Max', value: '${session.maxBpm} BPM'),
            ],
          ),
        ],
      ),
    );
  }

  // ── Chart card ────────────────────────────────────────────────────────────

  Widget _buildChartCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Time series',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: _buildChartContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildChartContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load data',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    final readings = _readings ?? [];
    if (readings.length < 2) {
      return Center(
        child: Text(
          'Not enough data points',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    return HrSessionChart(readings: readings);
  }

  // ── Zone duration card ────────────────────────────────────────────────────

  Widget _buildZoneCard(int? age) {
    final readings = _readings!;
    final maxHr = _estimateMaxHr(age);
    final zones = _zoneDurations(readings, maxHr);
    final maxDur = zones.reduce((a, b) => a > b ? a : b);

    const zoneColors = [
      Color(0xFFB8B8BE),
      Color(0xFF90CFF2),
      Color(0xFF57B7E2),
      Color(0xFF45C8B8),
      Color(0xFFE7C457),
      Color(0xFFFF6B5A),
    ];
    const zoneLabels = ['Z0', 'Z1', 'Z2', 'Z3', 'Z4', 'Z5'];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Heart rate zones',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
                          widthFactor: maxDur == Duration.zero
                              ? 0
                              : zones[i].inMilliseconds /
                                    maxDur.inMilliseconds,
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
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 72,
                    child: Text(
                      '${zoneLabels[i]}  ${_fmtDur(zones[i])}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _estimateMaxHr(int? age) =>
      ((208 - 0.7 * (age ?? 20)).round()).clamp(130, 210);

  List<Duration> _zoneDurations(List<HrSessionPoint> readings, int maxHr) {
    final zones = List<Duration>.filled(6, Duration.zero);
    if (readings.length < 2) return zones;
    final sorted = [...readings]..sort((a, b) => a.time.compareTo(b.time));
    for (var i = 0; i < sorted.length; i++) {
      final bpm = sorted[i].smoothedBpm.round();
      final ratio = bpm / maxHr;
      final zone = ratio < 0.5
          ? 0
          : ratio < 0.6
          ? 1
          : ratio < 0.7
          ? 2
          : ratio < 0.8
          ? 3
          : ratio < 0.9
          ? 4
          : 5;
      Duration span = const Duration(seconds: 1);
      if (i < sorted.length - 1) {
        final delta = sorted[i + 1].time.difference(sorted[i].time);
        if (delta > Duration.zero && delta <= const Duration(seconds: 10)) {
          span = delta;
        }
      }
      zones[zone] += span;
    }
    return zones;
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h${m}m';
    if (m > 0) return '${m}m${s}s';
    return '${s}s';
  }

  String _appBarTitle(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'Today · ${_timeStr(dt)}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day) {
      return 'Yesterday · ${_timeStr(dt)}';
    }
    return '${local.month}/${local.day} · ${_timeStr(dt)}';
  }

  String _timeStr(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _durationStr(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

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
          color: AppColors.backgroundPaper,
          borderRadius: BorderRadius.circular(14),
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
