/// Push Notification Service
///
/// Requests APNs permission and uploads the device token to the backend.
/// Uses native iOS APIs via MethodChannel — no Firebase dependency.
///
/// Also listens for notification taps and exposes a navigation callback
/// so the app can deep-link to the correct screen (e.g. Advisor).

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';

/// Callback type for notification tap navigation.
/// The [data] map contains the notification payload (e.g. `navigate_to`, `type`).
typedef NotificationTapCallback = void Function(Map<String, dynamic> data);
typedef NotificationReceiveCallback = void Function(Map<String, dynamic> data);

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static const _channel = MethodChannel('com.lumie.app/push');

  String? _token;
  NotificationTapCallback? _onTap;
  NotificationReceiveCallback? _onReceive;

  String? get token => _token;

  /// Register a callback to be invoked when the user taps a push notification.
  /// The callback receives the notification payload as a Map.
  void setOnNotificationTap(NotificationTapCallback callback) {
    _onTap = callback;
  }

  /// Register a callback to be invoked when a push arrives while the app is open.
  void setOnNotificationReceived(NotificationReceiveCallback callback) {
    _onReceive = callback;
  }

  /// Called on every app launch once the user is authenticated.
  /// Requests permission (no-op if already granted), retrieves the APNs
  /// device token, and POSTs it to the backend.
  Future<void> init(String authToken) async {
    if (!Platform.isIOS) return; // Android/FCM is P1

    // Listen for notification tap events from native
    _channel.setMethodCallHandler(_handleMethodCall);

    try {
      final deviceToken = await _channel.invokeMethod<String>('getDeviceToken');
      if (deviceToken == null || deviceToken.isEmpty) {
        debugPrint('[PUSHDBG] getDeviceToken returned empty');
        return;
      }

      debugPrint('[PUSHDBG] APNs token acquired: $deviceToken');
      _token = deviceToken;
      await _uploadToken(authToken, deviceToken);
    } on PlatformException catch (e) {
      // Permission denied or unavailable — not fatal
      debugPrint('[PUSHDBG] Push notification init failed: ${e.message}');
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onNotificationTap') {
      final data = Map<String, dynamic>.from(call.arguments as Map);
      debugPrint(
        '[RCMD] Push tap: type=${data['type']} navigate_to=${data['navigate_to']} request_id=${data['request_id']}',
      );
      _onTap?.call(data);
    } else if (call.method == 'onNotificationReceived') {
      final data = Map<String, dynamic>.from(call.arguments as Map);
      debugPrint(
        '[RCMD] Push received: type=${data['type']} navigate_to=${data['navigate_to']} request_id=${data['request_id']}',
      );
      _onReceive?.call(data);
    }
  }

  Future<void> _uploadToken(String authToken, String deviceToken) async {
    try {
      debugPrint('[PUSHDBG] Uploading token to backend: $deviceToken');
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/save-device-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: json.encode({'device_token': deviceToken}),
      );
      debugPrint('[PUSHDBG] Token upload response: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[PUSHDBG] Token upload failed: ${response.body}');
      } else {
        debugPrint('[PUSHDBG] Token upload successful');
      }
    } catch (e) {
      debugPrint('[PUSHDBG] Failed to upload device token: $e');
    }
  }

  /// Remove server-side token on logout.
  Future<void> deleteToken(String authToken) async {
    try {
      debugPrint('[PUSHDBG] Deleting token from backend: $_token');
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/auth/device-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );
      debugPrint('[PUSHDBG] Token deletion response: ${response.statusCode}');
    } catch (e) {
      debugPrint('[PUSHDBG] Failed to delete token: $e');
    }
    _token = null;
    debugPrint('[PUSHDBG] Token cleared locally');
  }
}
