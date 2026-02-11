# Lumie Project Custom Skills

This directory contains custom Claude Code Skills created for the Lumie project.

## 📁 Available Skills

### 1. **lumie-email-service** - Email Service Management
📧 Manage Gmail API email sending functionality

**Trigger Keywords:**
- send email, test email, email testing
- verification email, invitation email
- email service, email functionality

**Main Features:**
- Send test emails
- Send verification emails
- Send team invitation emails
- Integrate with FastAPI endpoints
- Troubleshoot email issues

**Documentation:** `lumie-email-service/SKILL.md`

---

### 2. **lumie-deployment** - Deployment Management
🚀 Automate deployment of website and backend API

**Trigger Keywords:**
- deploy, deployment, release
- push to production, update website
- restart service, check status

**Main Features:**
- Deploy frontend website to https://yumo.org
- Deploy backend API to server
- Manage services (Nginx, MongoDB, lumie-api)
- SSL certificate management
- Troubleshoot and rollback

**Documentation:** `lumie-deployment/SKILL.md`

---

## 🎯 How to Use These Skills

### Automatic Triggering
Claude Code will automatically match and use the appropriate skill based on your natural language request:

**Example Conversations:**

```
You: "Help me send a test email to ciline@gmail.com"
→ Automatically triggers lumie-email-service skill

You: "Deploy the latest code to production"
→ Automatically triggers lumie-deployment skill

You: "Check if the API service is running normally"
→ Automatically triggers lumie-deployment skill (service management)

You: "Restart Nginx"
→ Automatically triggers lumie-deployment skill
```

### Manual Invocation
If you need to explicitly specify a skill, mention it in your request:

```
"Use email service skill to send verification email"
"Use deployment skill to redeploy backend"
```

---

## 📚 Detailed Skill Information

### Lumie Email Service Skill

**Implementation Status:** ✅ Production Ready

**Server Info:**
- Server: 54.193.153.37
- Email Service: `/home/ubuntu/lumie_backend/app/services/email_service.py`
- Sender: lumie@yumo.org

**Quick Test:**
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37
cd /home/ubuntu/lumie_backend && source venv/bin/activate && python test_email.py
```

**Common Operations:**
1. Send test emails (3 test cases)
2. Integrate with signup endpoint (send verification email)
3. Integrate with invite endpoint (send invitation email)
4. Troubleshoot (403, missing files, etc.)

---

### Lumie Deployment Skill

**Implementation Status:** 🟢 All Services Running

**Server Info:**
- Server: 54.193.153.37
- Website: https://yumo.org
- API: https://yumo.org/api/v1

**Quick Deploy:**
```bash
# Website
scp -i ~/.ssh/Lumie_Key.pem -r ./website/* ubuntu@54.193.153.37:/home/ubuntu/website/

# API
cd lumie_backend && bash deploy.sh
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

**Common Operations:**
1. Deploy website/API
2. Restart services (Nginx, API, MongoDB)
3. View logs and status
4. SSL certificate management
5. Troubleshoot and rollback

---

## 🔧 Skill Development Guide

To create new skills or modify existing ones:

### Skill File Structure
```
.claude/skills/
├── README.md                          # This file
├── lumie-email-service/
│   └── SKILL.md                       # Email service skill
└── lumie-deployment/
    └── SKILL.md                       # Deployment management skill
```

### Required SKILL.md Sections
1. **Description** - Brief explanation
2. **When to Use** - Trigger conditions and keywords
3. **Prerequisites** - Requirements
4. **Instructions** - Detailed steps
5. **Examples** - Usage examples
6. **Error Handling** - Error solutions
7. **Safety Checks** - Safety guidelines

### Creating New Skills
```bash
# 1. Create directory
mkdir -p .claude/skills/my-new-skill

# 2. Create SKILL.md
touch .claude/skills/my-new-skill/SKILL.md

# 3. Write content following template (refer to existing skills)

# 4. Test if skill triggers correctly
```

---

## 🚦 Status

| Skill | Status | Last Updated | Server |
|-------|--------|--------------|--------|
| lumie-email-service | ✅ Ready | 2026-02-07 | 54.193.153.37 |
| lumie-deployment | 🟢 Active | 2026-02-07 | 54.193.153.37 |

---

## 📞 Related Documentation

### Email Service
- **Implementation:** `lumie_backend/app/services/email_service.py`
- **Test Script:** `lumie_backend/test_email.py`
- **Setup Guide:** `lumie_backend/EMAIL_SETUP_GUIDE.md`
- **Quick Start:** `lumie_backend/EMAIL_SETUP_COMPLETE.md`
- **Developer Reference:** `docs/gmail_send_with_lumie.md`

### Deployment
- **Deployment Guide:** `DEPLOYMENT.md`
- **Deploy Script:** `lumie_backend/deploy.sh`
- **Init Script:** `lumie_backend/init-server.sh`

---

## 💡 Usage Tips

### 1. Combine Skills
```
"Deploy backend and send a test email to verify email service"
→ Triggers deployment + email-service skills
```

### 2. Context Awareness
Claude Code remembers conversation context, allowing consecutive related operations:

```
You: "Deploy the latest code"
Claude: [Performs deployment...]

You: "Check service status"
Claude: [Checks API, Nginx, MongoDB status]

You: "Send a test email to verify"
Claude: [Runs test_email.py]
```

### 3. Quick Troubleshooting
```
"API is not accessible, help me troubleshoot"
→ Automatically checks service status, logs, port usage, etc.
```

---

**Created:** 2026-02-07
**Project:** Lumie Health App
**Server:** 54.193.153.37
