---
skill_id: gmail_inbox_check
title: Gmail Inbox Check
capability_id: email_read
runtime_type: browser
requires_ping: false
requires_credentials: true
target_system: email
tags: [email, gmail, inbox, unread, check, browser]
keywords: [check email, gmail, inbox, unread emails, new messages, email count, what emails, mail check]
summary: Log into Gmail and check the user's inbox for unread messages, recent emails, and email count.
allowed_connectors: [browser_skill_runtime]
input_schema:
  type: object
  properties:
    query:
      type: string
      description: Optional email search query (e.g., 'from:school', 'subject:homework'). Defaults to unread emails.
output_schema:
  type: object
  properties:
    summary:
      type: string
    unread_count:
      type: integer
    total_count:
      type: integer
    emails:
      type: array
      items:
        type: object
        properties:
          from:
            type: string
          subject:
            type: string
          date:
            type: string
          preview:
            type: string
---

# Purpose
Use this skill when the user asks to check their Gmail inbox, count unread emails, or find recent messages.

# When To Use
- User asks "check my email"
- User asks "do I have any new emails?"
- User asks "how many unread emails do I have?"
- User asks to search for emails from a specific sender or topic
- Parent asks about their child's emails

# Required Inputs
- query (optional): Gmail search query string (e.g., 'is:unread', 'from:teacher@school.com')
- Default if not provided: 'is:unread' (show unread emails only)

# Runtime Rules
- Use `browser` runtime
- Requires stored credentials: username, password (no base_url needed — always uses https://mail.google.com)
- For Gmail accounts with 2FA enabled, use app-specific password instead of account password
- Read-only operation; no sending, deleting, or marking

# Connector Rules
- Use Playwright browser session for automation
- Set browser viewport to 1920x1080 for reliable element detection
- Wait for Gmail to fully load (check for inbox label visibility)
- Handle potential reCAPTCHA (screenshot and fail gracefully)

# Execution Plan
**CRITICAL: Gmail has a TWO-STEP login process with page navigation between steps.**

1. Initialize browser and navigate to https://mail.google.com/mail
2. **Wait 2 seconds** for login page to fully load
3. Wait for email input field to appear (selector: `input#identifierId` or `input[type='email']`)
4. Fill email field with username
5. Click the "Next" button to submit email
6. **Wait 3-5 seconds** for Gmail to redirect to password page (this is critical - page navigation takes time)
7. Wait for password input field to appear (selector: `input[type='password']`)
8. Fill password field
9. Click the "Next" button to submit password
10. **Wait 5 seconds** for Gmail inbox to load
11. Wait for inbox to be visible (selector: `div[role="main"]` or "[data-view-name='INBOX']")
12. Wait 2 more seconds for all emails to render
13. Find Gmail's search box (usually top of page)
14. Click the search box
15. Type the query (default: `is:unread`)
16. Press Enter to search
17. Extract email list:
    - For each visible email: get sender, subject, date, preview
    - Limit to first 10 emails
18. Count unread emails (look for badge with number)
19. Close browser
20. Return results as JSON with summary

# Email Extraction Selectors
Gmail's interface structure (for LLM reference):

## Login Page Selectors
- Email input: `input#identifierId` or `input[type='email']`
- Next button (after email): `button` or `div[role='button']` containing "Next" text
- Password input: `input[type='password']` or `input[aria-label*='password']` or `input[name='password']`
- Next button (after password): `button` or `div[role='button']` containing "Next" text

## Inbox Page Selectors
- Email list container: div[role="main"]
- Email row: span[role="option"] or tr (table row)
- Sender name: Within email row, extract text before dash/subject
- Subject line: Within email row, find the main text
- Email preview: Text snippet after subject
- Date: Right side of email row, smaller text
- Unread count badge: On Inbox label (number in parenthesis)

# Output Guidance
- Return `unread_count`: Total unread emails (from badge or count)
- Return `total_count`: Total emails in mailbox (if visible)
- Return `emails` as array: [{from, subject, date, preview}]
  - Sender: "John Doe" or "john@example.com"
  - Subject: Exact subject line (max 100 chars)
  - Date: "Yesterday", "3 days ago", or "Jan 15"
  - Preview: First 80 characters of email body
- Provide a concise summary: "You have 5 unread emails. Most recent from..."
- Sort emails by date descending (newest first)

# Failure Handling
- If login fails (wrong credentials): Mark credential as invalid and fail
- If 2FA is detected (phone verification screen): Take screenshot and fail with message "2FA enabled. Use app-specific password in Advisor settings."
- If reCAPTCHA appears: Screenshot and fail with message "reCAPTCHA detected. Try again in a few minutes."
- If Gmail interface doesn't load after 15 seconds: Retry once, then fail
- If search query returns no results: Return empty array with summary "No emails found matching query"
- On partial failure (loaded but inbox unreadable): Return best-effort results with error note

# Browser Best Practices
- Use explicit waits (max 15 seconds per wait)
- Scroll carefully; Gmail loads emails lazily
- Don't click on individual emails (read-only)
- Handle cases where Gmail may load ads or promotional banners
- Clear any modal dialogs that might appear on first login
