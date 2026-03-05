// Workout recording screen — Apple Watch-style immersive dark UI
// Acquires HR from ring then lets user start/pause/finish a workout.
//
// TODO: Replace simulated HR with real BLE streaming:
//   - Send command 0x19 (Exercise Mode Control, subcommand 0x01 = start)
//   - Listen to notifications on char 0xfff7 for 0x18 (exercise push) or 0x09 (real-time stream)
//   - Each BLE notification fires ~every 1 s, parse heartRate from protocol bytes

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';
import '../../ring/providers/ring_provider.dart';

enum _RecordingState {
  acquiring, // waiting for ring to report first HR
  ready,     // HR received — Start button is lit
  recording, // timer running, HR updating
  paused,    // timer stopped, resume/end options visible
  finished,  // workout ended, summary shown
}

class WorkoutRecordingScreen extends StatefulWidget {
  final ActivityType activityType;

  const WorkoutRecordingScreen({
    super.key,
    required this.activityType,
  });

  @override
  State<WorkoutRecordingScreen> createState() => _WorkoutRecordingScreenState();
}

class _WorkoutRecordingScreenState extends State<WorkoutRecordingScreen>
    with TickerProviderStateMixin {
  _RecordingState _state = _RecordingState.acquiring;

  Timer? _durationTimer;
  Timer? _acquisitionTimer;
  int _elapsedSeconds = 0;

  int? _currentHeartRate;
  int _maxHeartRate = 0;
  final List<int> _hrHistory = [];

  // BLE HR streaming — used when ring is actively BLE-connected
  late final RingProvider _ring;
  StreamSubscription<int>? _hrStreamSub;
  // ignore: prefer_final_fields
  bool _usingRealHr = false;

  // Pulsing heart animation
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Light icons on dark background
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarIconBrightness: Brightness.light),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _ring = context.read<RingProvider>();
    _startHrAcquisition();
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarIconBrightness: Brightness.dark),
    );
    _durationTimer?.cancel();
    _acquisitionTimer?.cancel();
    _hrStreamSub?.cancel();
    _ring.stopHrStreaming();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Ring HR acquisition ────────────────────────────────────────────────────

  /// Tries real BLE streaming first (command 0x09 via RingProvider).
  /// Falls back to simulation after 5 s if ring isn't actively connected.
  void _startHrAcquisition() {
    final stream = _ring.startHrStreaming();
    bool gotRealData = false;

    _hrStreamSub = stream.listen((bpm) {
      if (!mounted) return;
      gotRealData = true;
      _usingRealHr = true;
      _updateHr(bpm);
      if (_state == _RecordingState.acquiring) {
        _acquisitionTimer?.cancel();
        setState(() => _state = _RecordingState.ready);
        _pulseController.repeat(reverse: true);
      }
    });

    // Fallback: if ring doesn't stream within 5 s, simulate
    _acquisitionTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || gotRealData) return;
      setState(() {
        _currentHeartRate = 72;
        _state = _RecordingState.ready;
      });
      _pulseController.repeat(reverse: true);
    });
  }

  // ── Timer helpers ──────────────────────────────────────────────────────────

  void _startTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
        // Only simulate HR tick when ring stream isn't providing data
        if (!_usingRealHr) _simulatedHrTick();
      });
    });
  }

  void _simulatedHrTick() {
    final base = 85 + (_elapsedSeconds ~/ 15);
    final jitter = math.Random().nextInt(11) - 5;
    _updateHr((base + jitter).clamp(50, 185));
  }

  void _updateHr(int bpm) {
    _currentHeartRate = bpm;
    if (_state == _RecordingState.recording) {
      _hrHistory.add(bpm);
      if (bpm > _maxHeartRate) _maxHeartRate = bpm;
    }
  }

  // ── State transitions ──────────────────────────────────────────────────────

  void _startRecording() {
    setState(() {
      _state = _RecordingState.recording;
      _elapsedSeconds = 0;
      _hrHistory.clear();
      _maxHeartRate = _currentHeartRate ?? 0;
    });
    _startTimer();
  }

  void _pauseRecording() {
    _durationTimer?.cancel();
    setState(() => _state = _RecordingState.paused);
  }

  void _resumeRecording() {
    setState(() => _state = _RecordingState.recording);
    _startTimer();
  }

  void _finishRecording() {
    _durationTimer?.cancel();
    _hrStreamSub?.cancel();
    _ring.stopHrStreaming();
    _pulseController.stop();
    setState(() => _state = _RecordingState.finished);
  }

  void _confirmStop() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2825),
        title: const Text('End Workout?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to end this workout?',
          style: TextStyle(color: Color(0xFFD6D3D1)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Going',
                style: TextStyle(color: AppColors.primaryLemonDark)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _finishRecording();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }

  // ── Computed values ────────────────────────────────────────────────────────

  int get _avgHeartRate {
    if (_hrHistory.isEmpty) return _currentHeartRate ?? 0;
    return (_hrHistory.reduce((a, b) => a + b) / _hrHistory.length).round();
  }

  String get _formattedDuration {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) {
      return '${_pad(h)}:${_pad(m)}:${_pad(s)}';
    }
    return '${_pad(m)}:${_pad(s)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Color get _hrColor {
    final hr = _currentHeartRate ?? 0;
    if (hr < 100) return const Color(0xFF4ADE80);   // green — low/resting
    if (hr < 140) return AppColors.primaryLemonDark; // amber — moderate
    return AppColors.error;                           // red — high
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1816),
      body: SafeArea(
        child: _state == _RecordingState.finished
            ? _buildFinishedView()
            : _buildActiveView(),
      ),
    );
  }

  // ── Active view (acquiring / ready / recording / paused) ──────────────────

  Widget _buildActiveView() {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDurationSection(),
                const SizedBox(height: 52),
                _buildHrSection(),
              ],
            ),
          ),
        ),
        _buildBottomControls(),
      ],
    );
  }

  Widget _buildTopBar() {
    final canDismiss = _state == _RecordingState.acquiring ||
        _state == _RecordingState.ready;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              canDismiss ? Icons.arrow_back : Icons.close,
              color: Colors.white60,
            ),
            onPressed: () {
              if (canDismiss) {
                Navigator.of(context).pop();
              } else {
                _confirmStop();
              }
            },
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.activityType.icon,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.activityType.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Balance spacer
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildDurationSection() {
    return Column(
      children: [
        Text(
          _formattedDuration,
          style: const TextStyle(
            fontSize: 80,
            fontWeight: FontWeight.w100,
            color: Colors.white,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'DURATION',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white30,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildHrSection() {
    return Column(
      children: [
        _buildHeartIcon(),
        const SizedBox(height: 10),
        Text(
          _currentHeartRate != null ? '$_currentHeartRate' : '--',
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.bold,
            color: _currentHeartRate != null ? Colors.white : Colors.white24,
          ),
        ),
        const Text(
          'BPM',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white30,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 16),
        _buildHrStatusLabel(),
      ],
    );
  }

  Widget _buildHeartIcon() {
    final shouldPulse = _state == _RecordingState.ready ||
        _state == _RecordingState.recording;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, _) {
        return Transform.scale(
          scale: shouldPulse ? _pulseAnimation.value : 1.0,
          child: Icon(
            Icons.favorite,
            size: 44,
            color: _currentHeartRate != null ? _hrColor : Colors.white.withValues(alpha: 0.15),
          ),
        );
      },
    );
  }

  Widget _buildHrStatusLabel() {
    switch (_state) {
      case _RecordingState.acquiring:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryLemonDark.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Acquiring heart rate...',
              style: TextStyle(fontSize: 14, color: Colors.white38),
            ),
          ],
        );
      case _RecordingState.ready:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4ADE80),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Heart rate ready',
              style: TextStyle(fontSize: 14, color: Color(0xFF4ADE80)),
            ),
          ],
        );
      case _RecordingState.recording:
        return const Text(
          'Recording...',
          style: TextStyle(fontSize: 13, color: Colors.white30),
        );
      case _RecordingState.paused:
        return const Text(
          'Paused',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.primaryLemonDark,
            fontWeight: FontWeight.w500,
          ),
        );
      case _RecordingState.finished:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: _buildButtons(),
    );
  }

  Widget _buildButtons() {
    switch (_state) {
      // ── Acquiring: Start is disabled / greyed ──
      case _RecordingState.acquiring:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: Colors.white10,
              padding: const EdgeInsets.symmetric(vertical: 22),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: Text(
              'START',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.20),
                letterSpacing: 3,
              ),
            ),
          ),
        );

      // ── Ready: Start is lit green ──
      case _RecordingState.ready:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startRecording,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4ADE80),
              padding: const EdgeInsets.symmetric(vertical: 22),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 10,
              shadowColor:
                  const Color(0xFF4ADE80).withValues(alpha: 0.5),
            ),
            child: const Text(
              'START',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF052E16),
                letterSpacing: 3,
              ),
            ),
          ),
        );

      // ── Recording: Pause + Finish ──
      case _RecordingState.recording:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pauseRecording,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text(
                  'PAUSE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white60,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _confirmStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text(
                  'FINISH',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        );

      // ── Paused: End + Resume ──
      case _RecordingState.paused:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _confirmStop,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  'END',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error.withValues(alpha: 0.8),
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _resumeRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLemonDark,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text(
                  'RESUME',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF78350F),
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        );

      case _RecordingState.finished:
        return const SizedBox.shrink();
    }
  }

  // ── Finished summary view ─────────────────────────────────────────────────

  Widget _buildFinishedView() {
    final totalMins = _elapsedSeconds ~/ 60;
    final totalSecs = _elapsedSeconds % 60;
    final durationLabel =
        totalMins > 0 ? '${totalMins}m ${totalSecs}s' : '${totalSecs}s';

    return Column(
      children: [
        const SizedBox(height: 20),
        const Text(
          'Workout Complete',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Activity icon
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLemon.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.activityType.icon,
                      style: const TextStyle(fontSize: 44),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.activityType.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 40),
                // Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatItem(
                      icon: Icons.timer_outlined,
                      label: 'Duration',
                      value: durationLabel,
                    ),
                    _StatItem(
                      icon: Icons.favorite_outline,
                      label: 'Avg HR',
                      value: '$_avgHeartRate bpm',
                    ),
                    _StatItem(
                      icon: Icons.trending_up,
                      label: 'Max HR',
                      value: '$_maxHeartRate bpm',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Save / Discard
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Save ActivityRecord to backend via API
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLemonDark,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text(
                    'Save Workout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Discard',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white30,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Stat item widget ───────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryLemonDark, size: 26),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white38),
        ),
      ],
    );
  }
}
