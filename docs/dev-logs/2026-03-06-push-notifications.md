# Push Notification System — Med-Reminder
**Date:** 2026-03-06

## Decisions

- **No Firebase/FCM dependency (P0 is iOS only).** Used native APNs via HTTP/2 with `.p8` JWT auth. Android/FCM is deferred to P1.
- **No local notifications.** All scheduling is server-side (notification daemon). Flutter only handles permission + token upload.
- **MethodChannel for APNs token.** Avoids pulling in `firebase_messaging` or `flutter_local_notifications`. The Swift `AppDelegate` requests permission, registers for remote notifications, and returns the hex device token over `com.lumie.app/push`.
- **Daemon is standalone.** Separate Python process (`notification_daemon.py`) with its own systemd unit. Does not share the FastAPI process.
- **In-memory dedup cache.** Keyed by `{user_id}_{task_id}`, lost on restart (acceptable per PRD).
- **Device token stored on user record** via `$set` (last-write-wins upsert). No separate collection.

## New Files

### Backend
- `lumie_backend/notification_daemon.py` — standalone asyncio daemon (poll, phases, APNs send, dedup)
- `lumie_backend/lumie-notify.service` — systemd unit for the daemon

### Flutter
- `lumie_activity_app/lib/core/services/push_notification_service.dart` — MethodChannel bridge + token upload/delete

### iOS
- `lumie_activity_app/ios/Runner/Runner.entitlements` — APNs entitlement (`aps-environment = development`)

## Modified Files

### Backend
- `lumie_backend/app/api/auth_routes.py` — added `POST /auth/save-device-token` and `DELETE /auth/device-token`
- `lumie_backend/requirements.txt` — added `httpx[http2]`, `PyJWT` (already present, noted for daemon)

### Flutter
- `lumie_activity_app/lib/features/auth/providers/auth_provider.dart` — wired `PushNotificationService.init()` on auth, `deleteToken()` on logout

### iOS
- `lumie_activity_app/ios/Runner/AppDelegate.swift` — push permission, MethodChannel handler, token callbacks
- `lumie_activity_app/ios/Runner/Info.plist` — added `UIBackgroundModes: remote-notification`
- `lumie_activity_app/ios/Runner.xcodeproj/project.pbxproj` — `CODE_SIGN_ENTITLEMENTS` + file reference

## API Endpoints Added

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/auth/save-device-token` | Bearer | Upsert device push token |
| DELETE | `/api/v1/auth/device-token` | Bearer | Remove device token (logout) |

## New DB Fields

| Collection | Field | Type | Notes |
|---|---|---|---|
| `users` | `device_token` | string / null | APNs hex token, last-write-wins |

## Daemon Env Vars

| Var | Description |
|---|---|
| `APNS_KEY_PATH` | Path to Apple `.p8` key file |
| `APNS_KEY_ID` | Key ID from Apple developer portal |
| `APNS_TEAM_ID` | Apple team ID |
| `APNS_TOPIC` | Bundle identifier (`com.linxu.lumieActivityApp`) |
| `APNS_USE_SANDBOX` | `true` for dev, `false` for production |

## Testing Checklist

- [ ] iOS simulator: verify permission dialog appears on first launch
- [ ] Physical device: verify APNs token is received and uploaded
- [ ] Backend: `POST /auth/save-device-token` stores token in user doc
- [ ] Backend: `DELETE /auth/device-token` clears token
- [ ] Daemon: starts, connects to MongoDB, polls tasks
- [ ] Daemon: sends notification for active task (Early phase)
- [ ] Daemon: dedup prevents duplicate sends within interval
- [ ] Daemon: Middle and Late phases fire at correct progress thresholds
- [ ] Logout: server-side token is deleted

## iOS Entitlement — Temporarily Removed

Personal dev team ("LIN XU") doesn't support Push Notifications capability.
The entitlement and background mode were removed so the app can build.
The Dart + Swift code is still in place and will no-op gracefully.

**When you have a paid Apple Developer account, restore these 3 things:**

### 1. Create `ios/Runner/Runner.entitlements`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
</dict>
</plist>
```

### 2. Add to `ios/Runner/Info.plist` (before `UIApplicationSupportsIndirectInputEvents`)
```xml
<key>UIBackgroundModes</key>
<array>
	<string>remote-notification</string>
</array>
```

### 3. Add to all 3 Runner build configs in `project.pbxproj`
Add this line inside each `buildSettings` block (Debug, Release, Profile):
```
CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;
```

After restoring, also generate the `.p8` APNs key from Apple Developer portal and configure the daemon env vars (see "Daemon Env Vars" section above).

---

## Future Work / Deferred

- **P1: FCM/Android support** — add `firebase_messaging` dependency, send via Firebase Admin SDK
- **P1: In-app banner** when push permission is denied
- **P1: Deep-link routing** from notification `task_id` payload to task detail screen
- Production entitlement: change `aps-environment` from `development` to `production` before App Store release
