import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/activity_models.dart';
import '../../../shared/widgets/gradient_card.dart';
import '../../../shared/widgets/ring_status_indicator.dart';
import '../widgets/walk_test_timer.dart';
import '../widgets/heart_rate_display.dart';
import '../widgets/walk_test_results_card.dart';
import '../widgets/walk_test_instructions.dart';

enum WalkTestState {
  instructions,
  ready,
  inProgress,
  completed,
}

class WalkTestScreen extends StatefulWidget {
  const WalkTestScreen({super.key});

  @override
  State<WalkTestScreen> createState() => _WalkTestScreenState();
}

class _WalkTestScreenState extends State<WalkTestScreen> {
  WalkTestState _testState = WalkTestState.instructions;
  final RingStatus _ringStatus = RingStatus.connected;

  Timer? _timer;
  int _elapsedSeconds = 0;
  static const int _testDuration = 360; // 6 minutes in seconds

  // Mock real-time data
  int _currentHeartRate = 72;
  double _currentDistance = 0;
  int _maxHeartRate = 72;
  List<int> _heartRateHistory = [];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _testState = WalkTestState.ready;
    });
  }

  void _startTest() {
    setState(() {
      _testState = WalkTestState.inProgress;
      _elapsedSeconds = 0;
      _heartRateHistory = [];
      _maxHeartRate = _currentHeartRate;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_elapsedSeconds >= _testDuration) {
        _completeTest();
        return;
      }

      setState(() {
        _elapsedSeconds++;
        // Simulate heart rate changes
        _currentHeartRate = 72 + (_elapsedSeconds ~/ 10) + ((_elapsedSeconds % 7) - 3);
        _currentHeartRate = _currentHeartRate.clamp(60, 180);
        _heartRateHistory.add(_currentHeartRate);
        if (_currentHeartRate > _maxHeartRate) {
          _maxHeartRate = _currentHeartRate;
        }
        // Simulate distance (avg walking speed ~1.2 m/s)
        _currentDistance = _elapsedSeconds * 1.15;
      });
    });
  }

  void _completeTest() {
    _timer?.cancel();
    setState(() {
      _testState = WalkTestState.completed;
    });
  }

  void _stopTest() {
    _timer?.cancel();
    setState(() {
      _testState = WalkTestState.completed;
    });
  }

  void _resetTest() {
    setState(() {
      _testState = WalkTestState.instructions;
      _elapsedSeconds = 0;
      _currentDistance = 0;
      _heartRateHistory = [];
    });
  }

  int get _avgHeartRate {
    if (_heartRateHistory.isEmpty) return _currentHeartRate;
    return (_heartRateHistory.reduce((a, b) => a + b) / _heartRateHistory.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.mintGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    children: [
                      if (_ringStatus != RingStatus.connected)
                        RingRequiredBanner(
                          onConnectPressed: () {},
                        )
                      else
                        _buildRingConnected(),
                      const SizedBox(height: 16),
                      _buildContent(),
                    ],
                  ),
                ),
              ),
              _buildBottomButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_testState == WalkTestState.inProgress) {
                _showStopConfirmation();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          const Expanded(
            child: Text(
              '6-Minute Walk Test',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildRingConnected() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: RingStatusIndicator(
        status: _ringStatus,
        batteryLevel: 78,
      ),
    );
  }

  Widget _buildContent() {
    switch (_testState) {
      case WalkTestState.instructions:
        return const WalkTestInstructions();
      case WalkTestState.ready:
        return _buildReadyState();
      case WalkTestState.inProgress:
        return _buildInProgressState();
      case WalkTestState.completed:
        return _buildCompletedState();
    }
  }

  Widget _buildReadyState() {
    return GradientCard(
      gradient: AppColors.cardGradient,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.sunriseGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryLemon.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.directions_walk,
              size: 60,
              color: AppColors.textOnYellow,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Ready to Start',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Find a flat, unobstructed path\nTap Start when you\'re ready',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          HeartRateDisplay(
            heartRate: _currentHeartRate,
            label: 'Resting Heart Rate',
          ),
        ],
      ),
    );
  }

  Widget _buildInProgressState() {
    return Column(
      children: [
        GradientCard(
          gradient: AppColors.cardGradient,
          child: Column(
            children: [
              WalkTestTimer(
                elapsedSeconds: _elapsedSeconds,
                totalSeconds: _testDuration,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: '${_currentDistance.toStringAsFixed(0)} m',
                      gradient: AppColors.warmGradient,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.favorite,
                      label: 'Heart Rate',
                      value: '$_currentHeartRate bpm',
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFEBEE), Color(0xFFFFCDD2)],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GradientCard(
          gradient: AppColors.cardGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tips_and_updates, color: AppColors.primaryLemonDark),
                  SizedBox(width: 8),
                  Text(
                    'Keep Walking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Walk at your own pace. You can slow down or rest if needed, but try to keep moving if possible.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _elapsedSeconds / _testDuration,
                backgroundColor: AppColors.surfaceLight,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryLemonDark),
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedState() {
    // Calculate mock recovery heart rate (measured 1 minute after stopping)
    final recoveryHeartRate = (_avgHeartRate - 10).clamp(60, 120);

    return Column(
      children: [
        WalkTestResultsCard(
          result: WalkTestResult(
            id: 'mock-${DateTime.now().millisecondsSinceEpoch}',
            date: DateTime.now(),
            distanceMeters: _currentDistance,
            durationSeconds: _elapsedSeconds,
            avgHeartRate: _avgHeartRate,
            maxHeartRate: _maxHeartRate,
            recoveryHeartRate: recoveryHeartRate,
          ),
        ),
        const SizedBox(height: 16),
        _buildSelfComparisonNote(),
      ],
    );
  }

  Widget _buildSelfComparisonNote() {
    return GradientCard(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accentOrange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.info_outline,
              color: AppColors.accentOrange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Self-Referenced Results',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Results are compared only to your past tests. This is for informational purposes, not medical diagnosis.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: _buildActionButton(),
      ),
    );
  }

  Widget _buildActionButton() {
    switch (_testState) {
      case WalkTestState.instructions:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startCountdown,
            icon: const Icon(Icons.play_arrow),
            label: const Text('I\'m Ready'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.primaryLemonDark,
            ),
          ),
        );
      case WalkTestState.ready:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startTest,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Walking'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
          ),
        );
      case WalkTestState.inProgress:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _showStopConfirmation,
            icon: const Icon(Icons.stop),
            label: const Text('Stop Test'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
          ),
        );
      case WalkTestState.completed:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _resetTest,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('New Test'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.primaryLemonDark,
                ),
              ),
            ),
          ],
        );
    }
  }

  void _showStopConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Test?'),
        content: const Text(
          'Are you sure you want to stop the test early? Your current progress will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _stopTest();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: AppColors.primaryLemonDark),
            SizedBox(width: 8),
            Text('About 6MWT'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The Six-Minute Walk Test measures the distance you can walk in six minutes.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                'What it measures:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text('• Walking distance'),
              Text('• Heart rate response'),
              Text('• Recovery rate'),
              SizedBox(height: 12),
              Text(
                'Important:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '• Results are compared only to your own past tests',
                style: TextStyle(fontSize: 13),
              ),
              Text(
                '• This is informational, not a medical diagnosis',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Gradient gradient;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textOnYellow, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textOnYellow,
            ),
          ),
        ],
      ),
    );
  }
}
