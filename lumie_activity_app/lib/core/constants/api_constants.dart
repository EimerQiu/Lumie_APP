/// API configuration constants
class ApiConstants {
  ApiConstants._();

  // Base URL - change this for different environments
  static const String baseUrl = 'http://localhost:8000/api/v1';

  // Endpoints
  static const String activityTypes = '/activity-types';
  static const String dailySummary = '/activity/daily';
  static const String weeklySummary = '/activity/weekly';
  static const String adaptiveGoal = '/activity/goal';
  static const String activity = '/activity';
  static const String ringStatus = '/ring/status';
  static const String ringDetected = '/ring/detected';
  static const String walkTestHistory = '/walk-test/history';
  static const String walkTest = '/walk-test';
  static const String walkTestBest = '/walk-test/best';
  static const String health = '/health';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
