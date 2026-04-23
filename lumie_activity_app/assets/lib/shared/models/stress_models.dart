/// Real-time stress zone models.
///
/// Stress is calculated continuously throughout the day using HR/HRV data
/// from the ring. The four zones replace the previous numeric score display.

import 'package:flutter/material.dart';

// ─── Stress zones ────────────────────────────────────────────────────────────

/// Four qualitative stress zones displayed to the user.
enum StressZone { restored, relaxed, engaged, stressed }

/// Whether a 15-minute slot is a zone reading, exercise gap, or no-data gap.
enum StressSlotType { zone, exercise, noData }

extension StressZoneX on StressZone {
  String get label => switch (this) {
        StressZone.restored => 'Restored',
        StressZone.relaxed => 'Relaxed',
        StressZone.engaged => 'Engaged',
        StressZone.stressed => 'Stressed',
      };

  String get description => switch (this) {
        StressZone.restored =>
          'Body is in pure rest/recovery, parasympathetic dominant',
        StressZone.relaxed =>
          'Mild recovery state, low sympathetic activation',
        StressZone.engaged =>
          'Elevated but productive stress — normal during focus or activity',
        StressZone.stressed =>
          'High sympathetic activation, body needs recovery',
      };

  /// Zone color as specified in the design.
  Color get color => switch (this) {
        StressZone.restored => const Color(0xFFFFFFFF),
        StressZone.relaxed => const Color(0xFFFFF9C4),
        StressZone.engaged => const Color(0xFFF9A825),
        StressZone.stressed => const Color(0xFFE65100),
      };

  /// Chart fill color — restored gets a tinted fill so it's visible on white.
  Color get chartColor => switch (this) {
        StressZone.restored => const Color(0xFFE8E6E1),
        StressZone.relaxed => const Color(0xFFFFF59D),
        StressZone.engaged => const Color(0xFFF9A825),
        StressZone.stressed => const Color(0xFFE65100),
      };

  /// Accent color for cards/badges — needs to be visible on white bg.
  Color get displayColor => switch (this) {
        StressZone.restored => const Color(0xFFA8A29E),
        StressZone.relaxed => const Color(0xFFFBC02D),
        StressZone.engaged => const Color(0xFFF57F17),
        StressZone.stressed => const Color(0xFFBF360C),
      };

  /// Normalized value for chart height (0–1).
  double get chartValue => switch (this) {
        StressZone.restored => 0.18,
        StressZone.relaxed => 0.40,
        StressZone.engaged => 0.70,
        StressZone.stressed => 0.95,
      };
}

// ─── Reading ─────────────────────────────────────────────────────────────────

/// A single 15-minute stress reading.
class StressReading {
  final DateTime time;
  final StressSlotType type;
  final StressZone? zone;
  final double? hr;

  const StressReading({
    required this.time,
    required this.type,
    this.zone,
    this.hr,
  });

  factory StressReading.fromJson(Map<String, dynamic> json) {
    return StressReading(
      time: DateTime.parse(json['time'] as String).toUtc(),
      type: StressSlotType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => StressSlotType.zone,
      ),
      zone: json['zone'] != null
          ? StressZone.values.firstWhere(
              (e) => e.name == json['zone'],
              orElse: () => StressZone.relaxed,
            )
          : null,
      hr: (json['hr'] as num?)?.toDouble(),
    );
  }
}

// ─── Day summary ─────────────────────────────────────────────────────────────

/// Summary of a single day's stress data.
class StressDaySummary {
  final DateTime date;
  final DateTime? wakeTime;
  final List<StressReading> timeline;
  final Duration restoredTime;
  final Duration relaxedTime;
  final Duration engagedTime;
  final Duration stressedTime;
  final Duration activeTime;
  final Duration noDataTime;
  final String? insight;
  final int baselineDaysCollected;
  final bool hasData;

  const StressDaySummary({
    required this.date,
    this.wakeTime,
    this.timeline = const [],
    this.restoredTime = Duration.zero,
    this.relaxedTime = Duration.zero,
    this.engagedTime = Duration.zero,
    this.stressedTime = Duration.zero,
    this.activeTime = Duration.zero,
    this.noDataTime = Duration.zero,
    this.insight,
    this.baselineDaysCollected = 0,
    this.hasData = false,
  });

  /// Total tracked time across all zones.
  Duration get totalTrackedTime =>
      restoredTime + relaxedTime + engagedTime + stressedTime;

  /// Daily stress score (0–100, higher = better/calmer).
  ///
  /// Each zone carries a physiological stress weight:
  ///   Restored = 0, Relaxed = 25, Engaged = 60, Stressed = 100
  /// The score inverts the weighted average so lower stress = higher score.
  int get score {
    final total = totalTrackedTime.inMinutes;
    if (total == 0) return 0;
    final weightedStress =
        (relaxedTime.inMinutes * 25) +
        (engagedTime.inMinutes * 60) +
        (stressedTime.inMinutes * 100);
    return (100 - weightedStress / total).round().clamp(0, 100);
  }

  /// Human-readable label for the current score.
  String get scoreLabel {
    if (!hasData) return '';
    if (score >= 85) return 'Very Calm';
    if (score >= 65) return 'Balanced';
    if (score >= 40) return 'Moderate';
    return 'Under Strain';
  }

  /// Average zone for the day, derived from the score (for color coding).
  StressZone get averageZone {
    if (score >= 85) return StressZone.restored;
    if (score >= 65) return StressZone.relaxed;
    if (score >= 40) return StressZone.engaged;
    return StressZone.stressed;
  }

  /// Current zone (last zone reading in timeline).
  StressZone? get currentZone {
    for (int i = timeline.length - 1; i >= 0; i--) {
      if (timeline[i].type == StressSlotType.zone &&
          timeline[i].zone != null) {
        return timeline[i].zone;
      }
    }
    return null;
  }

  factory StressDaySummary.fromJson(Map<String, dynamic> json) {
    return StressDaySummary(
      date: DateTime.parse(json['date'] as String).toUtc(),
      wakeTime: json['wake_time'] != null
          ? DateTime.parse(json['wake_time'] as String).toUtc()
          : null,
      timeline: (json['timeline'] as List?)
              ?.map((e) => StressReading.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      restoredTime:
          Duration(minutes: (json['restored_minutes'] as num?)?.toInt() ?? 0),
      relaxedTime:
          Duration(minutes: (json['relaxed_minutes'] as num?)?.toInt() ?? 0),
      engagedTime:
          Duration(minutes: (json['engaged_minutes'] as num?)?.toInt() ?? 0),
      stressedTime:
          Duration(minutes: (json['stressed_minutes'] as num?)?.toInt() ?? 0),
      activeTime:
          Duration(minutes: (json['active_minutes'] as num?)?.toInt() ?? 0),
      noDataTime:
          Duration(minutes: (json['no_data_minutes'] as num?)?.toInt() ?? 0),
      insight: json['insight'] as String?,
      baselineDaysCollected:
          (json['baseline_days_collected'] as num?)?.toInt() ?? 0,
      hasData: json['has_data'] as bool? ?? false,
    );
  }
}

// ─── Week summary ────────────────────────────────────────────────────────────

/// 7-day stress trend data.
class StressWeekData {
  final List<StressDaySummary> days;
  final String trendLabel;

  const StressWeekData({
    this.days = const [],
    this.trendLabel = '',
  });
}
