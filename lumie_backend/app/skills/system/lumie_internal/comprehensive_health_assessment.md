---
skill_id: comprehensive_health_assessment
title: Comprehensive Health Assessment
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [health, sleep, activity, hrv, rhr, medication, tasks, walk_test]
keywords: [health summary, recent condition, daughter health, overall health, how is she doing, how am I doing, weekly summary, health report]
summary: Query sleep, activity, HRV, RHR, walk test, and medication/task adherence for a target user and produce a combined health assessment.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    target_user_hint:
      type: string
    time_range:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    sleep:
      type: object
    activity:
      type: object
    hrv_rhr:
      type: object
    medications:
      type: object
    walk_tests:
      type: object
---

# Purpose
Use this skill when the user asks for an overall health view that spans multiple Lumie data domains. This is the go-to skill for broad health questions like "how has my daughter been doing?" or "give me a health summary."

# When To Use
- The user asks how they or their child have been doing recently
- The question requires combining sleep, activity, HRV, RHR, and medication/task adherence
- Parent asks about a team member's overall health
- Any request for a comprehensive or multi-domain health report

# Required Inputs
- target user hint (may be implicit from context — "my daughter", "me", etc.)
- requested time range (default to last 7 days if not specified)

# Runtime Rules
- Use `lumie_db` runtime
- Must include the requester's ping from this skill's credential record
- All target-user access must be validated by `lumie_db_connector`

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Query from these collections: `profiles`, `activities`, `sleep_sessions`, `tasks`, `walk_tests`
- Do NOT access `users` collection (contains auth secrets)
- Strip sensitive fields: `hashed_password`, `verification_token`, `device_token`, `_id`

# Execution Plan
1. Resolve target user from question context
2. Query the target user's profile for age, condition, timezone
3. Query activities from the requested time range, aggregate by day
4. Query sleep sessions from the requested time range
5. Query tasks from the requested time range, compute adherence rate
6. Query walk test results if any exist in the range
7. Normalize all returned data into structured sections
8. Generate a combined assessment with trends and noteworthy issues

# Output Guidance
- Return structured sections: `summary`, `sleep`, `activity`, `medications`, `walk_tests`
- `summary` should be a 2-3 sentence natural language overview
- Each section should include key metrics and any notable trends
- Flag any concerning patterns (e.g., declining sleep quality, low task adherence)

# Failure Handling
- Retry if the DB script fails due to field mismatch or query error
- Fail immediately on permission denied or invalid ping
- If a collection has no data for the range, return that section as empty with a note, don't fail
