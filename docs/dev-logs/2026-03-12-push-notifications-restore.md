# Push Notifications Restoration — APNs Setup Complete
**Date:** 2026-03-12

## Summary

Restored the push notification system that was previously temporarily disabled due to lack of Apple Developer account. The notification daemon is now deployed and running on the production server with APNs credentials configured.

## Decisions

- **APNs Credentials Obtained:** Acquired personal Apple Developer account with APNs capability
- **Daemon Already in Codebase:** The `notification_daemon.py` and `lumie-notify.service` were already implemented from 2026-03-06; only needed to deploy and configure
- **Environment Variables via .env:** Configured APNs credentials in the backend `.env` file (read by systemd service)
- **Sandbox Mode Enabled:** Set `APNS_USE_SANDBOX=true` for development; will change to `false` for production release
- **No Code Changes Required:** iOS entitlements, Info.plist, and project.pbxproj were already fully configured

## Changes Made

### Backend (Server)
- ✅ Uploaded APNs key: `AuthKey_9YS58RKP86.p8` → `/home/ubuntu/lumie_backend/`
- ✅ Deployed notification daemon service to systemd: `/etc/systemd/system/lumie-notify.service`
- ✅ Added environment variables to `.env`:
  ```
  APNS_KEY_PATH=/home/ubuntu/lumie_backend/AuthKey_9YS58RKP86.p8
  APNS_KEY_ID=9YS58RKP86
  APNS_TEAM_ID=G756UPT65U
  APNS_TOPIC=org.yumo.lumie
  APNS_USE_SANDBOX=true
  ```
- ✅ Enabled daemon: `sudo systemctl enable lumie-notify`
- ✅ Started daemon: `sudo systemctl start lumie-notify`

### iOS (No Changes Needed)
The following were already in place from the 2026-03-06 implementation:
- `ios/Runner/Runner.entitlements` — APNs entitlement configured
- `ios/Runner/Info.plist` — `UIBackgroundModes: remote-notification` already present
- `ios/Runner.xcodeproj/project.pbxproj` — `CODE_SIGN_ENTITLEMENTS` set in all build configs (Debug, Release, Profile)
- `ios/Runner/AppDelegate.swift` — Push permission + MethodChannel handler
- `lib/core/services/push_notification_service.dart` — Token upload/delete logic

## Server Configuration

### Notification Daemon Status
```
● lumie-notify.service - Lumie Notification Daemon
   Loaded: loaded (/etc/systemd/system/lumie-notify.service; enabled)
   Active: active (running) since Thu 2026-03-12 01:55:22 UTC
   Main PID: 56311 (python)
   Memory: 33.8M
```

### Environment Variables
| Variable | Value | Purpose |
|----------|-------|---------|
| `APNS_KEY_PATH` | `/home/ubuntu/lumie_backend/AuthKey_9YS58RKP86.p8` | Path to APNs signing key |
| `APNS_KEY_ID` | `9YS58RKP86` | Apple-issued key identifier |
| `APNS_TEAM_ID` | `G756UPT65U` | Apple Developer Team ID |
| `APNS_TOPIC` | `org.yumo.lumie` | iOS bundle identifier (matches entitlement) |
| `APNS_USE_SANDBOX` | `true` | Development sandbox; change to `false` for production |

## How It Works (Refresh)

1. **App Requests Permission** — On first launch, iOS shows system dialog
2. **Device Token Uploaded** — Flutter calls `POST /api/v1/auth/save-device-token` with APNs token
3. **Daemon Polls Tasks** — Every 60 seconds, `notification_daemon.py` checks for active tasks
4. **Task Phases Checked** — For each task, evaluates progress against Early/Middle/Late phases
5. **APNs Notification Sent** — If phase threshold reached, sends HTTP/2 request to Apple APNs
6. **Dedup Cache** — In-memory dedup prevents duplicate sends within the same polling interval
7. **Device Token Cleared** — On logout, `DELETE /api/v1/auth/device-token` removes token from server

## Testing Checklist

- [x] Daemon starts without errors
- [x] Daemon connects to MongoDB
- [x] Daemon polls tasks every 60 seconds
- [ ] iOS device: Request permission dialog appears on first launch
- [ ] iOS device: APNs token is received and uploaded via `POST /auth/save-device-token`
- [ ] Backend: Token is stored in `users.device_token` field
- [ ] Backend: `DELETE /auth/device-token` clears token on logout
- [ ] Daemon: Sends notification when task enters Early phase
- [ ] Daemon: Respects dedup cache (no duplicate notifications)
- [ ] Daemon: Middle and Late phase notifications fire at correct progress thresholds
- [ ] End-to-end: Receive push notification on physical iOS device

## Production Checklist

Before App Store release:

1. **Change APNS_USE_SANDBOX:**
   ```bash
   # On server, edit .env
   APNS_USE_SANDBOX=false
   systemctl restart lumie-notify
   ```

2. **Update iOS Entitlement:**
   In `ios/Runner/Runner.entitlements`, change:
   ```xml
   <string>development</string>
   ```
   to:
   ```xml
   <string>production</string>
   ```

3. **Update APNs Key (Optional):**
   Apple may issue a production key; if so, upload and update:
   ```
   APNS_KEY_PATH=/home/ubuntu/lumie_backend/AuthKey_PROD.p8
   ```

4. **Test on App Store TestFlight** — Verify notifications work with production APNs

## Files Reference

- Backend daemon: `lumie_backend/notification_daemon.py`
- Systemd service: `lumie_backend/lumie-notify.service`
- Flutter service: `lumie_activity_app/lib/core/services/push_notification_service.dart`
- Auth routes: `lumie_backend/app/api/auth_routes.py` (has `/auth/save-device-token` and `/auth/device-token`)

## API Endpoints (Already Implemented)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/v1/auth/save-device-token` | Bearer | Upsert device push token |
| DELETE | `/api/v1/auth/device-token` | Bearer | Remove device token (logout) |

## Future Work / Deferred

- **P1: Production Entitlement** — Switch to production APNs before App Store release
- **P1: Deep-link Routing** — From push notification payload, route to task detail screen
- **P2: FCM/Android Support** — Add Firebase Cloud Messaging for Android devices (P1 is iOS only)
- **P2: In-app Banner** — Show permission denial warning if user denies notifications
- **P2: Rich Notifications** — Add custom notification UI with task details and actions
- **P3: Notification Preferences** — Let users customize notification timing (Early/Middle/Late phases)

## Deployment Steps Taken

```bash
# 1. Uploaded APNs key
scp -i ~/.ssh/Lumie_Key.pem AuthKey_9YS58RKP86.p8 ubuntu@54.177.85.124:/home/ubuntu/lumie_backend/

# 2. Deployed service file
ssh ubuntu@54.177.85.124 "sudo cp lumie-notify.service /etc/systemd/system/ && sudo systemctl daemon-reload"

# 3. Added environment variables to .env
ssh ubuntu@54.177.85.124 "cat >> .env << 'EOF'
APNS_KEY_PATH=/home/ubuntu/lumie_backend/AuthKey_9YS58RKP86.p8
APNS_KEY_ID=9YS58RKP86
APNS_TEAM_ID=G756UPT65U
APNS_TOPIC=org.yumo.lumie
APNS_USE_SANDBOX=true
EOF"

# 4. Started and enabled daemon
ssh ubuntu@54.177.85.124 "sudo systemctl start lumie-notify && sudo systemctl enable lumie-notify"

# 5. Verified status
ssh ubuntu@54.177.85.124 "sudo systemctl status lumie-notify"
```

---

## Notes for Future Developers

- The daemon runs as a separate Python process, not within FastAPI
- All task polling and notification logic is in `notification_daemon.py`
- Device tokens are stored on the `users` collection, not a separate table
- APNs JWT tokens are automatically generated per-request using the `.p8` key
- For local development, you can run `notification_daemon.py` directly without systemd
- To test without real APNs, modify the daemon to log instead of sending (or mock the httpx client)
