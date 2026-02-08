# ✅ Lumie Email Service - Setup Complete!

The email service has been successfully deployed to the server.

---

## 🎉 What's Been Done

✅ **Server Setup Complete:**
- Google API Python packages installed
- Email service module deployed to `/home/ubuntu/lumie_backend/app/services/email_service.py`
- Test script deployed to `/home/ubuntu/lumie_backend/test_email.py`
- Secrets directory created at `/home/ubuntu/secrets/`
- Requirements.txt updated with Google API dependencies

✅ **Email Templates Ready:**
- Basic email sending
- Verification email template (for user signup)
- Team invitation email template

---

## 🔑 NEXT STEP: Upload Service Account Key

**You need to upload the service account key file to complete the setup.**

### Option 1: If you have the key file locally

```bash
scp -i ~/.ssh/Lumie_Key.pem /path/to/lumie-mailer.json ubuntu@54.193.153.37:/home/ubuntu/secrets/
```

Replace `/path/to/lumie-mailer.json` with the actual path to your service account key.

### Option 2: If you need to download the key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project (e.g., "Lumie")
3. Navigate to **IAM & Admin** → **Service Accounts**
4. Find `lumie-mailer@*.iam.gserviceaccount.com`
5. Click the three dots (⋮) → **Manage Keys**
6. Click **Add Key** → **Create New Key**
7. Select **JSON** format
8. Download the key file
9. Upload to server:
   ```bash
   scp -i ~/.ssh/Lumie_Key.pem ~/Downloads/lumie-mailer-*.json ubuntu@54.193.153.37:/home/ubuntu/secrets/lumie-mailer.json
   ```

---

## 🧪 Testing the Email Service

Once the key is uploaded, run the test:

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend
source venv/bin/activate
python test_email.py
```

**This will send 3 test emails to ciline@gmail.com:**
1. ✉️ Basic test email
2. ✉️ Verification email template
3. ✉️ Team invitation email template

---

## 📧 Expected Output

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

Test Summary
====================================================
✅ PASS: Basic Email
✅ PASS: Verification Email
✅ PASS: Invitation Email

Total: 3/3 tests passed
====================================================
```

---

## 📬 Check Your Inbox

After running the test, check **ciline@gmail.com** inbox for:

- **Test Email** - "🌟 Lumie Email Service - Test Successful!"
- **Verification Email** - "Verify Your Lumie Account"
- **Invitation Email** - "You've been invited to join Smith Family on Lumie"

All emails should be from: **lumie@yumo.org**

---

## 🔍 Troubleshooting

### If test fails with "Service account key file not found"

The key file hasn't been uploaded yet. Follow the upload steps above.

### If test fails with "403 unauthorized_client"

Check these in Google Workspace Admin Console:
1. Domain-wide delegation is enabled
2. OAuth scope is correct: `https://www.googleapis.com/auth/gmail.send`
3. Service account client ID matches

### If emails go to spam

This is normal for the first few emails. To improve deliverability:
1. Configure SPF record in DNS
2. Enable DKIM in Google Workspace
3. Add DMARC policy

---

## 📚 Documentation

Detailed documentation available in:
- **[EMAIL_SETUP_GUIDE.md](EMAIL_SETUP_GUIDE.md)** - Complete setup guide
- **[gmail_send_with_lumie.md](../docs/gmail_send_with_lumie.md)** - Gmail API configuration
- **[email_service.py](app/services/email_service.py)** - Email service code

---

## 🚀 Using in Your Code

### Import the service

```python
from app.services.email_service import email_service
```

### Send verification email

```python
email_service.send_verification_email(
    to_email="user@example.com",
    verification_token="your_token_here"
)
```

### Send team invitation

```python
email_service.send_invitation_email(
    to_email="user@example.com",
    inviter_name="John Smith",
    team_name="Smith Family",
    invitation_link="https://yumo.org/invite/token_123",
    is_registered=False
)
```

### Send custom email

```python
email_service.send_email(
    to_email="user@example.com",
    subject="Welcome to Lumie",
    html_body="<h1>Welcome!</h1>",
    plain_body="Welcome!"
)
```

---

## 📊 Service Information

**Configuration:**
- Sender Email: `lumie@yumo.org`
- Service Account: `lumie-mailer@*.iam.gserviceaccount.com`
- Key Location: `/home/ubuntu/secrets/lumie-mailer.json`
- Server: `54.193.153.37`

**Limits:**
- Daily: 10,000 emails
- Per minute: 250 emails
- Burst: 100 emails/second

---

## ✅ Status Checklist

- [x] Google API packages installed
- [x] Email service code deployed
- [x] Test script deployed
- [x] Secrets directory created
- [ ] **Service account key uploaded** ← YOU ARE HERE
- [ ] Test emails sent
- [ ] Integration with signup endpoint
- [ ] Integration with team invitations

---

**Ready to test!** Upload the service account key and run the test script.

**Last Updated:** 2026-02-07
**Server:** 54.193.153.37
**Sender:** lumie@yumo.org
