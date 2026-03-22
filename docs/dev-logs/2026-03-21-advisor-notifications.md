# 2026-03-21 — Advisor Push Notifications

## Overview

Added push notification support for three advisor-related scenarios:
1. **Important Insight Alerts** — when the advisor detects a health concern (symptom, emotional distress, medication issue), team admins (parents) are notified
2. **Analysis Complete** — when an async data analysis job finishes, the user receives a push so they can return to see results
3. **Proactive Check-in Nudges** — scheduled daily/weekday check-in reminders that nudge the user to chat with the advisor

Also fixed a **session-merging bug** in the dayprint service where conversations from separate chat sessions could be incorrectly collapsed into a single entry.

## Decisions Made

### Session-aware dayprint entries
- **Problem**: Two separate conversations (e.g., grief + high resting HR) could merge into one dayprint entry because the `replace_last` logic had no concept of sessions.
- **Solution**: Frontend generates a UUID `session_id` per chat tab lifecycle. Backend stores it on each event and only allows `replace_last` within the same session. A hard guard ensures new sessions never merge regardless of LLM output.

### Notification queue architecture
- **Decision**: Notifications are queued in a `notification_queue` MongoDB collection and drained by the existing `notification_daemon.py` instead of sending APNs inline from the API.
- **Rationale**: Keeps API response fast, centralises HTTP/2 client lifecycle in one process, and naturally retries on daemon restart.

### Important insight recipients
- **Decision**: Notifications go to team admins (parents), not the user who raised the concern.
- **Rationale**: The teen already knows about their concern. The value is alerting their care team.
- **Fallback**: If the user has no team or no admins, the notification goes to the user themselves.

### Check-in scheduling
- **Decision**: Uses a lightweight `advisor_checkins` collection polled by the daemon, not a cron job.
- **Rationale**: Already have the daemon polling infrastructure. One less moving part.

## New Files Created

### Backend
- `lumie_backend/app/core/apns.py` — shared APNs JWT helper (extracted from daemon)
- `lumie_backend/app/services/notification_service.py` — queue helpers for all 3 notification types
- `lumie_backend/app/api/checkin_routes.py` — GET/PATCH `/api/v1/advisor/checkin/preferences`

### Frontend
- `lumie_activity_app/lib/core/services/checkin_service.dart` — API client for check-in preferences

## Modified Files

### Backend
- `lumie_backend/app/services/dayprint_service.py` — session_id tracking, notification trigger on new important_insight
- `lumie_backend/app/services/analysis_service.py` — queue notification on job success
- `lumie_backend/app/api/advisor_routes.py` — accept and forward `session_id`
- `lumie_backend/app/main.py` — register `checkin_router`
- `lumie_backend/notification_daemon.py` — added `process_notification_queue()` and `process_advisor_checkins()` to main loop

### Frontend
- `lumie_activity_app/pubspec.yaml` — added `uuid` dependency
- `lumie_activity_app/lib/core/services/advisor_service.dart` — send `session_id` in request
- `lumie_activity_app/lib/core/services/push_notification_service.dart` — added notification tap handler via MethodChannel
- `lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart` — generate `_sessionId` per chat session
- `lumie_activity_app/ios/Runner/AppDelegate.swift` — added `UNUserNotificationCenterDelegate` for tap handling + foreground display
- `lumie_activity_app/lib/main.dart` — wire notification tap to navigate to Advisor tab

## API Endpoints Added

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/advisor/checkin/preferences` | Get check-in notification preferences |
| PATCH | `/api/v1/advisor/checkin/preferences` | Update check-in preferences (partial) |

## New DB Collections

| Collection | Purpose |
|---|---|
| `notification_queue` | Queued push notifications (pending/sent/failed) |
| `advisor_checkins` | Per-user check-in schedule and last-sent date |

## Testing Checklist

- [ ] Two separate advisor conversations produce two distinct dayprint entries (not merged)
- [ ] Two separate important_insights from different sessions both appear in dayprint
- [ ] Important insight triggers push notification to team admin
- [ ] Analysis job completion triggers push notification to user
- [ ] Tapping advisor notification deep-links to Advisor tab
- [ ] Check-in preferences GET returns defaults when no doc exists
- [ ] Check-in preferences PATCH creates/updates correctly
- [ ] Daemon processes notification_queue and marks items as sent
- [ ] Daemon sends check-in at configured time, only once per day
- [ ] Foreground notifications display as banner on iOS

## Future Work

- Android (FCM) push notification support
- Check-in preferences UI in Settings screen (currently API-only)
- Notification history screen in the app
- Rate limiting on important_insight notifications (max N per day per admin)
- Rich notification UI with action buttons (e.g., "View Dayprint")
- Customisable check-in messages per user
