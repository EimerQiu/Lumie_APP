# Sending System Emails as lumie@yumo.org
(Gmail API + Domain-wide Delegation)

**Status:** ✅ **IMPLEMENTED AND TESTED** (2026-02-07)

This document explains how the **Lumie backend** sends system emails (e.g. verification or invitation emails) **as `lumie@yumo.org`** using **Google Workspace**, **Gmail API**, and a **Service Account with Domain-wide Delegation**.

This guide is intended for **backend developers**.

---

## 📁 Implementation Files

The email service has been fully implemented:

- **[`lumie_backend/app/services/email_service.py`](../lumie_backend/app/services/email_service.py)** - Main EmailService class (LIVE)
- **[`lumie_backend/test_email.py`](../lumie_backend/test_email.py)** - Test script with 3 test cases
- **[`lumie_backend/EMAIL_SETUP_GUIDE.md`](../lumie_backend/EMAIL_SETUP_GUIDE.md)** - Complete setup guide
- **[`lumie_backend/EMAIL_SETUP_COMPLETE.md`](../lumie_backend/EMAIL_SETUP_COMPLETE.md)** - Quick start guide

**Server:** 54.193.153.37
**Service Account Key:** `/home/ubuntu/secrets/lumie-mailer.json` (deployed)
**Sender Email:** `lumie@yumo.org`

---

## 1. Architecture Overview

### Key Components

- **System Sender Email**
  - `lumie@yumo.org`
  - A real Google Workspace user
  - Used only as a system sender (no human login required)

- **Service Account**
  - `lumie-mailer@<project>.iam.gserviceaccount.com`
  - Not a real mailbox
  - Authorized via Domain-wide Delegation to impersonate Workspace users

- **Gmail API**
  - Used to send emails programmatically
  - Scope: `gmail.send`

---

### How It Works (Simplified)

```

Backend Code
↓
Service Account (lumie-mailer)
↓  Domain-wide Delegation
Impersonate: [lumie@yumo.org](mailto:lumie@yumo.org)
↓
Gmail API
↓
Recipient Inbox

```

Recipients will see:

```

From: [lumie@yumo.org](mailto:lumie@yumo.org)

````

---

## 2. Actual Implementation (Production)

### 2.1 Quick Usage

The email service is ready to use in your backend code:

```python
from app.services.email_service import email_service

# Send verification email
email_service.send_verification_email(
    to_email="user@example.com",
    verification_token="abc123xyz"
)

# Send team invitation
email_service.send_invitation_email(
    to_email="user@example.com",
    inviter_name="John Smith",
    team_name="Smith Family",
    invitation_link="https://yumo.org/invite/token_123",
    is_registered=False  # For unregistered users
)

# Send custom email
email_service.send_email(
    to_email="user@example.com",
    subject="Welcome to Lumie",
    html_body="<h1>Welcome!</h1>",
    plain_body="Welcome!"
)
```

### 2.2 Implementation Details

**Location:** [`lumie_backend/app/services/email_service.py`](../lumie_backend/app/services/email_service.py)

**Key Features:**
- ✅ Service account authentication with domain-wide delegation
- ✅ HTML and plain text email support
- ✅ Beautiful, responsive email templates
- ✅ Pre-built verification email template
- ✅ Pre-built team invitation email template
- ✅ Configurable via environment variables
- ✅ Error handling and logging
- ✅ Singleton pattern for easy import

**Configuration:**
```python
# Environment variables (optional)
GMAIL_SERVICE_ACCOUNT_FILE=/home/ubuntu/secrets/lumie-mailer.json
GMAIL_SENDER_EMAIL=lumie@yumo.org

# Defaults if not set
service_account_file = "/home/ubuntu/secrets/lumie-mailer.json"
sender_email = "lumie@yumo.org"
```

### 2.3 Testing

Run the test script on the server:

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend
source venv/bin/activate
python test_email.py
```

**Test Results (Latest Run: 2026-02-07):**
```
✅ PASS: Basic Email
✅ PASS: Verification Email
✅ PASS: Invitation Email

Total: 3/3 tests passed
```

---

## 3. Prerequisites (Admin Setup)

The following steps have been completed by a Google Workspace / Cloud administrator:

1. Google Cloud Project created (e.g. `Lumie`)
2. Gmail API enabled
3. Service Account `lumie-mailer` created
4. Domain-wide Delegation enabled on the Service Account
5. Google Admin Console → API controls → Domain-wide delegation:
   - Client ID: `lumie-mailer`
   - OAuth Scope:
     ```
     https://www.googleapis.com/auth/gmail.send
     ```
6. `lumie@yumo.org` exists as a real Workspace user (not just an alias)

---

## 4. Development Environment Setup

### Install Dependencies

```bash
pip install google-api-python-client google-auth google-auth-httplib2
````

### Service Account Key

* Download the Service Account JSON key
* Store it securely, for example:

```
secrets/
└── lumie-mailer.json
```

⚠️ **Security note**
Never commit this file to source control.

---

## 5. Reference: Minimal Working Example (Python)

> **Note:** The code below is a simplified reference. For production use, see the actual implementation in [`email_service.py`](../lumie_backend/app/services/email_service.py).

### 5.1 Configuration

```python
SERVICE_ACCOUNT_FILE = "secrets/lumie-mailer.json"
SENDER = "lumie@yumo.org"
SCOPES = ["https://www.googleapis.com/auth/gmail.send"]
```

---

### 5.2 Create Gmail API Client

```python
from google.oauth2 import service_account
from googleapiclient.discovery import build

def get_gmail_service():
    creds = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE,
        scopes=SCOPES,
    )

    # Key point: impersonate lumie@yumo.org
    delegated_creds = creds.with_subject(SENDER)

    service = build("gmail", "v1", credentials=delegated_creds)
    return service
```

---

### 5.3 Send Email Function

```python
from email.mime.text import MIMEText
import base64

def send_email(to_email: str, subject: str, html_body: str):
    message = MIMEText(html_body, "html", "utf-8")
    message["to"] = to_email
    message["from"] = SENDER
    message["subject"] = subject

    raw_message = base64.urlsafe_b64encode(
        message.as_bytes()
    ).decode("utf-8")

    service = get_gmail_service()
    service.users().messages().send(
        userId="me",
        body={"raw": raw_message},
    ).execute()
```

---

### 5.4 Example Usage

```python
send_email(
    to_email="user@example.com",
    subject="Welcome to Lumie",
    html_body="""
    <h2>Welcome to Lumie</h2>
    <p>Please verify your email:</p>
    <p>
      <a href="https://yumo.org/verify?token=EXAMPLE_TOKEN">
        Verify my email
      </a>
    </p>
    """
)
```

---

## 6. Critical Notes (Please Read)

### 6.1 `with_subject()` Controls the Sender

```python
delegated_creds = creds.with_subject("lumie@yumo.org")
```

* The email specified here:

  * Must be a real Workspace user
  * Determines the **From** address of the email

---

### 6.2 Service Account Is Never the Sender

Recipients will **never** see:

```
lumie-mailer@*.iam.gserviceaccount.com
```

The Service Account only provides authorization.

---

### 6.3 No OAuth Consent Screen Required

* No user login flow
* No OAuth client ID
* No consent screen
* Fully server-to-server

---

### 6.4 Common Errors & Troubleshooting

#### 403 / `unauthorized_client`

* Check Admin Console → API controls → Domain-wide delegation
* Ensure `gmail.send` scope is authorized
* Verify the correct Client ID

#### Incorrect From Address

* Check `with_subject("lumie@yumo.org")`
* Ensure the address is a real user, not an alias

---

## 7. Recommended Use Cases

**Recommended**

* Email verification
* User invitations
* System notifications

**Not recommended**

* Human-to-human support conversations
* Personal or ad-hoc emails

---

## 8. Security & Best Practices

* Store Service Account keys securely (Vault / Secret Manager)
* Grant only required scopes
* Add:

  * Rate limiting
  * Token expiration
  * Audit logging

---

## 9. Implementation Status

### ✅ Completed

* **Email Service Class:** [`email_service.py`](../lumie_backend/app/services/email_service.py)
  * Basic email sending with HTML and plain text
  * Service account authentication with domain-wide delegation
  * Error handling and logging
  * Singleton pattern for easy import

* **Email Templates:** Beautiful HTML templates with responsive design
  * Verification email template
  * Team invitation email template (supports registered and unregistered users)
  * Custom email support

* **Testing:** [`test_email.py`](../lumie_backend/test_email.py)
  * 3 comprehensive test cases
  * Successfully tested on production server (2026-02-07)

* **Documentation:**
  * [`EMAIL_SETUP_GUIDE.md`](../lumie_backend/EMAIL_SETUP_GUIDE.md) - Complete setup guide
  * [`EMAIL_SETUP_COMPLETE.md`](../lumie_backend/EMAIL_SETUP_COMPLETE.md) - Quick start guide
  * This document - Developer reference

* **Deployment:**
  * Deployed to server: 54.193.153.37
  * Service account key installed
  * Dependencies installed
  * Permissions configured

### 🔄 Pending Integration

* FastAPI endpoints integration:
  * `/api/v1/auth/signup` - Send verification email
  * `/api/v1/teams/{team_id}/invite` - Send invitation email
  * `/api/v1/auth/password-reset` - Password reset emails

### 🎯 Future Extensions

* Email templates (Jinja2) for more flexibility
* Localization / i18n support
* Background queues (Celery / Cloud Tasks) for high volume
* Email analytics (open rates, click tracking)
* Template versioning and A/B testing

---

**Status:** ✅ Production Ready
**Maintained by:** Lumie Engineering
**System Sender:** [lumie@yumo.org](mailto:lumie@yumo.org)
**Last Updated:** 2026-02-07