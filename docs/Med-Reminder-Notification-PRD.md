# Med-Reminder: Push Notification System
**Product Requirements Document — Lumie Ring**

---

## 1. Architecture

Notifications are sent by a standalone server-side daemon. The Flutter client handles permission and token upload only — it must not schedule any local notifications for Med-Reminder tasks.

| Component | Responsibility | Stack |
|---|---|---|
| Notification Daemon | Poll MongoDB; send push via APNs/FCM | Python asyncio + apns2 |
| API Server | Store device push token per user | FastAPI + MongoDB |
| Flutter Client | Request permission; upload token on launch | Flutter push APIs |

---

## 2. Device Token

### Client (on every launch)
- Request push permission (first launch only; skip if already granted).
- Retrieve device token from OS (APNs on iOS, FCM on Android).
- POST to server immediately.
- If denied: show in-app banner linking to device Settings.

### API
```
POST /save-device-token
Auth: Bearer <user_token>
Body: { "device_token": "<token>" }

Behaviour: upsert token to user record in chat_db.users (last-write-wins).
```

---

## 3. Daemon

### Poll cycle
- Runs every **60 seconds**.
- Queries `task_collection` for all tasks where **`done` field does not exist** (not yet completed).
- Computes progress ratio for each task:

```python
duration = close_datetime - open_datetime   # seconds
progress = (now_utc - open_datetime) / duration
```

- Skips task if **`progress < 0`** (window not yet open) or **`progress > 1`** (expired). Only `0 ≤ progress ≤ 1` is eligible.

### Deduplication
In-memory cache keyed by `"{user_id}_{task_id}"`. A notification is sent only if time elapsed since the last send for this key exceeds the phase interval. Cache is lost on restart — tasks active at restart will re-notify on the next cycle (acceptable).

---

## 4. Notification Phases

| Phase | Progress | Interval | Title |
|---|---|---|---|
| Early | 0 – 10% | `duration × 5%` | `"{name} Started"` |
| Middle | 10 – 90% | `duration × 10%` | `"{name} Progress"` |
| Late | 90 – 100% | `duration × 2.5% − 60 s` ¹ | `"{name} Ending Soon"` |

¹ If this value is ≤ 0 (very short windows), interval defaults to one poll cycle (60 s).

---

## 5. Notification Content

| Field | Value |
|---|---|
| `title` | Phase-dependent (see Section 4) |
| `body` | `task_info` (single task) or `rpttask_info` (template task). Fallback: `"No specific information provided"`. |
| `sound` | `"default"` |
| `data.task_id` | MongoDB `_id` of the task — used for client deep-link routing |

**For template tasks:** look up `repeat_task_collection` by `rpttask_id`. Task name → `rpttask_list[small_task_id].name`; body → `rpttask.rpttask_info`.

---

## 6. Min-Interval Interaction

> ⚠️ No special handling required. If `open_datetime` is pushed forward by the min-interval rule, `progress` will be negative until the new time arrives and the daemon will skip the task automatically. No cancellation or rescheduling step is needed.

---

## 7. Requirements

| Pri | Owner | Requirement |
|---|---|---|
| P0 | Backend | Deploy notification daemon; poll every 60 s |
| P0 | Backend | Implement three-phase frequency model (Section 4) |
| P0 | Backend | Send via APNs (iOS) with `.p8` JWT credentials |
| P0 | Backend | In-memory deduplication cache per user + task |
| P0 | Backend | Resolve `task_info` / `rpttask_info` as body (Section 5) |
| P0 | Backend | `POST /save-device-token`: upsert token to user record |
| P0 | Flutter | Request permission and upload push token on every launch |
| P0 | Flutter | Remove all `flutter_local_notifications` scheduling for Med-Reminder |
| P1 | Backend | Send via FCM (Android) |
| P1 | Flutter | Show in-app banner when permission is denied |
| P1 | Flutter | Delete server-side token on logout |
