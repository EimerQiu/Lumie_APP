/// Chat History Service
///
/// Manages advisor chat history with two layers:
///   1. **Server** — source of truth (GET /advisor/history)
///   2. **Local cache** — SharedPreferences, survives tab switches
///      and app restarts (cleared on reinstall / logout)
///
/// On ChatTab init the service loads local cache instantly, then
/// fetches the latest from the server in the background.  New messages
/// are written to both layers simultaneously.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'auth_service.dart';

/// A persisted chat message.
class PersistedMessage {
  final String sessionId;
  final String role; // "user" | "assistant"
  final String content;
  final Map<String, dynamic> metadata;
  final String createdAt; // ISO UTC

  const PersistedMessage({
    required this.sessionId,
    required this.role,
    required this.content,
    this.metadata = const {},
    required this.createdAt,
  });

  factory PersistedMessage.fromJson(Map<String, dynamic> json) {
    return PersistedMessage(
      sessionId: json['session_id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'role': role,
        'content': content,
        'metadata': metadata,
        'created_at': createdAt,
      };

  bool get isUser => role == 'user';
}

class ChatHistoryService {
  static final ChatHistoryService _instance = ChatHistoryService._internal();
  factory ChatHistoryService() => _instance;
  ChatHistoryService._internal();

  final AuthService _auth = AuthService();

  static const _cacheKey = 'advisor_chat_history';
  static const int _maxCachedMessages = 500;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_auth.token}',
      };

  // ── Server fetch ─────────────────────────────────────────────────────────

  /// Fetch messages from the server (newest first).
  /// Returns them in **chronological** order (oldest first) for display.
  Future<List<PersistedMessage>> fetchFromServer({
    int limit = 200,
    String? before,
  }) async {
    try {
      var url = '${ApiConstants.baseUrl}${ApiConstants.advisorHistory}?limit=$limit';
      if (before != null) {
        url += '&before=${Uri.encodeComponent(before)}';
      }

      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(ApiConstants.receiveTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final msgs = (data['messages'] as List)
            .map((m) => PersistedMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        // API returns newest-first; reverse for chronological display
        return msgs.reversed.toList();
      }
    } catch (e) {
      print('ChatHistoryService.fetchFromServer error: $e');
    }
    return [];
  }

  // ── Local cache ──────────────────────────────────────────────────────────

  /// Load messages from local SharedPreferences cache.
  /// Returns in chronological order.
  Future<List<PersistedMessage>> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return [];

      final list = json.decode(raw) as List;
      return list
          .map((m) => PersistedMessage.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('ChatHistoryService.loadFromCache error: $e');
      return [];
    }
  }

  /// Save messages to local cache (full replace).
  Future<void> saveToCache(List<PersistedMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only the latest N messages to avoid bloating storage
      final trimmed = messages.length > _maxCachedMessages
          ? messages.sublist(messages.length - _maxCachedMessages)
          : messages;
      final raw = json.encode(trimmed.map((m) => m.toJson()).toList());
      await prefs.setString(_cacheKey, raw);
    } catch (e) {
      print('ChatHistoryService.saveToCache error: $e');
    }
  }

  /// Append new messages to the local cache (for real-time updates).
  Future<void> appendToCache(List<PersistedMessage> newMessages) async {
    final existing = await loadFromCache();
    existing.addAll(newMessages);
    await saveToCache(existing);
  }

  /// Clear local cache (call on logout).
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  // ── Combined load (cache-first, then server sync) ────────────────────────

  /// Load history: returns local cache immediately, then syncs from server.
  /// [onServerSync] is called when server data arrives (may update the list).
  Future<List<PersistedMessage>> loadHistory({
    void Function(List<PersistedMessage>)? onServerSync,
  }) async {
    // 1. Load local cache for instant display
    final cached = await loadFromCache();

    // 2. Fetch from server in background
    fetchFromServer(limit: 200).then((serverMessages) async {
      if (serverMessages.isNotEmpty) {
        await saveToCache(serverMessages);
        onServerSync?.call(serverMessages);
      }
    });

    return cached;
  }
}
