import 'dart:math';
import '../../shared/models/stress_models.dart';

/// Service for fetching stress zone data from the backend.
///
/// Currently returns demo data — swap the method bodies for real API calls
/// when the backend endpoints are ready.
class StressService {
  static final StressService _instance = StressService._internal();
  factory StressService() => _instance;
  StressService._internal();

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Fetch today's stress timeline and summary.
  Future<StressDaySummary> getTodayStress() async {
    // TODO: Replace with real API call: GET /api/v1/stress/today
    await Future.delayed(const Duration(milliseconds: 300));
    return _generateDemoDay(DateTime.now());
  }

  /// Fetch 7-day stress history.
  Future<StressWeekData> getWeekStress() async {
    // TODO: Replace with real API call: GET /api/v1/stress/week
    await Future.delayed(const Duration(milliseconds: 200));
    return _generateDemoWeek();
  }

  // ─── Demo data generation ──────────────────────────────────────────────────

  /// Deterministic PRNG seeded by date so same day always produces same data.
  Random _rng(DateTime date) => Random(date.year * 10000 + date.month * 100 + date.day);

  StressDaySummary _generateDemoDay(DateTime date) {
    final rng = _rng(date);
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    // Wake time: 6:00–7:30 AM
    final wakeHour = 6;
    final wakeMinute = (rng.nextInt(7)) * 15; // 0, 15, 30, 45, 60, 75, 90 → clamp
    final wakeTime = DateTime(date.year, date.month, date.day, wakeHour,
        wakeMinute.clamp(0, 45));

    // End time: now if today, otherwise 10:00–11:00 PM
    final endTime = isToday
        ? now
        : DateTime(date.year, date.month, date.day, 22, rng.nextInt(4) * 15);

    // Generate 15-min readings from wake to end
    final timeline = <StressReading>[];
    var cursor = wakeTime;

    // Exercise block: 1 period per day, 30–60 min
    final exerciseStartHour = 15 + rng.nextInt(3); // 3–5 PM
    final exerciseStart = DateTime(
        date.year, date.month, date.day, exerciseStartHour, 0);
    final exerciseDuration = Duration(minutes: (rng.nextInt(3) + 2) * 15); // 30–60 min
    final exerciseEnd = exerciseStart.add(exerciseDuration);

    // Zone pattern weights shift throughout the day
    while (cursor.isBefore(endTime)) {
      final hour = cursor.hour + cursor.minute / 60.0;

      // Check if in exercise block
      if (cursor.isAfter(exerciseStart.subtract(const Duration(minutes: 1))) &&
          cursor.isBefore(exerciseEnd)) {
        timeline.add(StressReading(
          time: cursor,
          type: StressSlotType.exercise,
          hr: 120 + rng.nextInt(40).toDouble(),
        ));
        cursor = cursor.add(const Duration(minutes: 15));
        continue;
      }

      // Determine zone based on time of day + randomness
      final zone = _zoneForTime(hour, rng);
      final baseHr = _baseHrForZone(zone, rng);

      timeline.add(StressReading(
        time: cursor,
        type: StressSlotType.zone,
        zone: zone,
        hr: baseHr,
      ));
      cursor = cursor.add(const Duration(minutes: 15));
    }

    // Calculate zone durations
    int restoredMin = 0, relaxedMin = 0, engagedMin = 0, stressedMin = 0;
    int activeMin = 0, noDataMin = 0;
    for (final r in timeline) {
      switch (r.type) {
        case StressSlotType.zone:
          switch (r.zone!) {
            case StressZone.restored:
              restoredMin += 15;
            case StressZone.relaxed:
              relaxedMin += 15;
            case StressZone.engaged:
              engagedMin += 15;
            case StressZone.stressed:
              stressedMin += 15;
          }
        case StressSlotType.exercise:
          activeMin += 15;
        case StressSlotType.noData:
          noDataMin += 15;
      }
    }

    final insight = _generateInsight(
      restoredMin: restoredMin,
      relaxedMin: relaxedMin,
      engagedMin: engagedMin,
      stressedMin: stressedMin,
      rng: rng,
    );

    return StressDaySummary(
      date: date,
      wakeTime: wakeTime,
      timeline: timeline,
      restoredTime: Duration(minutes: restoredMin),
      relaxedTime: Duration(minutes: relaxedMin),
      engagedTime: Duration(minutes: engagedMin),
      stressedTime: Duration(minutes: stressedMin),
      activeTime: Duration(minutes: activeMin),
      noDataTime: Duration(minutes: noDataMin),
      insight: insight,
      baselineDaysCollected: 8,
      hasData: true,
    );
  }

  StressZone _zoneForTime(double hour, Random rng) {
    // Early morning (6–8): mostly restored/relaxed
    if (hour < 8) {
      return _weightedPick(rng, {
        StressZone.restored: 40,
        StressZone.relaxed: 45,
        StressZone.engaged: 12,
        StressZone.stressed: 3,
      });
    }
    // Morning (8–12): engaged/relaxed
    if (hour < 12) {
      return _weightedPick(rng, {
        StressZone.restored: 8,
        StressZone.relaxed: 30,
        StressZone.engaged: 48,
        StressZone.stressed: 14,
      });
    }
    // Lunch (12–13): relaxed
    if (hour < 13) {
      return _weightedPick(rng, {
        StressZone.restored: 15,
        StressZone.relaxed: 55,
        StressZone.engaged: 25,
        StressZone.stressed: 5,
      });
    }
    // Afternoon (13–17): engaged with some stressed
    if (hour < 17) {
      return _weightedPick(rng, {
        StressZone.restored: 5,
        StressZone.relaxed: 22,
        StressZone.engaged: 48,
        StressZone.stressed: 25,
      });
    }
    // Post-exercise / evening (17–20): restored/relaxed
    if (hour < 20) {
      return _weightedPick(rng, {
        StressZone.restored: 30,
        StressZone.relaxed: 45,
        StressZone.engaged: 20,
        StressZone.stressed: 5,
      });
    }
    // Night (20+): restored
    return _weightedPick(rng, {
      StressZone.restored: 50,
      StressZone.relaxed: 38,
      StressZone.engaged: 10,
      StressZone.stressed: 2,
    });
  }

  StressZone _weightedPick(Random rng, Map<StressZone, int> weights) {
    final total = weights.values.reduce((a, b) => a + b);
    var roll = rng.nextInt(total);
    for (final entry in weights.entries) {
      roll -= entry.value;
      if (roll < 0) return entry.key;
    }
    return weights.keys.last;
  }

  double _baseHrForZone(StressZone zone, Random rng) {
    return switch (zone) {
      StressZone.restored => 58 + rng.nextInt(8).toDouble(),
      StressZone.relaxed => 66 + rng.nextInt(10).toDouble(),
      StressZone.engaged => 78 + rng.nextInt(12).toDouble(),
      StressZone.stressed => 92 + rng.nextInt(15).toDouble(),
    };
  }

  String _generateInsight({
    required int restoredMin,
    required int relaxedMin,
    required int engagedMin,
    required int stressedMin,
    required Random rng,
  }) {
    final total = restoredMin + relaxedMin + engagedMin + stressedMin;
    if (total == 0) return 'No stress data recorded yet today.';

    final stressedRatio = stressedMin / total;
    final restoredRatio = restoredMin / total;
    final calmRatio = (restoredMin + relaxedMin) / total;

    if (stressedRatio > 0.3) {
      return 'Your body showed elevated stress for a good part of the day '
          '— consider some wind-down time tonight.';
    }
    if (restoredRatio > 0.3) {
      return 'Mostly restored today — great recovery day! '
          'Your body is getting plenty of rest.';
    }
    if (calmRatio > 0.6) {
      return 'A calm and balanced day so far. '
          'Your stress levels have been low — keep it up!';
    }
    return 'You had a calm morning with a more active afternoon '
        '— good balance overall.';
  }

  StressWeekData _generateDemoWeek() {
    final now = DateTime.now();
    final days = <StressDaySummary>[];

    for (int i = 6; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      days.add(_generateDemoDay(date));
    }

    // Generate trend label based on average score
    final avgScore = days.isEmpty
        ? 0.0
        : days.map((d) => d.score.toDouble()).reduce((a, b) => a + b) /
            days.length;

    final String trendLabel;
    if (avgScore >= 75) {
      trendLabel = 'Your stress has been well-managed this week';
    } else if (avgScore >= 50) {
      trendLabel = 'Your stress has been typical this week';
    } else {
      trendLabel = 'More stressed time than usual this week';
    }

    return StressWeekData(days: days, trendLabel: trendLabel);
  }
}
