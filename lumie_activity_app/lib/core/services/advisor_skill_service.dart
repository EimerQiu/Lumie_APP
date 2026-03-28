import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';

/// A system skill that Advisor can execute.
class AdvisorSkill {
  final String skillId;
  final String title;
  final String capabilityId;
  final String skillRuntimeType;
  final String summary;
  final List<String> tags;
  final bool requiresCredentials;
  final bool requiresPing;
  final String status;

  const AdvisorSkill({
    required this.skillId,
    required this.title,
    required this.capabilityId,
    required this.skillRuntimeType,
    required this.summary,
    required this.tags,
    required this.requiresCredentials,
    required this.requiresPing,
    required this.status,
  });

  factory AdvisorSkill.fromJson(Map<String, dynamic> json) {
    return AdvisorSkill(
      skillId: json['skill_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      capabilityId: json['capability_id'] as String? ?? '',
      skillRuntimeType: json['runtime_type'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      requiresCredentials: json['requires_credentials'] as bool? ?? false,
      requiresPing: json['requires_ping'] as bool? ?? false,
      status: json['status'] as String? ?? 'indexed',
    );
  }

  bool get isIndexed => status == 'indexed';
  bool get isLumieInternal => capabilityId == 'lumie_internal_data';
}

/// Credential info for a skill (sanitized — no password/ping values).
class SkillCredential {
  final String credentialId;
  final String skillId;
  final String status; // missing, saved_not_tested, valid, invalid
  final String? systemName;
  final String? baseUrl;
  final String? username;
  final bool hasPassword;
  final bool hasPing;
  final String? notes;
  final String? lastTestedAt;
  final String? lastTestResult;

  const SkillCredential({
    required this.credentialId,
    required this.skillId,
    required this.status,
    this.systemName,
    this.baseUrl,
    this.username,
    this.hasPassword = false,
    this.hasPing = false,
    this.notes,
    this.lastTestedAt,
    this.lastTestResult,
  });

  factory SkillCredential.fromJson(Map<String, dynamic> json) {
    return SkillCredential(
      credentialId: json['credential_id'] as String? ?? '',
      skillId: json['skill_id'] as String? ?? '',
      status: json['status'] as String? ?? 'missing',
      systemName: json['system_name'] as String?,
      baseUrl: json['base_url'] as String?,
      username: json['username'] as String?,
      hasPassword: json['has_password'] as bool? ?? false,
      hasPing: json['has_ping'] as bool? ?? false,
      notes: json['notes'] as String?,
      lastTestedAt: json['last_tested_at'] as String?,
      lastTestResult: json['last_test_result'] as String?,
    );
  }

  bool get isValid => status == 'valid';
  bool get isMissing => status == 'missing';
}

/// Service for managing Advisor skills and credentials.
class AdvisorSkillService {
  static final AdvisorSkillService _instance = AdvisorSkillService._internal();
  factory AdvisorSkillService() => _instance;
  AdvisorSkillService._internal();

  final AuthService _authService = AuthService();

  String get _baseUrl => ApiConstants.baseUrlV2;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  /// Fetch all indexed skills.
  Future<List<AdvisorSkill>> getSkills() async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2Skills}'),
          headers: _headers,
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final list = data['skills'] as List<dynamic>? ?? [];
      return list
          .map((e) => AdvisorSkill.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to fetch skills');
  }

  /// Get credential for a specific skill.
  Future<SkillCredential> getCredential(String skillId) async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2Skills}/$skillId/credential'),
          headers: _headers,
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return SkillCredential.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to fetch credential');
  }

  /// Save credential for a skill.
  Future<SkillCredential> saveCredential(
    String skillId, {
    String? systemName,
    String? baseUrl,
    String? username,
    String? password,
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    if (systemName != null) body['system_name'] = systemName;
    if (baseUrl != null) body['base_url'] = baseUrl;
    if (username != null) body['username'] = username;
    if (password != null) body['password'] = password;
    if (notes != null) body['notes'] = notes;

    final response = await http
        .put(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2Skills}/$skillId/credential'),
          headers: _headers,
          body: json.encode(body),
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return SkillCredential.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to save credential');
  }

  /// Test credential for a skill.
  Future<Map<String, dynamic>> testCredential(String skillId) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2Skills}/$skillId/test'),
          headers: _headers,
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to test credential');
  }

  /// Trigger a skill reindex.
  Future<Map<String, dynamic>> reindexSkills() async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2SkillReindex}'),
          headers: _headers,
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to reindex skills');
  }
}
