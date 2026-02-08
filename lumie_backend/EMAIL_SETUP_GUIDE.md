# Lumie Email Service - Setup Guide

Complete guide to setting up email sending functionality on the Lumie backend server.

---

## 📋 Prerequisites

Before starting, ensure you have:

1. **Service Account Key File** (`lumie-mailer.json`)
   - Downloaded from Google Cloud Console
   - Contains credentials for lumie-mailer@*.iam.gserviceaccount.com
   - Must have Domain-wide Delegation enabled

2. **Server Access**
   - SSH access to 54.193.153.37
   - SSH key: `~/.ssh/Lumie_Key.pem`
   - User: ubuntu

3. **Gmail API Configuration** (Already completed)
   - Gmail API enabled in Google Cloud
   - Domain-wide delegation configured in Google Workspace Admin Console
   - Scope: `https://www.googleapis.com/auth/gmail.send`
   - Delegated user: lumie@yumo.org

---

## 🚀 Quick Setup (Automated)

### Step 1: Run Setup Script

From your local machine:

```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend
bash setup_email.sh
```

**What this does:**
- ✅ Installs Google API Python packages
- ✅ Creates `/home/ubuntu/secrets` directory
- ✅ Uploads email service files to server
- ✅ Sets up directory permissions

### Step 2: Upload Service Account Key

Replace `/path/to/lumie-mailer.json` with the actual path to your service account key:

```bash
scp -i ~/.ssh/Lumie_Key.pem /path/to/lumie-mailer.json ubuntu@54.193.153.37:/home/ubuntu/secrets/
```

**Security check:**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "ls -la /home/ubuntu/secrets/"
```

Expected output: `-rw------- 1 ubuntu ubuntu ... lumie-mailer.json`

### Step 3: Test Email Service

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend
source venv/bin/activate
python test_email.py
```

**Expected output:**
```
🌟 Lumie Email Service Test Suite 🌟

Test 1: Basic Email
====================================================
Lumie Email Service - Test Script
====================================================

📧 Initializing email service...
📬 Sending test email to: ciline@gmail.com
📮 From: lumie@yumo.org

✅ Email sent successfully to ciline@gmail.com

====================================================
✅ SUCCESS: Test email sent!
📬 Check inbox: ciline@gmail.com
====================================================

Test 2: Verification Email
...
```

### Step 4: Check Your Inbox

Open Gmail and check ciline@gmail.com inbox for:
- ✉️ Test email from lumie@yumo.org
- ✉️ Verification email template
- ✉️ Team invitation email template

---

## 📁 Files Overview

### Created Files

```
lumie_backend/
├── app/
│   └── services/
│       └── email_service.py       # Main email service class
├── test_email.py                  # Test script (3 test cases)
├── setup_email.sh                 # Automated setup script
├── EMAIL_SETUP_GUIDE.md          # This file
└── requirements.txt               # Updated with Google API deps

/home/ubuntu/secrets/              # Server directory
└── lumie-mailer.json             # Service account key (upload manually)
```

### Email Service Features

**`email_service.py`** provides:

```python
from app.services.email_service import email_service

# Send custom email
email_service.send_email(
    to_email="user@example.com",
    subject="Welcome",
    html_body="<h1>Hello!</h1>",
    plain_body="Hello!"
)

# Send verification email (template)
email_service.send_verification_email(
    to_email="user@example.com",
    verification_token="token_123"
)

# Send team invitation (template)
email_service.send_invitation_email(
    to_email="user@example.com",
    inviter_name="John Smith",
    team_name="Smith Family",
    invitation_link="https://yumo.org/invite/token",
    is_registered=False
)
```

---

## 🔧 Manual Setup (Step-by-Step)

If automated setup fails, follow these manual steps:

### 1. Install Dependencies

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend
source venv/bin/activate

# Install Google API packages
pip install google-api-python-client==2.116.0
pip install google-auth==2.27.0
pip install google-auth-httplib2==0.2.0
pip install google-auth-oauthlib==1.2.0
```

### 2. Create Secrets Directory

```bash
mkdir -p /home/ubuntu/secrets
chmod 700 /home/ubuntu/secrets
```

### 3. Upload Email Service Files

From local machine:

```bash
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend

# Upload email service
scp -i ~/.ssh/Lumie_Key.pem \
    app/services/email_service.py \
    ubuntu@54.193.153.37:/home/ubuntu/lumie_backend/app/services/

# Upload test script
scp -i ~/.ssh/Lumie_Key.pem \
    test_email.py \
    ubuntu@54.193.153.37:/home/ubuntu/lumie_backend/
```

### 4. Upload Service Account Key

```bash
scp -i ~/.ssh/Lumie_Key.pem \
    /path/to/lumie-mailer.json \
    ubuntu@54.193.153.37:/home/ubuntu/secrets/
```

### 5. Set Environment Variables (Optional)

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend

# Add to .env file
echo 'GMAIL_SERVICE_ACCOUNT_FILE=/home/ubuntu/secrets/lumie-mailer.json' >> .env
echo 'GMAIL_SENDER_EMAIL=lumie@yumo.org' >> .env
```

### 6. Test

```bash
cd /home/ubuntu/lumie_backend
source venv/bin/activate
python test_email.py
```

---

## 🧪 Testing

### Run All Tests

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend
source venv/bin/activate
python test_email.py
```

### Run Individual Tests

Edit `test_email.py` and comment out unwanted tests, or run in Python:

```python
from app.services.email_service import EmailService

email_service = EmailService()

# Test basic email
email_service.send_email(
    to_email="ciline@gmail.com",
    subject="Test",
    html_body="<h1>Test</h1>"
)
```

### Check Sent Emails

1. **Gmail Inbox**: Check ciline@gmail.com
2. **Spam Folder**: Check if emails landed in spam
3. **Gmail Sent Items**: Login to lumie@yumo.org and check Sent folder

---

## 🔍 Troubleshooting

### Error: Service account key file not found

**Symptom:**
```
Exception: Service account key file not found: /home/ubuntu/secrets/lumie-mailer.json
```

**Solution:**
```bash
# Check if file exists
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "ls -la /home/ubuntu/secrets/"

# Re-upload if missing
scp -i ~/.ssh/Lumie_Key.pem /path/to/lumie-mailer.json ubuntu@54.193.153.37:/home/ubuntu/secrets/
```

### Error: 403 / unauthorized_client

**Symptom:**
```
Gmail API error: <HttpError 403 when requesting ... returned "Unauthorized">
```

**Possible causes:**
1. Domain-wide delegation not configured
2. Wrong OAuth scope
3. Service account client ID doesn't match

**Solution:**
1. Check Google Workspace Admin Console → API controls → Domain-wide delegation
2. Verify scope: `https://www.googleapis.com/auth/gmail.send`
3. Ensure lumie@yumo.org exists as a real user

### Error: Module not found

**Symptom:**
```
ModuleNotFoundError: No module named 'googleapiclient'
```

**Solution:**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend
source venv/bin/activate
pip install google-api-python-client google-auth google-auth-httplib2
```

### Emails Going to Spam

**Solutions:**
1. **SPF Record**: Add to DNS:
   ```
   v=spf1 include:_spf.google.com ~all
   ```

2. **DKIM**: Configure in Google Workspace Admin

3. **DMARC**: Add to DNS:
   ```
   v=DMARC1; p=quarantine; rua=mailto:postmaster@yumo.org
   ```

### Test Script Fails to Import

**Symptom:**
```
ModuleNotFoundError: No module named 'app'
```

**Solution:**
```bash
# Make sure you're in the correct directory
cd /home/ubuntu/lumie_backend

# Run from backend root
python test_email.py
```

---

## 🔐 Security Best Practices

1. **Service Account Key Protection**
   ```bash
   # Set strict permissions
   chmod 600 /home/ubuntu/secrets/lumie-mailer.json
   chmod 700 /home/ubuntu/secrets
   ```

2. **Never Commit Secrets**
   - ❌ Don't commit `lumie-mailer.json` to git
   - ❌ Don't include in Docker images
   - ✅ Use environment variables for paths

3. **Rotate Keys Periodically**
   - Create new service account key
   - Update on server
   - Delete old key in Google Cloud Console

4. **Monitor Usage**
   - Check Gmail API quota in Google Cloud Console
   - Review sent emails regularly
   - Set up alerts for unusual activity

---

## 📊 Integration with Backend

### Add to FastAPI App

```python
# app/main.py
from app.services.email_service import email_service

@app.post("/api/v1/auth/signup")
async def signup(user_data: UserCreate):
    # Create user...

    # Send verification email
    email_service.send_verification_email(
        to_email=user_data.email,
        verification_token=verification_token
    )

    return {"message": "Verification email sent"}
```

### Add to Team Invitation

```python
# app/api/v1/teams.py
from app.services.email_service import email_service

@router.post("/teams/{team_id}/invite")
async def invite_member(team_id: str, data: TeamInvite):
    # Create invitation...

    # Send invitation email
    email_service.send_invitation_email(
        to_email=data.email,
        inviter_name=current_user.name,
        team_name=team.name,
        invitation_link=f"https://yumo.org/invite/{token}",
        is_registered=user_exists
    )

    return {"message": "Invitation sent"}
```

---

## 📈 Usage Limits

**Gmail API Limits:**
- **Daily Send Quota**: 10,000 emails/day (Workspace account)
- **Per-minute Quota**: 250 emails/minute
- **Burst Limit**: 100 emails/second

**Monitor Usage:**
- Google Cloud Console → APIs & Services → Gmail API → Quotas

---

## 🎯 Next Steps

After successful setup:

1. **✅ Test all email templates** - Run test_email.py
2. **✅ Integrate with signup endpoint** - Send verification emails
3. **✅ Integrate with team invitations** - Send invitation emails
4. **✅ Add password reset emails** - Create new template
5. **✅ Set up email monitoring** - Track delivery and bounces
6. **✅ Configure SPF/DKIM/DMARC** - Improve deliverability

---

## 📞 Support

**Check Status:**
```bash
# Check if service is accessible
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 \
    "cd /home/ubuntu/lumie_backend && source venv/bin/activate && python -c 'from app.services.email_service import email_service; print(\"✅ Email service OK\")'"
```

**View Logs:**
```bash
# If integrated with FastAPI
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo journalctl -u lumie-api -n 100 --no-pager | grep -i email"
```

**Resources:**
- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [Service Account Documentation](https://cloud.google.com/iam/docs/service-accounts)
- [Domain-wide Delegation Guide](https://developers.google.com/identity/protocols/oauth2/service-account#delegatingauthority)

---

**Last Updated:** 2026-02-06
**Status:** Ready for Testing
**Sender Email:** lumie@yumo.org
**Server:** 54.193.153.37
