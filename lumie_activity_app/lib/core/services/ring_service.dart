// Backend API service for ring pairing and status management
// Endpoints defined in PRD.md: POST /ring/pair, POST /ring/unpair, GET /ring/status

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../../shared/models/ring_models.dart';

class RingService {
  static final RingService _instance = RingService._internal();
  factory RingService() => _instance;
  RingService._internal();

  static const String _ringInfoKey = 'ring_info';
  static const String _ringPromptShownKey = 'ring_prompt_shown';

  String? _token;

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ─── Local storage helpers ────────────────────────────────────────────────

  /// Whether the ring setup prompt has already been shown to this user
  Future<bool> hasShownRingPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ringPromptShownKey) ?? false;
  }

  Future<void> markRingPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ringPromptShownKey, true);
  }

  /// Load locally cached ring info
  Future<RingInfo?> loadLocalRingInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_ringInfoKey);
    if (json == null) return null;
    try {
      return RingInfo.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  /// Save ring info locally (as a cache)
  Future<void> saveLocalRingInfo(RingInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ringInfoKey, jsonEncode(info.toJson()));
  }

  Future<void> clearLocalRingInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ringInfoKey);
  }

  /// Clear ring-related prefs on logout
  Future<void> clearOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ringInfoKey);
    await prefs.remove(_ringPromptShownKey);
  }

  // ─── Backend API calls ────────────────────────────────────────────────────

  /// POST /ring/pair — Register a paired ring with the backend
  Future<RingInfo> pairRing({
    required String ringDeviceId,
    required String ringName,
    String? firmwareVersion,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/ring/pair'),
        headers: _headers,
        body: jsonEncode({
          'ring_device_id': ringDeviceId,
          'ring_name': ringName,
          if (firmwareVersion != null) 'firmware_version': firmwareVersion,
        }),
      ).timeout(ApiConstants.receiveTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final info = RingInfo.fromJson(jsonDecode(response.body));
        await saveLocalRingInfo(info);
        return info;
      } else {
        // If backend is unavailable, save locally and continue
        final info = RingInfo(
          ringDeviceId: ringDeviceId,
          ringName: ringName,
          connectionStatus: RingConnectionStatus.connected,
          pairedAt: DateTime.now(),
          firmwareVersion: firmwareVersion,
        );
        await saveLocalRingInfo(info);
        return info;
      }
    } catch (_) {
      // Offline fallback — still record locally
      final info = RingInfo(
        ringDeviceId: ringDeviceId,
        ringName: ringName,
        connectionStatus: RingConnectionStatus.connected,
        pairedAt: DateTime.now(),
        firmwareVersion: firmwareVersion,
      );
      await saveLocalRingInfo(info);
      return info;
    }
  }

  /// POST /ring/unpair — Remove ring binding from user profile
  Future<void> unpairRing() async {
    try {
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/ring/unpair'),
        headers: _headers,
      ).timeout(ApiConstants.receiveTimeout);
    } catch (_) {
      // Best-effort; always clear locally
    }
    await clearLocalRingInfo();
  }

  /// GET /ring/status — Fetch current ring status from backend
  Future<RingInfo?> getRingStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/ring/status'),
        headers: _headers,
      ).timeout(ApiConstants.receiveTimeout);

      if (response.statusCode == 200) {
        final info = RingInfo.fromJson(jsonDecode(response.body));
        await saveLocalRingInfo(info);
        return info;
      }
    } catch (_) {
      // Fall back to local cache
    }
    return loadLocalRingInfo();
  }
}
