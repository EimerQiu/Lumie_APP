# Push Notification Deployment Guide

> Status: **Deployed to Production** (2026-03-12)

## Quick Start (Production Server)

If you already have an Apple Developer account with APNs capability and a `.p8` key file:

```bash
# 1. Obtain your APNs credentials from Apple Developer Portal
# You need: Key file (.p8), Key ID, Team ID, Bundle ID

# 2. Set environment variables
export APNS_KEY_PATH=/home/ubuntu/lumie_backend/AuthKey_XXXXX.p8
export APNS_KEY_ID=XXXXX
export APNS_TEAM_ID=XXXXX
export APNS_TOPIC=org.yumo.lumie
export APNS_USE_SANDBOX=true  # or false for production

# 3. Deploy backend and notification daemon
cd lumie_backend
bash deploy.sh

# 4. Copy service file to systemd
sudo cp lumie-notify.service /etc/systemd/system/
sudo systemctl daemon-reload

# 5. Enable and start daemon
sudo systemctl enable lumie-notify
sudo systemctl start lumie-notify

# 6. Verify
sudo systemctl status lumie-notify
sudo journalctl -u lumie-notify -f
```

---

## Full Setup Instructions

### Prerequisites

- Apple Developer Account with **paid membership** ($99/year)
- APNs capability enabled for your bundle ID (`org.yumo.lumie`)
- A `.p8` APNs key file from Apple Developer Portal
- Access to production server (SSH key configured)

### Step 1: Get APNs Credentials

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles** → **Keys**
3. Create a new key with **Apple Push Notifications service (APNs)** capability
4. Download the `.p8` file (e.g., `AuthKey_9YS58RKP86.p8`)
5. Note the **Key ID** (e.g., `9YS58RKP86`)
6. Note your **Team ID** (visible in top-right of Developer portal)

**Example Credentials:**
```
Key ID: 9YS58RKP86
Team ID: G756UPT65U
Bundle ID: org.yumo.lumie
```

### Step 2: Upload Key to Server

```bash
# From your local machine
scp -i ~/.ssh/Lumie_Key.pem /path/to/AuthKey_9YS58RKP86.p8 \
  ubuntu@54.177.85.124:/home/ubuntu/lumie_backend/
```

### Step 3: Configure Environment Variables

SSH into the server and edit the backend `.env` file:

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
cd /home/ubuntu/lumie_backend
nano .env
```

Add these lines (replace with your actual values):

```bash
APNS_KEY_PATH=/home/ubuntu/lumie_backend/AuthKey_9YS58RKP86.p8
APNS_KEY_ID=9YS58RKP86
APNS_TEAM_ID=G756UPT65U
APNS_TOPIC=org.yumo.lumie
APNS_USE_SANDBOX=true
```

Or use command-line (non-interactive):

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 << 'EOF'
cat >> /home/ubuntu/lumie_backend/.env << 'ENVEOF'

APNS_KEY_PATH=/home/ubuntu/lumie_backend/AuthKey_9YS58RKP86.p8
APNS_KEY_ID=9YS58RKP86
APNS_TEAM_ID=G756UPT65U
APNS_TOPIC=org.yumo.lumie
APNS_USE_SANDBOX=true
ENVEOF
EOF
```

### Step 4: Deploy Notification Daemon

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 << 'EOF'
cd /home/ubuntu/lumie_backend

# Copy systemd service file
sudo cp lumie-notify.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable and start the daemon
sudo systemctl enable lumie-notify
sudo systemctl start lumie-notify

# Verify it's running
sudo systemctl status lumie-notify --no-pager
EOF
```

### Step 5: Verify Deployment

Check daemon status and logs:

```bash
# Check service status
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo systemctl status lumie-notify --no-pager"

# View recent logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo journalctl -u lumie-notify -n 50 --no-pager"

# Monitor live logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo journalctl -u lumie-notify -f"
```

Expected output:
```
● lumie-notify.service - Lumie Notification Daemon
   Loaded: loaded (/etc/systemd/system/lumie-notify.service; enabled)
   Active: active (running) since Thu 2026-03-12 01:55:22 UTC
```

---

## Configuration Reference

### Environment Variables

| Variable | Example | Description | Required |
|----------|---------|-------------|----------|
| `APNS_KEY_PATH` | `/home/ubuntu/lumie_backend/AuthKey_9YS58RKP86.p8` | Absolute path to `.p8` key file | Yes |
| `APNS_KEY_ID` | `9YS58RKP86` | Key ID from Apple Developer Portal | Yes |
| `APNS_TEAM_ID` | `G756UPT65U` | Apple Developer Team ID | Yes |
| `APNS_TOPIC` | `org.yumo.lumie` | iOS bundle identifier (must match app) | Yes |
| `APNS_USE_SANDBOX` | `true` \| `false` | `true` for development, `false` for production | Yes |
| `MONGODB_URL` | (from backend .env) | MongoDB connection string | Yes |
| `MONGODB_DB_NAME` | `lumie_db` | Database name (inherited from backend config) | No |

### iOS Configuration

No changes needed if coming from 2026-03-06 implementation. The following are already configured:

**File: `ios/Runner/Runner.entitlements`**
```xml
<key>aps-environment</key>
<string>development</string>  <!-- Change to "production" for App Store -->
```

**File: `ios/Runner/Info.plist`**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

**File: `ios/Runner.xcodeproj/project.pbxproj`**
```
CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;
```

---

## Troubleshooting

### Daemon won't start

**Check logs:**
```bash
sudo journalctl -u lumie-notify -n 30 --no-pager
```

**Common issues:**
- ❌ `No such file or directory: AuthKey_XXXXX.p8` → Key file not uploaded to server
- ❌ `Invalid key ID` → Check `APNS_KEY_ID` matches file name and Apple Portal
- ❌ `Connection refused (MongoDB)` → Ensure `mongod` is running
- ❌ `EnvironmentFile=... not found` → The `.env` file doesn't exist; create it

**Fix steps:**
```bash
# 1. Verify key file exists
ls -lh /home/ubuntu/lumie_backend/AuthKey_*.p8

# 2. Check .env file
cat /home/ubuntu/lumie_backend/.env | grep APNS

# 3. Verify MongoDB is running
sudo systemctl status mongod

# 4. Restart daemon
sudo systemctl restart lumie-notify

# 5. Check logs again
sudo journalctl -u lumie-notify -f
```

### iOS app not receiving notifications

**Checklist:**
- [ ] iOS device has notifications permission granted (check Settings → Lumie App)
- [ ] Device token is uploaded: `POST /api/v1/auth/save-device-token` returns 200
- [ ] Token is stored in DB: `db.users.findOne({_id: "..."}).device_token` is not null
- [ ] Daemon is running: `sudo systemctl status lumie-notify` shows "active (running)"
- [ ] Daemon logs show task polling (check `journalctl`)
- [ ] Task is in Early/Middle/Late phase threshold (check task progress in DB)

**Debug steps:**
```bash
# Check if daemon is polling
sudo journalctl -u lumie-notify -n 20 | grep -i "task\|poll\|phase"

# Check device tokens in database
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
mongosh
use lumie_db
db.users.find({device_token: {$exists: true, $ne: null}})

# Check task records
db.tasks.findOne({_id: ObjectId("...")})
```

### Key file permissions

If you get permission errors:

```bash
# Ensure key file is readable by the notification daemon user (ubuntu)
sudo chown ubuntu:ubuntu /home/ubuntu/lumie_backend/AuthKey_*.p8
sudo chmod 600 /home/ubuntu/lumie_backend/AuthKey_*.p8
```

---

## Switching to Production

When ready for App Store release:

### 1. Update APNs Environment

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
nano /home/ubuntu/lumie_backend/.env

# Change:
# APNS_USE_SANDBOX=true
# To:
# APNS_USE_SANDBOX=false

# Then restart the daemon
sudo systemctl restart lumie-notify
```

### 2. Update iOS Entitlement

Edit `ios/Runner/Runner.entitlements`:

```xml
<!-- Change from: -->
<string>development</string>

<!-- To: -->
<string>production</string>
```

Build and submit to App Store.

### 3. Optional: Update APNs Key

If Apple issues a separate production key:

```bash
# Upload new key
scp -i ~/.ssh/Lumie_Key.pem AuthKey_PROD.p8 ubuntu@54.177.85.124:/home/ubuntu/lumie_backend/

# Update .env
APNS_KEY_PATH=/home/ubuntu/lumie_backend/AuthKey_PROD.p8
APNS_KEY_ID=<new-key-id>

# Restart
sudo systemctl restart lumie-notify
```

---

## Monitoring & Maintenance

### Daily/Weekly Checks

```bash
# Check daemon health
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo systemctl status lumie-notify"

# Check error rate in logs
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo journalctl -u lumie-notify --since '24 hours ago' | grep -i error"

# Check MongoDB connection
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo systemctl status mongod"
```

### Key Expiry

Apple APNs keys **never expire**, so no action needed.

### Logs Rotation

Logs are managed by systemd's journal. Default retention is 7 days. To keep longer:

```bash
sudo nano /etc/systemd/journald.conf
# Set: MaxRetentionSec=30day
sudo systemctl restart systemd-journald
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ iOS App (lumie_activity_app)                                │
│ - Requests notification permission on first launch          │
│ - Uploads APNs device token via POST /auth/save-device-token│
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ (token stored in users.device_token)
                       │
        ┌──────────────▼──────────────┐
        │ FastAPI Backend             │
        │ (lumie-api service)         │
        │ - Auth routes               │
        │ - Task management           │
        │ - Database queries          │
        └──────────────┬──────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
┌───────▼─────────┐      ┌──────────▼──────────────┐
│ MongoDB         │      │ Notification Daemon     │
│ - users         │◄─────┤ (lumie-notify service) │
│ - tasks         │      │ - Polls every 60s       │
│ - profiles      │      │ - Evaluates phases      │
│ - etc.          │      │ - Sends APNs requests   │
└─────────────────┘      └──────────────┬──────────┘
                                        │
                         ┌──────────────▼──────────────┐
                         │ Apple Push Notification     │
                         │ Service (APNs)             │
                         │ - HTTP/2 server            │
                         │ - Authenticates via JWT    │
                         └──────────────┬──────────────┘
                                        │
                         ┌──────────────▼──────────────┐
                         │ iOS Device               │
                         │ - Receives notification   │
                         │ - Displays alert/badge   │
                         └──────────────────────────┘
```

---

## Related Documentation

- [Push Notifications Dev Log](./dev-logs/2026-03-12-push-notifications-restore.md) — Full implementation details
- [Original Push Notifications Dev Log](./dev-logs/2026-03-06-push-notifications.md) — Initial architecture
- [Med-Reminder PRD](./PRD.md#med-reminder) — Feature requirements
- `lumie_backend/notification_daemon.py` — Daemon source code
- `lumie_activity_app/lib/core/services/push_notification_service.dart` — Flutter service

