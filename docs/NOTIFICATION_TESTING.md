# Push Notification Testing Guide

> Last Updated: 2026-03-12

## End-to-End Test Flow

This guide walks you through testing the complete push notification system from iOS app to backend daemon to APNs.

---

## Prerequisites

✅ **All systems ready:**
- [x] Notification daemon deployed & running on server
- [x] iOS entitlements configured (`aps-environment: development`)
- [x] Flask/Swift app code compiled
- [x] APNs credentials configured on server

**Requirements for testing:**
- Physical iOS device (iOS 14+) with push notifications enabled
- Developer provisioning profile matched to bundle ID `org.yumo.lumie`
- Xcode installed on local machine
- Access to production server (for checking logs)

---

## Test 1: Build & Run App

### 1.1 Build the Flutter App

```bash
cd lumie_activity_app

# Clean build
flutter clean

# Get dependencies
flutter pub get

# Build for iOS
flutter build ios --debug
```

**Expected output:**
```
✓ Built build/ios/Debug-iphonesimulator or build/ios/Debug-iphonedevice
```

### 1.2 Run on Physical Device

```bash
flutter run -d <device_id> --debug
```

Or through Xcode:
```bash
open ios/Runner.xcworkspace
# Select physical device, press Play
```

**Expected behavior:**
- App launches successfully
- No build errors related to entitlements or push notifications

---

## Test 2: Permission Dialog

### 2.1 First Launch

When you first open the app after successful login, you should see a **system notification permission dialog**:

```
Lumie Activity App
Would Like to Send You Notifications

Notifications may include alerts, sounds, and icon badges.

[Dont Allow]  [Allow]
```

**Expected behavior:**
- Dialog appears automatically on first launch
- User can tap "Allow" to grant permission

### 2.2 Verify Permission Was Granted

**In iOS Settings:**
1. Settings → Lumie Activity App → Notifications
2. Should show "Allow Notifications" is enabled
3. Check that "Sounds" and "Badges" are on

**In App Logs:**
```bash
flutter logs
```

Should show:
```
flutter: Push notification init started
flutter: Device token retrieved successfully
flutter: Token uploaded to backend
```

---

## Test 3: Device Token Upload

### 3.1 Check Token Was Stored on Server

After giving permission, the app should upload the APNs token to the backend.

**Via MongoDB (on server):**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
mongosh lumie_db

# Check your user's device token
db.users.findOne({email: "your_email@example.com"}).device_token

# Expected output:
# device_token: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2"
```

**Expected:** Token should be a long hex string (128 characters)

### 3.2 Check Backend Logs

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
sudo journalctl -u lumie-api -n 50 --no-pager | grep -i "device_token\|save-device"
```

Expected:
```
POST /api/v1/auth/save-device-token - token saved successfully
```

---

## Test 4: Create a Task for Testing

### 4.1 Create Test Task (Admin)

1. In the app, go to **Med-Reminder** → **All Tasks** (☑️ button)
2. Click **Create New Task**
3. Fill in:
   - **Task Name:** "Test Notification"
   - **Assigned to:** (yourself)
   - **Frequency:** Daily
   - **Start Date:** Today
   - **Time Window:** Next hour (e.g., if now is 3pm, set 4:00pm - 5:00pm)
   - **Early Phase:** 0% (starts immediately when task begins)
   - **Middle Phase:** 50%
   - **Late Phase:** 80%

4. **Save Task**

### 4.2 Verify Task in Database

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
mongosh lumie_db

# Find your test task
db.tasks.findOne({task_name: "Test Notification"})

# Check the output includes:
# - user_id: (your user ID)
# - status: "active"
# - assigned_to_user_id: (your user ID)
# - phases: { early: 0, middle: 50, late: 80 }
# - time_window: { start: "16:00:00", end: "17:00:00" }
```

---

## Test 5: Trigger Notification (Early Phase)

### 5.1 Monitor Daemon Logs (Terminal 1)

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
sudo journalctl -u lumie-notify -f
```

Leave this running to watch the daemon poll.

### 5.2 Wait for Early Phase

The daemon polls every 60 seconds. When it evaluates your task:

1. Current time >= task start time → Task is "active"
2. Task progress is at 0% (early phase triggered)
3. Device token exists on your user record
4. Daemon sends APNs request

**Expected daemon log output:**
```
2026-03-12 14:05:22,123 [INFO] Polling tasks...
2026-03-12 14:05:22,234 [INFO] Task "Test Notification" (user: xxx) in EARLY phase
2026-03-12 14:05:22,345 [INFO] Sending notification to device token: a1b2c3d4...
2026-03-12 14:05:22,456 [INFO] APNs response: 200 (sent successfully)
```

### 5.3 Device Notification Received

**On your iOS device:**
- You should see a **banner notification** at the top of the screen
- It should show something like:
  ```
  Lumie Activity App

  Task: Test Notification
  Phase: Early
  Progress: 0%
  ```

- Notification should have a **sound** and badge
- Tapping it should open the app

---

## Test 6: Deduplication Check (No Duplicate Notifications)

### 6.1 Wait for Next Poll Cycle

The daemon polls every 60 seconds. After the first notification:

1. Wait 60 seconds for the next poll
2. Daemon should **not** send another notification for the same task in the same phase
3. In-memory dedup cache prevents duplicates within the same polling interval

**Expected daemon log:**
```
2026-03-12 14:06:22,123 [INFO] Task "Test Notification" already notified in EARLY phase (dedup)
```

**Expected on device:**
- No new notification received

---

## Test 7: Middle & Late Phase Transitions

### 7.1 Manually Advance Task Progress

To simulate progress and trigger Middle/Late phases, you need to update the task progress in the database:

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
mongosh lumie_db

# Find your test task
const task = db.tasks.findOne({task_name: "Test Notification"})

# Update progress to 60% (triggers Middle phase)
db.tasks.updateOne(
  {_id: task._id},
  {$set: {progress_percentage: 60}}
)
```

### 7.2 Wait for Next Poll & Check Notification

- Daemon polls again (every 60 seconds)
- Detects task is at 60% (≥ 50% threshold for Middle phase)
- Sends **new notification** for Middle phase
- You should receive notification on device

**Expected notification:**
```
Lumie Activity App

Task: Test Notification
Phase: Middle
Progress: 60%
```

### 7.3 Repeat for Late Phase

```bash
# Update to 85% (triggers Late phase)
db.tasks.updateOne(
  {_id: task._id},
  {$set: {progress_percentage: 85}}
)
```

Wait for next poll → Late phase notification should arrive.

---

## Test 8: Logout & Token Cleanup

### 8.1 Logout from App

In the app:
1. Tap profile icon
2. Tap **Logout**

**Expected app behavior:**
- App makes `DELETE /api/v1/auth/device-token` request
- User is logged out

### 8.2 Verify Token Deleted

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
mongosh lumie_db

# Check your user record
db.users.findOne({email: "your_email@example.com"})

# Expected: device_token field should be null or missing
```

---

## Troubleshooting

### Notification Not Received

**Symptom:** No notification on device, but daemon logs show "sent successfully"

**Check:**
1. Settings → Lumie App → Notifications is enabled
2. Do Not Disturb is off
3. Volume is not muted
4. Token is actually on user record: `db.users.findOne({...}).device_token` is not null

**Fix:**
```bash
# Force request permission again
# 1. Delete app from device
# 2. Rebuild and run
# 3. Grant notification permission when prompted
```

### No Logs from Daemon

**Symptom:** `journalctl -u lumie-notify` shows nothing or service is not running

**Check:**
```bash
sudo systemctl status lumie-notify
```

**If not running:**
```bash
# Check logs for why it failed
sudo journalctl -u lumie-notify -n 50 --no-pager

# Restart
sudo systemctl restart lumie-notify

# Verify
sudo systemctl status lumie-notify
```

### Device Token is null

**Symptom:** Task created but `device_token` is null in DB

**Check:**
1. Did you see the permission dialog on iOS?
2. Did you tap "Allow"?
3. Are there any errors in `flutter logs`?

**Fix:**
```bash
# Check app logs
flutter logs

# Look for errors like:
# "MethodChannel timeout"
# "Platform exception"

# If entitlements are missing, rebuild:
flutter clean
flutter pub get
flutter run -d <device>
```

### App Crashes on Launch

**Symptom:** App crashes immediately after login

**Likely cause:** Missing or invalid entitlements

**Check:**
1. Verify `ios/Runner/Runner.entitlements` exists and has correct content
2. Verify `CODE_SIGN_ENTITLEMENTS` is set in project.pbxproj for all build configs
3. Verify `UIBackgroundModes: remote-notification` is in Info.plist

**Fix:**
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter build ios --debug
```

---

## Quick Reference: Command Cheatsheet

```bash
# Check daemon status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo systemctl status lumie-notify"

# Monitor daemon logs live
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo journalctl -u lumie-notify -f"

# Check device token on server
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "mongosh lumie_db"
# Then: db.users.findOne({email: 'YOUR_EMAIL'}).device_token

# Check iOS app logs
flutter logs

# Rebuild clean
flutter clean && flutter pub get && flutter run

# Create test task in admin dashboard
# Med-Reminder → ☑️ → Create New Task
```

---

## Success Criteria

✅ **Test 1:** App builds and runs without errors
✅ **Test 2:** Permission dialog appears on first login
✅ **Test 3:** Device token is uploaded and stored on server
✅ **Test 4:** Test task created successfully
✅ **Test 5:** Notification received when Early phase triggered
✅ **Test 6:** No duplicate notifications in same phase
✅ **Test 7:** Middle and Late phase notifications trigger correctly
✅ **Test 8:** Token is deleted after logout

**All tests passing?** 🎉 Push notifications are working end-to-end!

---

## Next Steps

After successful testing:

1. **Document Results:** Update this guide with your test results and timestamps
2. **Production Checklist:**
   - Change `APNS_USE_SANDBOX=false` in server `.env`
   - Change iOS entitlement from `development` to `production`
   - Rebuild and submit to App Store
3. **Production Testing:** Repeat these tests with production APNs credentials
4. **Monitor:** Check daemon logs daily for errors
5. **User Testing:** Have actual users test on their devices

