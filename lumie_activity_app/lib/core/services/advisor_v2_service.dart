import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';

/// Unified response from the v2 Advisor endpoint.
///
/// [type] is "direct", "execution", or "guidance".
/// For execution responses, [jobId] and [skillId] are provided.
class AdvisorV2Response {
  final String type;
  final String reply;
  final String? jobId;
  final String? skillId;
  final String? status;
  final String? navHint;

  const AdvisorV2Response({
    required this.type,
    required this.reply,
    this.jobId,
    this.skillId,
    this.status,
    this.navHint,
  });

  factory AdvisorV2Response.fromJson(Map<String, dynamic> json) {
    return AdvisorV2Response(
      type: json['type'] as String? ?? 'direct',
      reply: json['reply'] as String? ?? '',
      jobId: json['job_id'] as String?,
      skillId: json['skill_id'] as String?,
      status: json['status'] as String?,
      navHint: json['nav_hint'] as String?,
    );
  }

  bool get isExecution => type == 'execution';
  bool get isDirect => type == 'direct';
  bool get isGuidance => type == 'guidance';
}

/// Service for the Lumie Advisor v2 API (unified capability + skill system).
class AdvisorV2Service {
  static final AdvisorV2Service _instance = AdvisorV2Service._internal();
  factory AdvisorV2Service() => _instance;
  AdvisorV2Service._internal();

  final AuthService _authService = AuthService();

  String get _baseUrl => ApiConstants.baseUrlV2;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${_authService.token}',
  };

  /// Send a chat message to the v2 advisor endpoint.
  Future<AdvisorV2Response> sendMessage(
    String message, {
    List<Map<String, String>> history = const [],
    String? sessionId,
    String? teamId,
  }) async {
    final body = <String, dynamic>{'message': message, 'history': history};
    if (sessionId != null) body['session_id'] = sessionId;
    if (teamId != null) body['team_id'] = teamId;

    final response = await http
        .post(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2Chat}'),
          headers: _headers,
          body: json.encode(body),
        )
        .timeout(ApiConstants.receiveTimeout);

    if (response.statusCode == 200) {
      return AdvisorV2Response.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    final error = json.decode(response.body);
    throw Exception(error['detail'] ?? 'Advisor request failed');
  }

  /// Poll an execution job until it completes or times out.
  Future<Map<String, dynamic>> pollJobResult(
    String jobId, {
    int maxWaitSeconds = 120,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: maxWaitSeconds));

    while (DateTime.now().isBefore(deadline)) {
      final response = await http
          .get(
            Uri.parse('$_baseUrl${ApiConstants.advisorV2Jobs}/$jobId'),
            headers: _headers,
          )
          .timeout(ApiConstants.connectTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';

        if (status == 'success' ||
            status == 'failed' ||
            status == 'cancelled') {
          return data;
        }
      }

      await Future.delayed(const Duration(seconds: 2));
    }

    return {'status': 'failed', 'error': 'Execution timed out'};
  }

  /// Cancel a running execution job.
  Future<bool> cancelJob(String jobId) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${ApiConstants.advisorV2Jobs}/$jobId/cancel'),
          headers: _headers,
        )
        .timeout(ApiConstants.connectTimeout);
    return response.statusCode == 200;
  }
}
