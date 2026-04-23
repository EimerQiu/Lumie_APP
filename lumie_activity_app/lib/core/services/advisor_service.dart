import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'auth_service.dart';

/// A single message in the conversation history.
class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  const ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Unified response from the Advisor endpoint.
///
/// [type] is either `"direct"` (fast path) or `"analysis"` (slow path).
/// For analysis responses, [jobId] contains the UUID to poll for results.
class AdvisorResponse {
  final String type; // "direct" or "analysis"
  final String reply;
  final String? jobId;
  final String? navHint; // "task_list" | "task_dashboard" | null

  const AdvisorResponse.direct({required this.reply, this.navHint})
      : type = 'direct',
        jobId = null;

  const AdvisorResponse.analysis({required this.reply, required this.jobId})
      : type = 'analysis',
        navHint = null;

  factory AdvisorResponse.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'direct';
    if (type == 'analysis') {
      return AdvisorResponse.analysis(
        reply: json['reply'] as String? ?? '',
        jobId: json['job_id'] as String?,
      );
    }
    return AdvisorResponse.direct(
      reply: json['reply'] as String? ?? '',
      navHint: json['nav_hint'] as String?,
    );
  }
}

/// Service for the Lumie Advisor AI chat.
///
/// Sends a message + conversation history to POST /advisor/chat and returns
/// an [AdvisorResponse] that may be a direct reply or an analysis job.
class AdvisorService {
  static final AdvisorService _instance = AdvisorService._internal();
  factory AdvisorService() => _instance;
  AdvisorService._internal();

  final AuthService _authService = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      };

  static const List<String> _stubReplies = [
    'Based on your recent activity patterns, a 20-minute walk today would be a great start. Your fatigue score is moderate, so keep it light.',
    'Your sleep last night was above your weekly average \u2014 that\'s a great sign for recovery. Today is a good day to push a little harder if you feel ready.',
    'I notice you haven\'t logged activity in the past two days. Even gentle stretching counts! Listen to your body first.',
    'Your advisor has flagged this as a lower-intensity week. Focus on consistency over intensity right now.',
    'Great question! For your condition, low-impact aerobic activity like swimming or cycling tends to be well-tolerated. Always check with your care team before increasing intensity.',
    'Check-in tip: Try to log your activity within an hour of finishing \u2014 it helps build an accurate picture of your trends.',
  ];
  int _stubIndex = 0;

  /// Send [message] to the backend along with the full [history] of prior
  /// turns. Returns an [AdvisorResponse] which may be direct or analysis.
  Future<AdvisorResponse> sendMessage(
    String message, {
    List<ChatMessage> history = const [],
    String? sessionId,
  }) async {
    try {
      final body = <String, dynamic>{
        'message': message,
        'history': history.map((m) => m.toJson()).toList(),
      };
      if (sessionId != null) {
        body['session_id'] = sessionId;
      }
      final response = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.advisorChat}'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(ApiConstants.receiveTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return AdvisorResponse.fromJson(data);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Advisor request failed');
      }
    } catch (_) {
      // Fallback to stub while backend endpoint is not yet deployed.
      await Future.delayed(const Duration(milliseconds: 900));
      final reply = _stubReplies[_stubIndex % _stubReplies.length];
      _stubIndex++;
      return AdvisorResponse.direct(reply: reply);
    }
  }
}
