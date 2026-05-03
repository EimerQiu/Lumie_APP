/// Advisor Notification Service — polls for new advisor messages in foreground.
library advisor_notification_service;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'chat_history_service.dart';

class AdvisorNotificationService {
  static final AdvisorNotificationService _instance = AdvisorNotificationService._internal();
  factory AdvisorNotificationService() => _instance;
  AdvisorNotificationService._internal();

  final ChatHistoryService _historyService = ChatHistoryService();

  /// Sessions with new messages. Drives the badge count in the AppBar.
  final ValueNotifier<List<SessionSummary>> unreadSessions = ValueNotifier([]);

  /// Stream of sessions that have new messages. Fired when a notification arrives.
  /// Not fired on navigation requests (requestNavigateTo uses a separate flow).
  final StreamController<SessionSummary> _incomingStream = StreamController.broadcast();
  Stream<SessionSummary> get incoming => _incomingStream.stream;

  /// Stream of navigation requests. Fired when user taps a session to view it.
  final StreamController<SessionSummary> _navStream = StreamController.broadcast();
  Stream<SessionSummary> get navigationRequests => _navStream.stream;

  /// Tracks the last known lastMessageAt per session.
  /// Used to detect new messages on subsequent polls.
  Map<String, String> _knownLastMessageAt = {};

  /// On the first poll, we seed the baseline and don't notify.
  /// Subsequent polls compare against this baseline.
  bool _initialized = false;

  /// Session currently being viewed. Notifications for this session are suppressed.
  String? _activeSessionId;

  /// Poll interval timer.
  Timer? _timer;

  /// Is the service currently polling?
  bool _isRunning = false;

  /// Start polling sessions every 15 seconds.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _poll(); // Immediate first poll
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  /// Stop polling and clear state.
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Called when user navigates to a session (to suppress notifications for that session).
  void setActiveSession(String? sessionId) {
    _activeSessionId = sessionId;
  }

  /// Mark a session as read (remove from unread list).
  void markSessionRead(String sessionId) {
    final current = unreadSessions.value;
    final updated = current.where((s) => s.sessionId != sessionId).toList();
    if (updated.length < current.length) {
      unreadSessions.value = updated;
    }
  }

  /// Clear all unread sessions.
  void markAllRead() {
    unreadSessions.value = [];
  }

  /// User tapped a session in the banner or unread panel. Fire navigation stream.
  void requestNavigateTo(SessionSummary session) {
    markSessionRead(session.sessionId);
    _navStream.add(session);
  }

  /// Poll the server for session updates.
  Future<void> _poll() async {
    if (!_isRunning) return;
    try {
      final sessions = await _historyService.fetchSessions(limit: 50);

      // First poll: seed the baseline
      if (!_initialized) {
        _knownLastMessageAt = {
          for (final s in sessions) s.sessionId: s.lastMessageAt
        };
        _initialized = true;
        return;
      }

      // Detect new messages
      final newUnread = <SessionSummary>[];
      for (final session in sessions) {
        // Skip the currently active session
        if (session.sessionId == _activeSessionId) continue;

        final lastKnown = _knownLastMessageAt[session.sessionId] ?? '';
        final isNew = session.lastMessageAt.compareTo(lastKnown) > 0;

        if (isNew) {
          // Mark as unread and fire the incoming stream
          newUnread.add(session);
          _incomingStream.add(session);
        }

        // Always update the baseline
        _knownLastMessageAt[session.sessionId] = session.lastMessageAt;
      }

      // Update the unread list (merge new ones)
      if (newUnread.isNotEmpty) {
        final current = unreadSessions.value;
        final merged = <SessionSummary>[];
        final sessionIds = {for (final s in newUnread) s.sessionId};

        // Keep existing unread sessions that aren't in the new update
        for (final existing in current) {
          if (!sessionIds.contains(existing.sessionId)) {
            merged.add(existing);
          }
        }
        // Add the new ones
        merged.addAll(newUnread);

        unreadSessions.value = merged;
      }
    } catch (e) {
      debugPrint('AdvisorNotificationService._poll error: $e');
    }
  }
}
