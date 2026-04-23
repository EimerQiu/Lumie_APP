/// Advisor Check-in Notification Preferences Service
///
/// Manages the user's proactive advisor check-in push notification settings.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';

class CheckinPrefs {
  final bool enabled;
  final String frequency; // "high" (30m) | "normal" (1h) | "lazy" (6h)

  const CheckinPrefs({
    this.enabled = false,
    this.frequency = 'normal',
  });

  factory CheckinPrefs.fromJson(Map<String, dynamic> json) {
    return CheckinPrefs(
      enabled: json['enabled'] as bool? ?? false,
      frequency: json['frequency'] as String? ?? 'normal',
    );
  }
}

class CheckinService {
  static final CheckinService _instance = CheckinService._internal();
  factory CheckinService() => _instance;
  CheckinService._internal();

  final AuthService _auth = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_auth.token}',
      };

  Future<CheckinPrefs> getPreferences() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/advisor/checkin/preferences'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return CheckinPrefs.fromJson(
            json.decode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const CheckinPrefs();
  }

  Future<CheckinPrefs> updatePreferences({
    bool? enabled,
    String? frequency,
  }) async {
    final body = <String, dynamic>{};
    if (enabled != null) body['enabled'] = enabled;
    if (frequency != null) body['frequency'] = frequency;

    try {
      final response = await http.patch(
        Uri.parse('${ApiConstants.baseUrl}/advisor/checkin/preferences'),
        headers: _headers,
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return CheckinPrefs.fromJson(
            json.decode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const CheckinPrefs();
  }
}
