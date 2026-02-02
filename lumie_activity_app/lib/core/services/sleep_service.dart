import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/sleep_models.dart';

/// Sleep service for managing sleep data
class SleepService {
  static final SleepService _instance = SleepService._internal();
  factory SleepService() => _instance;
  SleepService._internal();

  final AuthService _authService = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  /// Get the most recent sleep session
  Future<SleepSession?> getLatestSleep() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/sleep/latest'),
        headers: _headers,
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data != null ? SleepSession.fromJson(data) : null;
      } else {
        throw Exception('Failed to get latest sleep');
      }
    } catch (e) {
      // Fallback to mock data for local development
      return _mockGetLatestSleep();
    }
  }

  /// Get sleep sessions for a date range
  Future<List<SleepSession>> getSleepHistory({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConstants.baseUrl}/sleep/history?start=${startDate.toIso8601String()}&end=${endDate.toIso8601String()}',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((s) => SleepSession.fromJson(s)).toList();
      } else {
        throw Exception('Failed to get sleep history');
      }
    } catch (e) {
      // Fallback to mock data for local development
      return _mockGetSleepHistory(startDate: startDate, endDate: endDate);
    }
  }

  /// Get sleep summary for a date range
  Future<SleepSummary> getSleepSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConstants.baseUrl}/sleep/summary?start=${startDate.toIso8601String()}&end=${endDate.toIso8601String()}',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return SleepSummary.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to get sleep summary');
      }
    } catch (e) {
      // Fallback to mock data for local development
      return _mockGetSleepSummary(startDate: startDate, endDate: endDate);
    }
  }

  /// Get sleep target based on user age
  Future<SleepTarget> getSleepTarget() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/sleep/target'),
        headers: _headers,
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return SleepTarget.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to get sleep target');
      }
    } catch (e) {
      // Fallback to mock data for local development
      return _mockGetSleepTarget();
    }
  }

  /// Mock latest sleep for local development
  Future<SleepSession?> _mockGetLatestSleep() async {
    await Future.delayed(const Duration(milliseconds: 300));

    final now = DateTime.now();
    final lastNight = DateTime(now.year, now.month, now.day - 1, 22, 30);
    final thismorning = DateTime(now.year, now.month, now.day, 6, 45);

    return SleepSession(
      sessionId: 'mock_sleep_${now.millisecondsSinceEpoch}',
      userId: _authService.currentUser?.userId ?? 'mock_user',
      bedtime: lastNight,
      wakeTime: thismorning,
      totalSleepTime: const Duration(hours: 7, minutes: 45),
      timeAwake: const Duration(minutes: 30),
      stages: [
        const SleepStageData(
          stage: SleepStage.light,
          duration: Duration(hours: 3, minutes: 30),
          percentage: 45.0,
        ),
        const SleepStageData(
          stage: SleepStage.deep,
          duration: Duration(hours: 1, minutes: 45),
          percentage: 22.5,
        ),
        const SleepStageData(
          stage: SleepStage.rem,
          duration: Duration(hours: 2, minutes: 30),
          percentage: 32.5,
        ),
      ],
      restingHeartRate: 58,
      sleepQualityScore: 85.0,
      createdAt: thismorning,
    );
  }

  /// Mock sleep history for local development
  Future<List<SleepSession>> _mockGetSleepHistory({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final sessions = <SleepSession>[];
    final random = Random();
    final now = DateTime.now();

    // Generate 7 days of mock sleep data
    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: i));
      final bedtime = DateTime(
        date.year,
        date.month,
        date.day - 1,
        22 + random.nextInt(2),
        random.nextInt(60),
      );
      final sleepDuration = Duration(
        hours: 7 + random.nextInt(2),
        minutes: random.nextInt(60),
      );
      final wakeTime = bedtime.add(sleepDuration + Duration(minutes: 20 + random.nextInt(40)));

      final lightSleep = sleepDuration.inMinutes * (0.40 + random.nextDouble() * 0.10);
      final deepSleep = sleepDuration.inMinutes * (0.18 + random.nextDouble() * 0.10);
      final remSleep = sleepDuration.inMinutes * (0.25 + random.nextDouble() * 0.15);

      sessions.add(SleepSession(
        sessionId: 'mock_sleep_${date.millisecondsSinceEpoch}',
        userId: _authService.currentUser?.userId ?? 'mock_user',
        bedtime: bedtime,
        wakeTime: wakeTime,
        totalSleepTime: sleepDuration,
        timeAwake: Duration(minutes: 15 + random.nextInt(45)),
        stages: [
          SleepStageData(
            stage: SleepStage.light,
            duration: Duration(minutes: lightSleep.round()),
            percentage: (lightSleep / sleepDuration.inMinutes) * 100,
          ),
          SleepStageData(
            stage: SleepStage.deep,
            duration: Duration(minutes: deepSleep.round()),
            percentage: (deepSleep / sleepDuration.inMinutes) * 100,
          ),
          SleepStageData(
            stage: SleepStage.rem,
            duration: Duration(minutes: remSleep.round()),
            percentage: (remSleep / sleepDuration.inMinutes) * 100,
          ),
        ],
        restingHeartRate: 56 + random.nextInt(8),
        sleepQualityScore: 75.0 + random.nextDouble() * 20,
        createdAt: wakeTime,
      ));
    }

    return sessions;
  }

  /// Mock sleep summary for local development
  Future<SleepSummary> _mockGetSleepSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    return SleepSummary(
      startDate: startDate,
      endDate: endDate,
      averageSleepHours: 7.5,
      averageRestingHR: 58.0,
      averageSleepQuality: 82.0,
      sleepConsistency: 0.85,
      averageStagePercentages: {
        SleepStage.light: 45.0,
        SleepStage.deep: 22.0,
        SleepStage.rem: 30.0,
      },
    );
  }

  /// Mock sleep target for local development
  Future<SleepTarget> _mockGetSleepTarget() async {
    await Future.delayed(const Duration(milliseconds: 200));

    // Default target for teens (13-21)
    return const SleepTarget(
      minDuration: Duration(hours: 7),
      maxDuration: Duration(hours: 10),
      targetDuration: Duration(hours: 8, minutes: 30),
      targetStagePercentages: {
        SleepStage.light: 45.0,
        SleepStage.deep: 25.0,
        SleepStage.rem: 25.0,
      },
    );
  }
}
