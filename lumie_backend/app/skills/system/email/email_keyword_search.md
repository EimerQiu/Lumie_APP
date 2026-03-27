---
skill_id: email_keyword_search
title: Email Keyword Search
capability_id: email_read
runtime_type: external_api
requires_ping: false
requires_credentials: true
target_system: email
tags: [email, inbox, search, message]
keywords: [email, inbox, unread, keyword, school email, reminder email, check email, mail]
summary: Search the user's email inbox for messages matching a keyword or topic and summarize the relevant results.
allowed_connectors: [email_connector]
input_schema:
  type: object
  properties:
    keyword:
      type: string
    time_range:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    messages:
      type: array
---

# Purpose
Use this skill when the user asks the advisor to check their email for a topic, sender, or recent message.

# When To Use
- The user asks whether they received an email about something
- The user asks Advisor to search the inbox
- "Check my email for..." or "Did I get an email from..."

# Required Inputs
- keyword or topic
- optional time range

# Runtime Rules
- Use `external_api` runtime
- Requires stored credentials or an authorized email connection
- Only read access; no sending or deleting

# Connector Rules
- Use the email connector only
- Return matched messages in structured form
- Limit results to most recent 10 matches

# Execution Plan
1. Search the inbox using the keyword and optional time constraint
2. Fetch a small list of relevant messages (max 10)
3. Summarize the matching results

# Output Guidance
- Return sender, subject, date, and short preview for each message
- Provide a concise summary first
- Do not expose full email bodies (privacy)

# Failure Handling
- Retry on transient connector failures
- Fail directly if credentials are missing or revoked
