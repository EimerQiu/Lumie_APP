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

/// Service for the Lumie Advisor AI chat.
///
/// Sends a message + conversation history to POST /advisor/chat and returns
/// the assistant reply.  Falls back to stub replies when the backend is
/// unreachable (e.g. local development).
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
    'Your sleep last night was above your weekly average — that\'s a great sign for recovery. Today is a good day to push a little harder if you feel ready.',
    'I notice you haven\'t logged activity in the past two days. Even gentle stretching counts! Listen to your body first.',
    'Your advisor has flagged this as a lower-intensity week. Focus on consistency over intensity right now.',
    'Great question! For your condition, low-impact aerobic activity like swimming or cycling tends to be well-tolerated. Always check with your care team before increasing intensity.',
    'Check-in tip: Try to log your activity within an hour of finishing — it helps build an accurate picture of your trends.',
  ];
  int _stubIndex = 0;

  /// Send [message] to the backend along with the full [history] of prior
  /// turns.  Returns the assistant's reply text.
  ///
  /// Expected request body:
  /// ```json
  /// {
  ///   "message": "user text",
  ///   "history": [{"role": "user"|"assistant", "content": "..."}]
  /// }
  /// ```
  /// Expected response body:
  /// ```json
  /// { "reply": "assistant text" }
  /// ```
  Future<String> sendMessage(
    String message, {
    List<ChatMessage> history = const [],
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.advisorChat}'),
            headers: _headers,
            body: json.encode({
              'message': message,
              'history': history.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(ApiConstants.receiveTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['reply'] as String;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Advisor request failed');
      }
    } catch (_) {
      // Fallback to stub while backend endpoint is not yet deployed.
      await Future.delayed(const Duration(milliseconds: 900));
      final reply = _stubReplies[_stubIndex % _stubReplies.length];
      _stubIndex++;
      return reply;
    }
  }
}
