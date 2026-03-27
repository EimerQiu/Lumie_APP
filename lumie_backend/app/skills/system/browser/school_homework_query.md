---
skill_id: school_homework_query
title: School Homework Query
capability_id: browser_portal_access
runtime_type: browser
requires_ping: false
requires_credentials: true
target_system: school_portal
tags: [school, homework, assignments, portal]
keywords: [homework, assignment, due date, school portal, classwork, school work, what's due]
summary: Log into the user's school portal and retrieve homework or assignments due soon.
allowed_connectors: [browser_skill_runtime]
input_schema:
  type: object
  properties:
    time_range:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    assignments:
      type: array
---

# Purpose
Use this skill when the user asks about homework, assignments, or due dates from their school portal.

# When To Use
- The user asks what homework is due
- The user asks whether they have assignments today or this week
- Parent asks about their child's homework

# Required Inputs
- requested time range (default: this week)

# Runtime Rules
- Use `browser` runtime
- Requires stored credentials (base_url, username, password) for this skill
- The credential's `notes` field may contain navigation hints

# Connector Rules
- Use Playwright browser session
- The runtime should log in with saved username/password
- Follow selectors defined for this portal type
- Take screenshots on failure for debugging

# Execution Plan
1. Load credential and `base_url`
2. Open login page
3. Log in with stored credentials
4. Navigate to the homework/assignments section (use notes for hints)
5. Extract assignment title, course, due date, and status
6. Close browser session

# Output Guidance
- Return `assignments` as a list: [{title, course, due_date, status}]
- Provide a concise user-facing summary
- Sort by due date ascending

# Failure Handling
- Retry if selectors are missing or navigation fails (max 1 retry)
- Mark the credential invalid if login is rejected by the site
- Return screenshot path and failed step on error
