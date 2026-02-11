import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';
import '../../shared/models/rest_days_models.dart';

/// Service for managing user rest days.
class RestDaysService {
  static final RestDaysService _instance = RestDaysService._internal();
  factory RestDaysService() => _instance;
  RestDaysService._internal();

  final AuthService _authService = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  /// Get user's rest days configuration.
  Future<RestDaySettings> getRestDays() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/rest-days'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return RestDaySettings.fromJson(json.decode(response.body));
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to load rest days');
      }
    } catch (e) {
      print('⚠️ Failed to load rest days: $e');
      // Return empty settings as fallback
      return RestDaySettings(
        weeklyRestDays: [],
        specificDates: [],
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Update user's rest days configuration.
  Future<RestDaySettings> updateRestDays(RestDaySettings settings) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/rest-days'),
        headers: _headers,
        body: json.encode(settings.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return RestDaySettings.fromJson(json.decode(response.body));
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to update rest days');
      }
    } catch (e) {
      print('⚠️ Failed to update rest days: $e');
      rethrow;
    }
  }

  /// Check if today is a rest day.
  Future<bool> checkTodayIsRestDay() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/rest-days/check-today'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['is_rest_day'] ?? false;
      } else {
        return false;
      }
    } catch (e) {
      print('⚠️ Failed to check rest day: $e');
      return false;
    }
  }

  /// Get rest day suggestion based on sleep quality.
  Future<RestDaySuggestion> getRestDaySuggestion() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/rest-days/suggestion'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return RestDaySuggestion.fromJson(json.decode(response.body));
      } else {
        // Return no suggestion
        return const RestDaySuggestion(
          shouldSuggest: false,
          reason: '',
          sleepQuality: 100,
          message: '',
        );
      }
    } catch (e) {
      print('⚠️ Failed to get rest day suggestion: $e');
      return const RestDaySuggestion(
        shouldSuggest: false,
        reason: '',
        sleepQuality: 100,
        message: '',
      );
    }
  }

  /// Set today as a rest day.
  Future<void> setTodayAsRestDay() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/rest-days/set-today'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to set rest day');
      }
    } catch (e) {
      print('⚠️ Failed to set today as rest day: $e');
      rethrow;
    }
  }
}
