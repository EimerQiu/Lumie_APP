# Push Notification Testing Summary

**Status:** Ready to Test ✅
**Date:** 2026-03-12
**Test Environment:** iOS (Physical Device)

---

## System Readiness Checklist

- [x] **Backend:** Notification daemon deployed and running on production server
- [x] **iOS Configuration:** Entitlements, Info.plist, and code signing configured
- [x] **Flutter Code:** Push notification service integrated and wired to auth
- [x] **iOS Native Code:** AppDelegate.swift properly handles push permission + token upload
- [x] **Build:** Flutter app builds without errors
- [x] **Database:** MongoDB connected, ready for task creation

---

## What You'll Test

### 1. **App Build & Run**
   - Build the Flutter app for iOS
   - Run on physical device
   - Verify no crashes on startup

### 2. **Permission Dialog**
   - First login should trigger iOS notification permission dialog
   - User grants permission
   - System registers for remote notifications

### 3. **Token Upload**
   - App receives APNs device token from iOS
   - Token is uploaded to backend via `POST /api/v1/auth/save-device-token`
   - Token is stored in MongoDB `users` collection

### 4. **Task Creation**
   - Create a test task in Med-Reminder admin dashboard
   - Set up phases: Early (0%), Middle (50%), Late (80%)
   - Set start time for immediate or near-future

### 5. **Notification Delivery**
   - Daemon polls task progress every 60 seconds
   - When task enters Early phase, notification sent via APNs
   - Device receives notification with alert sound and badge
   - No duplicate notifications within same polling cycle

### 6. **Phase Transitions**
   - Advance task progress to 50% → Middle phase notification
   - Advance task progress to 80% → Late phase notification
   - Each phase transition triggers a new notification

### 7. **Logout & Cleanup**
   - Logout from app
   - Device token deleted from server
   - Device stops receiving notifications for that user

---

## Quick Start Testing (30 minutes)

### Step 1: Build & Run (5 min)
```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_activity_app

# Clean and build
flutter clean && flutter pub get

# Run on device (replace with your device ID)
flutter run -d <device_id>
```

### Step 2: Login & Grant Permission (3 min)
1. Open app
2. Login with test account
3. See permission dialog → tap **Allow**
4. Check `flutter logs` for "Token uploaded successfully"

### Step 3: Verify Token on Server (2 min)
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
mongosh lumie_db
db.users.findOne({email: "your_email@example.com"}).device_token
# Should see 128-char hex string
```

### Step 4: Create Test Task (5 min)
1. In app: **Med-Reminder** → **☑️ (All Tasks)**
2. **Create New Task**:
   - Name: "Test Notification"
   - Time: Next 1 hour (e.g., 3pm-4pm)
   - Early Phase: 0%
   - Middle Phase: 50%
   - Late Phase: 80%
3. Save

### Step 5: Monitor & Trigger (10 min)
**Terminal 1:** Monitor daemon
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
sudo journalctl -u lumie-notify -f
```

**Terminal 2:** Trigger Early phase (when task time starts)
```bash
# Wait for task time window to begin...
# Daemon will automatically detect and send notification within 60 seconds
```

**On Device:**
- Look for push notification at top of screen
- Should show task name and phase info
- Should have sound and badge

---

## Expected Results

### ✅ Success Indicators

**App Launch:**
```
✓ App builds without errors
✓ App runs on device without crashing
✓ No entitlement errors in logs
```

**Permission & Token:**
```
✓ iOS permission dialog appears
✓ User can tap "Allow"
✓ Settings show "Lumie Notifications" enabled
✓ Device token appears in MongoDB
```

**Notification Delivery:**
```
✓ Daemon logs show "Task in EARLY phase"
✓ Daemon logs show "APNs response: 200 (sent successfully)"
✓ Device receives notification with sound/badge
✓ Notification can be tapped to open app
```

**Phase Transitions:**
```
✓ Progress 0% → Early notification
✓ Progress 50% → Middle notification
✓ Progress 80% → Late notification
✓ No duplicates within 60-second polling window
```

**Cleanup:**
```
✓ Logout → device token deleted from DB
✓ Next notification attempt fails (token is null)
```

---

## Testing Documents

- **Full Testing Guide:** [docs/NOTIFICATION_TESTING.md](docs/NOTIFICATION_TESTING.md)
  - Detailed step-by-step instructions
  - Troubleshooting for common issues
  - Advanced tests (progress tracking, dedup validation)

- **Deployment Guide:** [docs/NOTIFICATION_DEPLOYMENT.md](docs/NOTIFICATION_DEPLOYMENT.md)
  - How to set up on new server
  - Production configuration
  - Monitoring and maintenance

- **Dev Log:** [docs/dev-logs/2026-03-12-push-notifications-restore.md](docs/dev-logs/2026-03-12-push-notifications-restore.md)
  - Technical implementation details
  - Architecture decisions
  - What was changed from original 2026-03-06 implementation

---

## Files Changed/Created

### iOS
- `ios/Runner/Runner.entitlements` — APNs capability (already configured)
- `ios/Runner/Info.plist` — `UIBackgroundModes: remote-notification` (already in place)
- `ios/Runner/AppDelegate.swift` — Push permission + token upload (already implemented)
- `ios/Runner.xcodeproj/project.pbxproj` — Code signing (already configured)

### Flutter
- `lib/core/services/push_notification_service.dart` — Handles token request & upload (already implemented)
- `lib/features/auth/providers/auth_provider.dart` — Initializes push service on login (already wired)

### Backend (Already Deployed)
- `notification_daemon.py` — Main polling loop and APNs sender
- `lumie-notify.service` — Systemd service unit
- `.env` — APNs credentials (configured on server)

### Documentation
- `docs/NOTIFICATION_TESTING.md` — Testing procedures (new)
- `docs/NOTIFICATION_DEPLOYMENT.md` — Deployment guide (new)
- `docs/dev-logs/2026-03-12-push-notifications-restore.md` — Dev log (new)

---

## Troubleshooting Quick Links

| Issue | Solution |
|-------|----------|
| App crashes on launch | Check entitlements are correct in Xcode project |
| Permission dialog doesn't appear | Ensure `lib/features/auth/providers/auth_provider.dart:44` calls `_pushService.init(token)` |
| Device token is null | Permission was denied; delete app, rebuild, and allow permission |
| Daemon not polling | Check `sudo systemctl status lumie-notify` is running |
| No notification received | Check device token in MongoDB is not null |
| Notification received but no sound | Check iOS Settings → Notifications → Sound is ON |

**Full troubleshooting:** See [docs/NOTIFICATION_TESTING.md](docs/NOTIFICATION_TESTING.md) "Troubleshooting" section.

---

## After Successful Testing

1. ✅ **Document results** — Take screenshots, note timestamps
2. 📝 **Update this file** with your test results
3. 🚀 **Prepare for production**:
   - Change `APNS_USE_SANDBOX=false` in server `.env`
   - Change iOS entitlement from `development` to `production`
   - Rebuild app for App Store
4. 📊 **Monitor** — Set up alerting for daemon errors
5. 👥 **User testing** — Have actual users test on their devices

---

## Key Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/v1/auth/save-device-token` | Upload device token |
| DELETE | `/api/v1/auth/device-token` | Delete token (logout) |

## Key Database Collections

| Collection | Fields | Purpose |
|-----------|--------|---------|
| `users` | `device_token` | Store APNs device token |
| `tasks` | `progress_percentage`, `status`, `phases` | Task data for daemon polling |

---

## Need Help?

- **App won't build?** Check `docs/NOTIFICATION_TESTING.md` → "Troubleshooting" → "App Crashes on Launch"
- **Not receiving notifications?** Check daemon is running: `sudo systemctl status lumie-notify`
- **Token not uploading?** Check `flutter logs` for errors in `push_notification_service.dart`
- **Something else?** See full testing guide: `docs/NOTIFICATION_TESTING.md`

---

**Ready to test? Start with:** [docs/NOTIFICATION_TESTING.md](docs/NOTIFICATION_TESTING.md) Test 1: Build & Run App

