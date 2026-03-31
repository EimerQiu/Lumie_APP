// Computes Fatigue and Stress signals from sleep history.
// No network calls — pure calculation over a List<SleepSession>.
//
// Algorithm:
//   • Baseline  = median RHR and median quality over the most recent 14 valid nights
//   • Recent    = mean over the last 3 valid nights
//   • Minimum   = 5 valid nights before any score is shown (returns calibrating otherwise)
//   • "Valid"   = source == 'ring' AND restingHeartRate > 0
//   • 3-day rolling average is implicit (recent = last 3 nights)

import '../../shared/models/sleep_models.dart';
import '../../shared/models/wellness_models.dart';

class WellnessService {
  static final WellnessService _instance = WellnessService._internal();
  factory WellnessService() => _instance;
  WellnessService._internal();

  static const int _minNightsForBaseline = 5;
  static const int _baselineWindow = 14;
  static const int _recentWindow = 3;

  /// Computes [WellnessState] from [sessions].
  /// Pass the full sleep history (up to ~14 nights) for best results.
  WellnessState compute(List<SleepSession> sessions) {
    // Only use ring-sourced sessions with a valid RHR reading
    final valid = sessions
        .where((s) => s.source == 'ring' && s.restingHeartRate > 0)
        .toList()
      ..sort((a, b) => b.bedtime.compareTo(a.bedtime)); // newest first

    if (valid.length < _minNightsForBaseline) {
      return WellnessState(
        fatigue: const FatigueState(FatigueLevel.calibrating),
        stress: const StressState(StressLevel.calibrating),
        calculatedAt: DateTime.now(),
      );
    }

    // Baseline: median over last 14 valid nights
    final baselineSet = valid.take(_baselineWindow).toList();
    final baselineRhr = _median(baselineSet.map((s) => s.restingHeartRate.toDouble()));
    final baselineQuality = _median(baselineSet.map((s) => s.sleepQualityScore));
    final baselineHours =
        _median(baselineSet.map((s) => s.totalSleepTime.inMinutes / 60.0));

    // Recent: mean over last 3 valid nights
    final recentSet = valid.take(_recentWindow).toList();
    final recentRhr = _mean(recentSet.map((s) => s.restingHeartRate.toDouble()));
    final recentQuality = _mean(recentSet.map((s) => s.sleepQualityScore));
    final recentHours = _mean(recentSet.map((s) => s.totalSleepTime.inMinutes / 60.0));

    final context = WellnessContext(
      recentRhr: recentRhr,
      recentQuality: recentQuality,
      recentHours: recentHours,
      baselineRhr: baselineRhr,
      baselineQuality: baselineQuality,
      baselineHours: baselineHours,
      nightsInBaseline: baselineSet.length,
    );

    return WellnessState(
      fatigue: _computeFatigue(
        recentRhr: recentRhr,
        baselineRhr: baselineRhr,
        recentQuality: recentQuality,
        baselineQuality: baselineQuality,
        recentHours: recentHours,
        baselineHours: baselineHours,
      ),
      stress: _computeStress(
        recentRhr: recentRhr,
        baselineRhr: baselineRhr,
        recentQuality: recentQuality,
        baselineQuality: baselineQuality,
      ),
      calculatedAt: DateTime.now(),
      context: context,
    );
  }

  // ─── Internal helpers ──────────────────────────────────────────────────────

  FatigueState _computeFatigue({
    required double recentRhr,
    required double baselineRhr,
    required double recentQuality,
    required double baselineQuality,
    required double recentHours,
    required double baselineHours,
  }) {
    int score = 0;

    // Resting HR elevation vs baseline
    final rhrDelta = recentRhr - baselineRhr;
    if (rhrDelta > 5) {
      score += 2;
    } else if (rhrDelta > 2) {
      score += 1;
    }

    // Sleep quality drop vs baseline
    if (baselineQuality > 0) {
      final qualityRatio = recentQuality / baselineQuality;
      if (qualityRatio < 0.75) {
        score += 2;
      } else if (qualityRatio < 0.90) {
        score += 1;
      }
    }

    // Absolute sleep duration thresholds
    if (recentHours < 6.0) {
      score += 2;
    } else if (recentHours < 7.0) {
      score += 1;
    }

    return FatigueState(switch (score) {
      0 || 1 => FatigueLevel.low,
      2 || 3 => FatigueLevel.moderate,
      _ => FatigueLevel.elevated,
    });
  }

  StressState _computeStress({
    required double recentRhr,
    required double baselineRhr,
    required double recentQuality,
    required double baselineQuality,
  }) {
    int score = 0;

    // Resting HR elevation
    final rhrDelta = recentRhr - baselineRhr;
    if (rhrDelta > 5) {
      score += 2;
    } else if (rhrDelta > 2) {
      score += 1;
    } else if (rhrDelta < -3) {
      score -= 1;
    }

    // Sleep quality as HRV proxy: drop = more stress
    if (baselineQuality > 0) {
      final qualityDrop = (baselineQuality - recentQuality) / baselineQuality;
      if (qualityDrop > 0.25) {
        score += 2;
      } else if (qualityDrop > 0.10) {
        score += 1;
      } else if (qualityDrop < -0.15) {
        score -= 1;
      }
    }

    return StressState(switch (score) {
      <= -1 => StressLevel.lower,
      0 || 1 => StressLevel.typical,
      _ => StressLevel.higher,
    });
  }

  double _median(Iterable<double> values) {
    final list = values.toList()..sort();
    final n = list.length;
    if (n == 0) return 0;
    if (n.isOdd) return list[n ~/ 2];
    return (list[n ~/ 2 - 1] + list[n ~/ 2]) / 2;
  }

  double _mean(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }
}
