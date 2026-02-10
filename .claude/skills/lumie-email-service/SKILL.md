# Lumie Email Service Skill

## Description
Send system emails (verification emails, team invitations, notifications, etc.) using Gmail API with service account domain-wide delegation, sent from lumie@yumo.org

## When to Use
- User requests to send emails or test email functionality
- Need to send verification emails or team invitations
- Keywords: send email, test email, verification email, invitation email, email testing
- Need to integrate email functionality into FastAPI endpoints

## Prerequisites

### Server Information
- **Server IP:** 54.193.153.37
- **SSH Key:** `~/.ssh/Lumie_Key.pem`
- **User:** ubuntu

### Deployed Files
- **Email Service:** `/home/ubuntu/lumie_backend/app/services/email_service.py`
- **Test Script:** `/home/ubuntu/lumie_backend/test_email.py`
- **Service Account Key:** `/home/ubuntu/secrets/lumie-mailer.json`
- **Sender Email:** lumie@yumo.org

### Environment Variables (Optional)
```bash
GMAIL_SERVICE_ACCOUNT_FILE=/home/ubuntu/secrets/lumie-mailer.json
GMAIL_SENDER_EMAIL=lumie@yumo.org
```

## Features
✅ Service account authentication with domain-wide delegation
✅ HTML and plain text email support
✅ Beautiful, responsive email templates
✅ Pre-built verification email template
✅ Pre-built team invitation email template (supports registered/unregistered users)
✅ Singleton pattern for easy import
✅ Error handling and logging

## Instructions

### 1. Send Test Emails
Run the test script on the server (includes 3 test cases):

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend
source venv/bin/activate
python test_email.py
```

**Expected Output:**
```
✅ PASS: Basic Email
✅ PASS: Verification Email
✅ PASS: Invitation Email
Total: 3/3 tests passed
```

### 2. Use Email Service in Code

#### Send Verification Email
```python
from app.services.email_service import email_service

email_service.send_verification_email(
    to_email="user@example.com",
    verification_token="abc123xyz"
)
```

#### Send Team Invitation
```python
email_service.send_invitation_email(
    to_email="user@example.com",
    inviter_name="John Smith",
    team_name="Smith Family",
    invitation_link="https://yumo.org/invite/token_123",
    is_registered=False  # For unregistered users
)
```

#### Send Custom Email
```python
email_service.send_email(
    to_email="user@example.com",
    subject="Welcome to Lumie",
    html_body="<h1>Welcome!</h1><p>Thanks for joining!</p>",
    plain_body="Welcome! Thanks for joining!"
)
```

### 3. Integrate into FastAPI Endpoints

#### Example: Signup Endpoint
```python
# app/api/v1/auth.py
from app.services.email_service import email_service

@router.post("/signup")
async def signup(user_data: UserCreate):
    # Create user...
    user = await user_service.create_user(user_data)

    # Generate verification token
    verification_token = generate_token(user.id)

    # Send verification email
    email_service.send_verification_email(
        to_email=user.email,
        verification_token=verification_token
    )

    return {"message": "Verification email sent"}
```

#### Example: Team Invitation Endpoint
```python
# app/api/v1/teams.py
from app.services.email_service import email_service

@router.post("/teams/{team_id}/invite")
async def invite_member(team_id: str, data: TeamInvite):
    # Create invitation...
    invitation = await team_service.create_invitation(team_id, data.email)

    # Generate invitation token
    token = generate_invitation_token(team_id, data.email)
    invitation_link = f"https://yumo.org/invite/{token}"

    # Check if user is registered
    user = await user_service.get_user_by_email(data.email)
    is_registered = user is not None

    # Send invitation email
    email_service.send_invitation_email(
        to_email=data.email,
        inviter_name=current_user.name,
        team_name=team.name,
        invitation_link=invitation_link,
        is_registered=is_registered
    )

    return {"message": f"Invitation sent to {data.email}"}
```

### 4. Update Test Email Content

To modify test email content:

```bash
# Edit locally
cd /Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend
nano test_email.py

# Upload to server
scp -i ~/.ssh/Lumie_Key.pem test_email.py ubuntu@54.193.153.37:/home/ubuntu/lumie_backend/

# Run tests
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "cd /home/ubuntu/lumie_backend && source venv/bin/activate && python test_email.py"
```

## Examples

### Example 1: Quick Email Functionality Test
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 \
  "cd /home/ubuntu/lumie_backend && source venv/bin/activate && python test_email.py"
```

### Example 2: Check Email Service Status
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 \
  "cd /home/ubuntu/lumie_backend && source venv/bin/activate && \
   python -c 'from app.services.email_service import email_service; print(\"✅ Email service OK\")'"
```

### Example 3: Send Single Test Email
```python
# Execute on server
cd /home/ubuntu/lumie_backend
source venv/bin/activate
python -c "
from app.services.email_service import email_service
email_service.send_email(
    to_email='ciline@gmail.com',
    subject='Test from Lumie',
    html_body='<h1>Hello!</h1><p>This is a test.</p>'
)
"
```

## Error Handling

### Error 1: Service account key file not found
**Symptoms:**
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

### Error 2: 403 unauthorized_client
**Symptoms:**
```
Gmail API error: <HttpError 403 when requesting ... returned "Unauthorized">
```

**Possible Causes:**
1. Domain-wide delegation not configured
2. Incorrect OAuth scope
3. Service account client ID mismatch

**Solution:**
1. Check Google Workspace Admin Console → API Controls → Domain-wide delegation
2. Verify scope: `https://www.googleapis.com/auth/gmail.send`
3. Ensure lumie@yumo.org is a real Workspace user

### Error 3: Module not found
**Symptoms:**
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

### Error 4: Emails Going to Spam
**Solutions:**
1. **Configure SPF Record** (add to DNS):
   ```
   v=spf1 include:_spf.google.com ~all
   ```

2. **Enable DKIM** (in Google Workspace Admin Console)

3. **Add DMARC Policy** (add to DNS):
   ```
   v=DMARC1; p=quarantine; rua=mailto:postmaster@yumo.org
   ```

## Safety Checks
- ✅ Only send emails when explicitly requested by user
- ✅ Test emails sent to ciline@gmail.com
- ✅ Confirm recipient address before sending in production
- ✅ Sensitive information (service account key) not committed to git
- ✅ Use environment variables for configuration

## Usage Limits
- **Daily Quota:** 10,000 emails/day (Workspace account)
- **Per-minute Quota:** 250 emails/minute
- **Burst Limit:** 100 emails/second

Monitor usage:
- Google Cloud Console → APIs & Services → Gmail API → Quotas

## Documentation
- **Complete Setup Guide:** `lumie_backend/EMAIL_SETUP_GUIDE.md`
- **Quick Start Guide:** `lumie_backend/EMAIL_SETUP_COMPLETE.md`
- **Developer Reference:** `docs/gmail_send_with_lumie.md`

## Quick Reference
```bash
# Run tests
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 \
  "cd /home/ubuntu/lumie_backend && source venv/bin/activate && python test_email.py"

# Check service
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 \
  "cd /home/ubuntu/lumie_backend && source venv/bin/activate && \
   python -c 'from app.services.email_service import email_service; print(\"OK\")'"

# View service account key
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "ls -la /home/ubuntu/secrets/"
```

---

**Status:** ✅ Production Ready (2026-02-07)
**Sender Email:** lumie@yumo.org
**Server:** 54.193.153.37
**Last Tested:** 2026-02-07 (3/3 tests passed)
