// Wellness models: Fatigue and Stress signals derived from sleep ring data.

import 'package:flutter/material.dart';

// ─── Fatigue ─────────────────────────────────────────────────────────────────

enum FatigueLevel { noData, calibrating, low, moderate, elevated }

class FatigueState {
  final FatigueLevel level;

  const FatigueState(this.level);

  /// Short label shown in the centre of the star ring (max ~4 chars).
  String get centerLabel => switch (level) {
        FatigueLevel.noData => '—',
        FatigueLevel.calibrating => '···',
        FatigueLevel.low => 'Low',
        FatigueLevel.moderate => 'Med',
        FatigueLevel.elevated => 'High',
      };

  /// Longer label shown in tooltips / advisor check-in.
  String get fullLabel => switch (level) {
        FatigueLevel.noData => 'No data',
        FatigueLevel.calibrating => 'Learning baseline',
        FatigueLevel.low => 'Low',
        FatigueLevel.moderate => 'Moderate',
        FatigueLevel.elevated => 'Elevated',
      };

  /// 0-1 progress for the star ring visualisation.
  double get progress => switch (level) {
        FatigueLevel.noData => 0.2,
        FatigueLevel.calibrating => 0.3,
        FatigueLevel.low => 0.85,
        FatigueLevel.moderate => 0.55,
        FatigueLevel.elevated => 0.88,
      };

  Color get color => switch (level) {
        FatigueLevel.noData || FatigueLevel.calibrating => const Color(0xFFBDBDBD),
        FatigueLevel.low => const Color(0xFF81C784),
        FatigueLevel.moderate => const Color(0xFFFFB74D),
        FatigueLevel.elevated => const Color(0xFFE57373),
      };

  bool get hasData => level != FatigueLevel.noData && level != FatigueLevel.calibrating;
}

// ─── Stress ───────────────────────────────────────────────────────────────────

enum StressLevel { noData, calibrating, lower, typical, higher }

class StressState {
  final StressLevel level;

  const StressState(this.level);

  String get centerLabel => switch (level) {
        StressLevel.noData => '—',
        StressLevel.calibrating => '···',
        StressLevel.lower => 'Low',
        StressLevel.typical => 'Norm',
        StressLevel.higher => 'High',
      };

  String get fullLabel => switch (level) {
        StressLevel.noData => 'No data',
        StressLevel.calibrating => 'Learning baseline',
        StressLevel.lower => 'Lower than usual',
        StressLevel.typical => 'Typical',
        StressLevel.higher => 'Higher than usual',
      };

  double get progress => switch (level) {
        StressLevel.noData => 0.2,
        StressLevel.calibrating => 0.3,
        StressLevel.lower => 0.85,
        StressLevel.typical => 0.6,
        StressLevel.higher => 0.88,
      };

  Color get color => switch (level) {
        StressLevel.noData || StressLevel.calibrating => const Color(0xFFBDBDBD),
        StressLevel.lower => const Color(0xFF81C784),
        StressLevel.typical => const Color(0xFFB39DDB),
        StressLevel.higher => const Color(0xFFE57373),
      };

  bool get hasData => level != StressLevel.noData && level != StressLevel.calibrating;
}

// ─── Contributing-factor context ─────────────────────────────────────────────

/// Raw values used to compute Fatigue and Stress — surfaced on detail screens.
class WellnessContext {
  /// Average of the 3 most recent valid nights.
  final double recentRhr;
  final double recentQuality;
  final double recentHours;

  /// Median of up to 14 baseline nights.
  final double baselineRhr;
  final double baselineQuality;
  final double baselineHours;

  /// How many nights are in the baseline window.
  final int nightsInBaseline;

  const WellnessContext({
    required this.recentRhr,
    required this.recentQuality,
    required this.recentHours,
    required this.baselineRhr,
    required this.baselineQuality,
    required this.baselineHours,
    required this.nightsInBaseline,
  });

  double get rhrDelta => recentRhr - baselineRhr;
  double get qualityDelta => recentQuality - baselineQuality;
  double get hoursDelta => recentHours - baselineHours;
}

// ─── Combined ─────────────────────────────────────────────────────────────────

class WellnessState {
  final FatigueState fatigue;
  final StressState stress;
  final DateTime? calculatedAt;

  /// Present when enough baseline data exists; null while calibrating / no data.
  final WellnessContext? context;

  const WellnessState({
    required this.fatigue,
    required this.stress,
    this.calculatedAt,
    this.context,
  });

  static const loading = WellnessState(
    fatigue: FatigueState(FatigueLevel.noData),
    stress: StressState(StressLevel.noData),
  );
}
