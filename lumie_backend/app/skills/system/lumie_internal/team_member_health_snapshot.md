---
skill_id: team_member_health_snapshot
title: Team Member Health Snapshot
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [team, member, health, parent, admin, snapshot]
keywords: [team member, my daughter, my son, my child, member health, team health, how is my kid]
summary: Quick health snapshot for a specific team member, accessible only by team admins/parents.
proactive_eligible: true
proactive_domain: team_followup
proactive_priority: 60
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    target_user_hint:
      type: string
    team_id:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    member_profile:
      type: object
    recent_sleep:
      type: object
    recent_activity:
      type: object
    recent_recovery:
      type: object
    task_adherence:
      type: object
---

# Purpose
Use this skill when a parent or team admin asks about a specific team member's health. This is a lighter version of comprehensive_health_assessment, focused on a quick snapshot.

# When To Use
- Parent asks "how is my daughter doing?"
- Team admin checks on a specific member
- Quick health check for a team member

# Required Inputs
- target user hint (must resolve to a team member)
- team_id (may be inferred from context)

# Runtime Rules
- Use `lumie_db` runtime
- Requester MUST be a team admin of the target user's team
- The connector will verify admin relationship

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Query from: `profiles`, `team_members`, `sleep_sessions`, `activities`, `daily_steps`, `hrv_readings`, `tasks`
- Only access data within the team scope
- Task queries must include team_id filter

# Collection Schemas

This snapshot queries ring-synced data from these collections:

- `profiles` — [`UserProfile` / `ProfileInDB` in models/user.py](../../models/user.py)
- `team_members` — [`TeamMember` in models/team.py](../../models/team.py)
- `sleep_sessions` — [`SleepSessionResponse` in models/sleep.py](../../models/sleep.py)
- `activities` — [`ActivityRecord` in models/activity.py](../../models/activity.py)
- `daily_steps` — [`DailyStepRecord` / `DailyStepResponse` in models/steps.py](../../models/steps.py)
- `hrv_readings` — [`HrvReadingResponse` in models/hrv.py](../../models/hrv.py)
- `tasks` — [`TaskResponse` in models/task.py](../../models/task.py)

### Relevant fields per domain:

- From `profiles`: `name`, `age`, `icd10_code`, `timezone`
- From `sleep_sessions`: `bedtime`, `wake_time`, `total_sleep_minutes`, `resting_heart_rate`, `sleep_quality_score`
- From `activities`: `activity_type_name`, `duration_minutes`, `intensity`, `start_time`
- From `daily_steps`: `date_str`, `steps`, `exercise_time_seconds`, `distance_km`
- From `hrv_readings`: `timestamp`, `hrv_ms`, `fatigue`, `heart_rate_bpm`, `systolic_mmhg`, `diastolic_mmhg`
- From `tasks`: `task_name`, `task_type`, `open_datetime`, `close_datetime`, `completed_at`

### Data interpretation rules:

- Prefer the latest `sleep_sessions` record for overnight snapshot
- Use `daily_steps` for daily totals; do not infer steps from `activities`
- Blood-pressure from `hrv_readings` is ring-estimated, not clinical
- If any section missing data, return as empty with note (don't omit)

# Execution Plan
1. Verify requester is admin of the target user's team
2. Get target user's profile
3. Get the most recent sleep session and last 3 days of sleep trend if available
4. Get recent activities and last 3 days of daily_steps
5. Get the latest HRV/recovery reading if available
6. Get today's task adherence
7. Return a concise snapshot

# Output Guidance
- Keep it brief and parent-friendly
- Highlight any concerns (missed medications, low activity)
- Include task completion rate for recent days
- Use a stable object shape:
  - `member_profile`
  - `recent_sleep`
  - `recent_activity`
  - `recent_recovery`
  - `task_adherence`

Recommended field examples:

- `recent_sleep`
  - `latest_bedtime`
  - `latest_wake_time`
  - `latest_total_sleep_minutes`
  - `latest_sleep_quality_score`
  - `latest_resting_heart_rate`
- `recent_activity`
  - `today_steps`
  - `today_active_minutes`
  - `recent_activities`
- `recent_recovery`
  - `latest_hrv_ms`
  - `latest_fatigue`
  - `latest_estimated_bp`
- `task_adherence`
  - `today_completion_rate`
  - `missed_medicine_tasks`
  - `pending_tasks`

# Failure Handling
- Fail immediately if not a team admin
- Retry on query errors
