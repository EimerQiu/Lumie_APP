/// Push Notification Service
///
/// Requests APNs permission and uploads the device token to the backend.
/// Uses native iOS APIs via MethodChannel — no Firebase dependency.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static const _channel = MethodChannel('com.lumie.app/push');

  String? _token;

  String? get token => _token;

  /// Called on every app launch once the user is authenticated.
  /// Requests permission (no-op if already granted), retrieves the APNs
  /// device token, and POSTs it to the backend.
  Future<void> init(String authToken) async {
    if (!Platform.isIOS) return; // Android/FCM is P1

    try {
      final deviceToken = await _channel.invokeMethod<String>('getDeviceToken');
      if (deviceToken == null || deviceToken.isEmpty) return;

      _token = deviceToken;
      await _uploadToken(authToken, deviceToken);
    } on PlatformException catch (e) {
      // Permission denied or unavailable — not fatal
      print('Push notification init failed: ${e.message}');
    }
  }

  Future<void> _uploadToken(String authToken, String deviceToken) async {
    try {
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/save-device-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: json.encode({'device_token': deviceToken}),
      );
    } catch (e) {
      print('Failed to upload device token: $e');
    }
  }

  /// Remove server-side token on logout.
  Future<void> deleteToken(String authToken) async {
    try {
      await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/auth/device-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
    } catch (_) {}
    _token = null;
  }
}
