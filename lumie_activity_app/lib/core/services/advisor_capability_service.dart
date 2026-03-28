import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';

/// A system capability that controls which skills Advisor can use.
class AdvisorCapability {
  final String capabilityId;
  final String displayName;
  final String description;
  final bool enabled;
  final String status; // "disabled", "enabled_not_ready", "ready"

  const AdvisorCapability({
    required this.capabilityId,
    required this.displayName,
    required this.description,
    required this.enabled,
    required this.status,
  });

  factory AdvisorCapability.fromJson(Map<String, dynamic> json) {
    return AdvisorCapability(
      capabilityId: json['capability_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      status: json['status'] as String? ?? 'disabled',
    );
  }

  bool get isReady => status == 'ready';
  bool get isEnabled => status != 'disabled';
}

/// Service for managing Advisor capabilities.
class AdvisorCapabilityService {
  static final AdvisorCapabilityService _instance =
      AdvisorCapabilityService._internal();
  factory AdvisorCapabilityService() => _instance;
  AdvisorCapabilityService._internal();

  final AuthService _authService = AuthService();

  String get _baseUrl => ApiConstants.baseUrlV2;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  /// Fetch all capabilities with user state.
  Future<List<AdvisorCapability>> getCapabilities() async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2Capabilities}'),
          headers: _headers,
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final list = data['capabilities'] as List<dynamic>? ?? [];
      return list
          .map((e) => AdvisorCapability.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to fetch capabilities');
  }

  /// Toggle a capability on or off.
  Future<Map<String, dynamic>> toggleCapability(
    String capabilityId,
    bool enabled,
  ) async {
    final response = await http
        .patch(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2Capabilities}/$capabilityId'),
          headers: _headers,
          body: json.encode({'enabled': enabled}),
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to toggle capability');
  }
}
