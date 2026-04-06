# Proactive Nudge Flow — User Opens Advisor After Notification

## Overview

When a proactive nudge is sent to the user via APNs, and the user taps the notification, the Advisor screen now intelligently opens the **most recent chat session** by default. No polling required.

---

## Complete Flow

```
Timeline:
═══════════════════════════════════════════════════════════════════════

3:17:00 PM  ← Proactive service runs (backend scheduled task)
  │
  ├─→ Executes 7 proactive-eligible skills in parallel
  │   (energy_status_query, health_data_query, tasks_query, etc.)
  │
  ├─→ Passes results to LLM decision model
  │
  ├─→ LLM decides: "should_nudge=true, message='...'"
  │
  └─→ Saves message to MongoDB:
      {
        user_id: "bc5e5a99-...",
        session_id: "proactive",
        role: "assistant",
        content: "Want a quick guide on healthy daily step targets?",
        metadata: { type: "proactive", reason: "...", ... },
        created_at: "2026-04-06T03:17:00..."
      }

3:17:01 PM  ← queue_checkin_notification(user_id, message)
  │
  └─→ APNs notification sent to device:
      Title: "Lumie Advisor"
      Body: "Want a quick guide on healthy daily step targets?"
      Payload: { navigate_to: "advisor", type: "advisor_checkin" }

3:17:03 PM  ← APNs arrives at user's device
  │
  └─→ Notification banner shown: "Lumie Advisor: Want a quick guide..."

3:17:07 PM  ← User taps notification
  │
  └─→ iOS native handler invokes method channel:
      MethodChannel('com.lumie.app/push').onMethodCall('onNotificationTap', {
        navigate_to: "advisor",
        type: "advisor_checkin"
      })

3:17:08 PM  ← main.dart receives notification tap
  │
  └─→ _handlePushPayload(data) called:
      └─→ if (navigateTo == 'advisor') {
            setState(() => _currentIndex = 1);
          }
      └─→ Switches to Advisor tab (index 1)

3:17:09 PM  ← AdvisorScreen widget builds
  │
  ├─→ _ChatTabState.initState() called
  │
  ├─→ _initSession() runs (NO POLLING)
  │
  │   1. Fetch proactive messages (session_id="proactive")
  │      └─ [{ content: "Want a quick guide...", createdAt: "2026-04-06T03:17:00..." }]
  │
  │   2. Fetch saved user session messages (session_id=$SAVED_SESSION_ID)
  │      └─ [{ content: "Turn on the AC", createdAt: "2026-04-05T15:22:00..." }]
  │
  │   3. Compare timestamps:
  │      lastProactiveTime = 2026-04-06T03:17:00
  │      lastSavedTime     = 2026-04-05T15:22:00
  │      └─ lastProactiveTime is more recent! ✅
  │
  │   4. Set _sessionId = 'proactive'
  │
  │   5. Load all proactive messages and mark isProactive=true
  │
  ├─→ setState() triggers rebuild
  │
  └─→ _scrollToBottom() scrolls to latest message

3:17:10 PM  ← Chat screen displayed to user
  │
  └─→ Message visible:
      ┌───────────────────────────────────────┐
      │ Proactive check-in                    │  ← Label (line 902)
      │ [✦] Want a quick guide on healthy     │  ← Yellow badge
      │     daily step targets and signs      │
      │     you may be overdoing it?          │
      │                                       │
      │ Today at 3:17 PM                      │  ← Timestamp
      └───────────────────────────────────────┘
```

---

## Code Changes

### Removed

**File:** `lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart`

```dart
// ❌ REMOVED: 10-second polling timer
Timer? _refreshTimer;
static const _proactiveRefreshIntervalSeconds = 10;

void _startProactiveRefreshTimer() {
  _refreshTimer = Timer.periodic(
    const Duration(seconds: _proactiveRefreshIntervalSeconds),
    (_) => _loadProactiveMessages(),
  );
}

Future<void> _loadProactiveMessages() async {
  // Poll every 10 seconds for new proactive messages
  final proactiveMessages = await _historyService.fetchSessionMessages('proactive');
  // ... add to chat view
}
```

### Added

**File:** `lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart`

```dart
Future<void> _initSession() async {
  final prefs = await SharedPreferences.getInstance();

  // Check for proactive messages first
  final proactiveMessages = await _historyService.fetchSessionMessages('proactive');
  final lastProactiveTime = proactiveMessages.isNotEmpty
      ? DateTime.tryParse(proactiveMessages.last.createdAt)
      : null;

  // Check saved session
  final savedId = prefs.getString(_sessionIdKey);
  final savedMessages = savedId != null
      ? await _historyService.fetchSessionMessages(savedId)
      : <dynamic>[];
  final lastSavedTime = savedMessages.isNotEmpty
      ? DateTime.tryParse(savedMessages.last.createdAt)
      : null;

  // Determine which session to display:
  // If proactive messages exist and are more recent, show proactive session
  if (lastProactiveTime != null &&
      (lastSavedTime == null || lastProactiveTime.isAfter(lastSavedTime))) {
    _sessionId = 'proactive';
  } else if (savedId != null) {
    _sessionId = savedId;
  } else {
    // No saved session — start fresh
    _sessionId = const Uuid().v4();
    await _saveActiveSession();
    if (mounted) setState(() => _isLoading = false);
    return;
  }

  // Load selected session
  final messagesToDisplay = (_sessionId == 'proactive')
      ? proactiveMessages
      : savedMessages;

  if (mounted && messagesToDisplay.isNotEmpty) {
    setState(() {
      _items.clear();
      for (final m in messagesToDisplay) {
        _items.add(
          _ChatItem.message(
            _Message(
              text: m.content,
              isUser: m.isUser,
              isProactive: _sessionId == 'proactive',  // ← Mark proactive messages
              createdAt: m.createdAt,
            ),
          ),
        );
      }
      _isLoading = false;
    });
    _scrollToBottom();
  } else {
    if (mounted) setState(() => _isLoading = false);
  }

  // Update saved session to current one
  if (_sessionId != 'proactive') {
    await _saveActiveSession();
  }
}
```

---

## Session Selection Logic

### Decision Tree

```
START: _initSession()
  │
  ├─ Fetch proactive messages (session_id="proactive")
  │  └─ Extract: createdAt of last message
  │
  ├─ Fetch saved user messages (session_id=prefs.getString(_sessionIdKey))
  │  └─ Extract: createdAt of last message
  │
  └─ DECISION TREE:
     │
     ├─ IF proactive messages exist AND more recent than saved:
     │  └─ _sessionId = "proactive"
     │     └─ Mark all loaded messages: isProactive=true
     │
     ├─ ELSE IF saved session exists:
     │  └─ _sessionId = savedId
     │     └─ Mark all loaded messages: isProactive=false
     │
     └─ ELSE (no messages anywhere):
        └─ _sessionId = UUID() (new session)
           └─ No messages to display
```

### Example Scenarios

**Scenario 1: Just Received Proactive Nudge**
```
Proactive messages: [message at 3:17 PM]  ← Most recent
Saved session:      [message at 3:10 PM]

→ Opens: proactive session
→ User sees: Proactive check-in label
```

**Scenario 2: User Had Recent Conversation**
```
Proactive messages: [message at 3:17 PM]
Saved session:      [message at 3:18 PM]  ← More recent!

→ Opens: saved session
→ User sees: Regular conversation (no label)
→ Can switch to proactive via "History" button
```

**Scenario 3: App First Launch, Fresh Session**
```
Proactive messages: []  (empty)
Saved session:      []  (empty)

→ Creates: new empty session (UUID)
→ User sees: Empty chat ready for input
```

**Scenario 4: No Saved Session, Only Proactive**
```
Proactive messages: [message at 3:17 PM]
Saved session:      (none saved yet)

→ Opens: proactive session
→ _sessionId = "proactive"
→ Won't save back to SharedPreferences (line 222: only if != 'proactive')
```

---

## Message Display

Messages are marked with `isProactive=true` when loaded from `session_id="proactive"`.

In the `_ChatBubble` widget (line 902-915):

```dart
if (message.isProactive) ...[
  Padding(
    padding: const EdgeInsets.only(left: 36, bottom: 6),
    child: Text(
      'Proactive check-in',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary.withValues(alpha: 0.85),
        letterSpacing: 0.2,
      ),
    ),
  ),
],
```

---

## Performance Benefits

| Aspect | Before | After |
|--------|--------|-------|
| **Polling** | Every 10 sec (6 calls/min/user) | None |
| **Battery** | Continuous timer drain | No timer |
| **API Calls** | 360 calls/hour/user | 2 calls (initial load) |
| **Latency** | Up to 10 sec to see message | Immediate on app open |
| **UX** | Message might not appear after tap | Always appears on tap |

---

## Edge Cases

### 1. Proactive message saved while app in background

**Before:** Would miss it until next polling cycle (up to 10 sec)
**After:** Opens proactive session immediately when user opens app ✅

### 2. User has multiple conversations in same session

**Before:** Only latest proactive message was displayed
**After:** All messages in `proactive` session are loaded (as they always were)

### 3. Two proactive messages in same run

```json
{
  "session_id": "proactive",
  "created_at": "2026-04-06T03:17:00"
},
{
  "session_id": "proactive",
  "created_at": "2026-04-06T03:17:05"
}
```

→ Both loaded, sorted by `created_at` ascending
→ User sees both in order

---

## Testing Checklist

- [ ] User receives proactive nudge → APNs notification appears
- [ ] User taps notification → Advisor tab opens
- [ ] Proactive session loaded by default with "Proactive check-in" label
- [ ] Message visible immediately (no polling delay)
- [ ] User can tap "History" to view previous sessions
- [ ] Switching back to Advisor remembers which session was open
- [ ] No console errors or warnings
- [ ] Confirm no 10-second timer in console (use `Timer.isRunning` if you add it back)

---

## References

- **Code**: Commit 7ec51c9
- **Issue**: 10-second polling inefficient, messages should appear immediately on tap
- **Related**: [PROACTIVE_MESSAGES_WORKFLOW.md](SHARED_CREDENTIAL_WORKFLOW.md) (where proactive messages are saved)
