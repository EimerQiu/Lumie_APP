---
skill_id: comprehensive_health_assessment
title: Comprehensive Health Assessment
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [health, sleep, activity, hrv, rhr, medication, tasks, walk_test, comprehensive, overall, report]
keywords: [health summary, recent condition, daughter health, overall health, how is she doing, how am I doing, weekly summary, health report, overall report, full report, comprehensive, everything, all health data, how have I been, how has she been, give me a summary]
summary: Multi-domain health report combining sleep, activity, walk test, and medication adherence. Use only for broad "how am I doing overall" questions — for single-domain queries (just sleep, just activity, etc.) use health_data_query instead.
proactive_eligible: true
proactive_domain: activity
proactive_priority: 80
proactive_mode: assessment
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
- Query from these collections: `profiles`, `activities`, `sleep_sessions`, `daily_steps`, `hr_readings`, `hrv_readings`, `temperature_readings`, `spo2_readings`, `tasks`, `walk_tests`
- Do NOT access `users` collection (contains auth secrets)
- Strip sensitive fields: `hashed_password`, `verification_token`, `device_token`, `_id`

# Data Scope and Structures

Use these collections and fields for each section:

- `sleep`
  - Source: `sleep_sessions`
  - Fields: `bedtime`, `wake_time`, `total_sleep_minutes`, `time_awake_minutes`, `stages`, `resting_heart_rate`, `sleep_quality_score`
- `activity`
  - Source: `activities` and `daily_steps`
  - `activities` fields: `activity_type_name`, `duration_minutes`, `intensity`, `avg_heart_rate`, `max_heart_rate`, `source`, `start_time`
  - `daily_steps` fields: `date_str`, `steps`, `exercise_time_seconds`, `distance_km`
- `hrv_rhr`
  - Source: `hrv_readings`, `hr_readings`, and sleep-derived `resting_heart_rate`
  - `hrv_readings` fields: `timestamp`, `hrv_ms`, `heart_rate_bpm`, `fatigue`, `systolic_mmhg`, `diastolic_mmhg`, `source`
  - `hr_readings` fields: `timestamp`, `bpm`
- `temperature`
  - Source: `temperature_readings`
  - Fields: `timestamp`, `temp1_c`, `temp2_c`, `temp3_c`
- `spo2`
  - Source: `spo2_readings`
  - Fields: `timestamp`, `spo2_percent`
- `medications`
  - Source: `tasks`
  - Relevant fields: `task_type`, `open_datetime`, `close_datetime`, `done`, `task_name`, `task_info`
- `walk_tests`
  - Source: `walk_tests`
  - Fields: `date`, `distance_meters`, `duration_seconds`, `avg_heart_rate`, `max_heart_rate`, `recovery_heart_rate`

Interpretation rules:

- Prefer `sleep_sessions.resting_heart_rate` for overnight recovery summaries.
- Use `hr_readings` when computing recent rolling HR metrics outside sleep sessions.
- Use `daily_steps` for day-level step totals; do not try to infer steps from `activities`.
- Treat `hrv_readings.systolic_mmhg` / `diastolic_mmhg` as ring-estimated wellness signals, not clinical cuff readings.
- Treat `temperature_readings` as ring/skin-adjacent temperature, not core body temperature.

# Execution Plan
1. Resolve target user from question context
2. Query the target user's profile for age, condition, timezone
3. Query sleep sessions from the requested time range
4. Query activities and daily_steps from the requested time range, aggregate by day
5. Query hrv_readings and hr_readings from the requested time range
6. Query temperature_readings and spo2_readings from the requested time range when relevant or available
7. Query tasks from the requested time range, compute adherence rate
8. Query walk test results if any exist in the range
9. Normalize all returned data into structured sections
10. Generate a combined assessment with trends and noteworthy issues

# Output Guidance
- Return structured sections: `summary`, `sleep`, `activity`, `hrv_rhr`, `temperature`, `spo2`, `medications`, `walk_tests`
- `summary` should be a 2-3 sentence natural language overview
- Each section should include key metrics and any notable trends
- Flag any concerning patterns (e.g., declining sleep quality, low task adherence)

Recommended section shapes:

- `sleep`
  - `latest_session`
  - `average_sleep_minutes`
  - `average_sleep_quality_score`
  - `average_resting_heart_rate`
  - `trend_notes`
- `activity`
  - `total_active_minutes`
  - `active_days`
  - `total_steps`
  - `average_daily_steps`
  - `activities`
  - `trend_notes`
- `hrv_rhr`
  - `latest_hrv`
  - `average_hrv_ms`
  - `latest_fatigue`
  - `recent_resting_heart_rate`
  - `recent_peak_heart_rate`
  - `estimated_blood_pressure`
- `temperature`
  - `latest_reading`
  - `highest_recent_temp_c`
  - `trend_notes`
- `spo2`
  - `latest_reading`
  - `lowest_recent_spo2_percent`
  - `trend_notes`
- `medications`
  - `adherence_rate`
  - `completed_count`
  - `missed_count`
  - `recent_misses`
- `walk_tests`
  - `latest_test`
  - `previous_test`
  - `distance_change_percent`

# Proactive Mode Guidance

When this skill is used in **proactive mode** (the advisor is autonomously checking whether to
send a nudge, not responding to a user message), evaluate the combined picture across all domains:

## Sleep
- **Nudge** if: quality score < 60, OR total sleep < 5 hours, OR resting HR is elevated
- **Nudge** if: sleep quality has declined for 2+ consecutive nights (trend, not a one-off)
- **Do not nudge** for a single average night

## Activity
- **Nudge** if: no activity for 3+ days AND user has a history of regular exercise
- **Nudge** if: weekly activity total has dropped more than 50% vs. the prior week
- **Do not nudge** for: occasional rest days or mildly reduced activity

## Medication Adherence
- **Nudge** if: adherence rate for medicine-type tasks is below 70% for the current week
- **Nudge** if: any medicine task has been missed for 2+ consecutive windows
- **Do not nudge** if adherence is above 80%

## Walk Test
- **Nudge** if: the most recent walk test distance has declined >10% vs. the prior test
- **Do not nudge** for: absence of new tests, or stable/improving results

## Combined Signals (escalate when multiple domains are poor)
- Two or more domains showing concerning patterns simultaneously is a stronger signal —
  nudge even if each domain alone would not quite meet the threshold
- Example: sleep score 62 (borderline) + no activity 2 days → nudge

## Chronic Condition Consideration
- If the user has an ICD-10 code, lower your threshold slightly — health signal changes
  carry more significance for someone managing a chronic condition
- Declining walk test + poor sleep together may indicate a condition flare-up — worth a nudge

## What NOT to Nudge About
- Everything is within normal range
- Data is missing for one domain but other domains look fine
- Upcoming tasks that haven't been missed yet
- Minor single-day fluctuations with no trend

# Failure Handling
- Retry if the DB script fails due to field mismatch or query error
- Fail immediately on permission denied or invalid ping
- If a collection has no data for the range, return that section as empty with a note, don't fail
