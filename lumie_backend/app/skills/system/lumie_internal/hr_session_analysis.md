---
skill_id: hr_session_analysis
title: Heart Rate Session Analysis
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [heart rate, hr, measurement session, bpm, pulse, cardiac, exercise heart rate, recovery]
keywords: [my heart rate, heart rate session, workout heart rate, exercise heart rate, resting heart rate, hr recovery, heart rate measurement, bpm, pulse, cardiac, heart performance, hr trend, heart rate history]
summary: Analyze completed heart rate measurement sessions, including duration, average/min/max BPM, time-series data, and trends across multiple sessions.
proactive_eligible: true
proactive_domain: cardiac
proactive_priority: 90
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    time_reference:
      type: string
      description: "last session | today | yesterday | this week | last 7 days | all"
    session_id:
      type: string
      description: "optional: specific session ID for detailed analysis"
    target_user_hint:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    data:
      type: object
---

# Purpose

Use this skill when the user asks about their heart rate during recorded measurement sessions (manual HR checks, exercise sessions, recovery measurements). Provides session summaries and detailed time-series analysis for cardio assessment.

# When To Use
- "Show me my heart rate sessions"
- "What was my heart rate during last workout?"
- "Show me my HR recovery"
- "Analyze my last 7 days of HR data"
- "What's my average heart rate been?"
- "How fast does my heart recover?"
- "Break down my last HR measurement"
- Parent asking about child's cardiac performance

# Do NOT Use When
- User wants current/real-time HR → use `ring_live_measure`
- User wants historical point-in-time HR readings → use `health_data_query` domain=heart_rate
- User wants to log a new HR measurement → use API directly

# Schema

See:
- [`HrSessionSummary` in models/hr_session.py](../../models/hr_session.py) — session overview
- [`HrSessionTimeseriesResponse` in models/hr_session.py](../../models/hr_session.py) — detailed time-series buckets

### Relevant fields for HR session analysis:
- `session_id` (string) — unique session identifier
- `started_at` (datetime ISO 8601) — when measurement began
- `ended_at` (datetime ISO 8601) — when measurement ended
- `duration_seconds` (integer) — total measurement duration
- `avg_bpm` (integer) — average BPM during session
- `min_bpm` (integer) — lowest BPM recorded
- `max_bpm` (integer) — highest BPM recorded
- `reading_count` (integer) — number of individual readings
- `created_at` (datetime) — when session was logged to server

### Time-series data (from buckets):
- `bucket_start` (datetime) — start of 5-minute bucket
- `bucket_end` (datetime) — end of 5-minute bucket
- `avg_bpm` (float) — average BPM in this bucket
- `min_bpm` (integer) — lowest BPM in bucket
- `max_bpm` (integer) — highest BPM in bucket
- `readings` (array) — individual readings with offsets from bucket start

# Runtime Rules
- `user_timezone`, `ZoneInfo`, `timezone`, `timedelta`, `datetime` are all pre-loaded — do NOT import them
- Use the `db` variable directly
- The `user_id` and `target_user_id` variables are pre-loaded

# Timezone: Computing Time Ranges
```python
local_tz = ZoneInfo(user_timezone)
today_local = datetime.now(local_tz).date()

# TODAY (sessions started since local midnight)
today_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc)
today_end_utc = today_start_utc + timedelta(days=1)

# YESTERDAY
yesterday_start_utc = today_start_utc - timedelta(days=1)
yesterday_end_utc = today_start_utc

# THIS WEEK (Mon–Sun)
days_since_monday = today_local.weekday()
week_start_local = today_local - timedelta(days=days_since_monday)
week_start_utc = datetime(week_start_local.year, week_start_local.month, week_start_local.day, tzinfo=local_tz).astimezone(timezone.utc)
week_end_utc = week_start_utc + timedelta(days=7)

# LAST 7 DAYS
seven_days_ago_utc = datetime.now(timezone.utc) - timedelta(days=7)
```

# Query Examples

## All Sessions for Time Period
```python
sessions = await db.hr_sessions.find({
    "user_id": target_user_id,
    "started_at": {"$gte": start_date_utc, "$lt": end_date_utc}
}).sort("started_at", -1).to_list(100)

# Sessions list contains: session_id, started_at, ended_at, duration_seconds, 
#                        avg_bpm, min_bpm, max_bpm, reading_count, created_at
```

## Detailed Time-Series for Single Session
```python
# Get session summary
session = await db.hr_sessions.find_one({
    "user_id": target_user_id,
    "session_id": session_id
})

# Get time-series buckets for this session
buckets = await db.hr_session_buckets.find({
    "user_id": target_user_id,
    "session_id": session_id
}).sort("bucket_start", 1).to_list(100)

# Each bucket has: bucket_start, bucket_end, count, avg_bpm, min_bpm, max_bpm, readings[]
# readings[] contains: t (offset in seconds), bpm
```

## HR Recovery Analysis
```python
# For sessions with before/after measurements
session = await db.hr_sessions.find_one({
    "user_id": target_user_id,
    "session_id": session_id
})

# Get first and last buckets
buckets = await db.hr_session_buckets.find({
    "user_id": target_user_id,
    "session_id": session_id
}).sort("bucket_start", 1).to_list(100)

if len(buckets) >= 2:
    initial_hr = buckets[0]["avg_bpm"]
    final_hr = buckets[-1]["avg_bpm"]
    recovery_delta = initial_hr - final_hr  # If positive, HR came down (good recovery)
    recovery_percentage = (recovery_delta / initial_hr) * 100 if initial_hr > 0 else 0
```

## HR Trends Across Sessions
```python
sessions = await db.hr_sessions.find({
    "user_id": target_user_id,
    "started_at": {"$gte": start_date_utc}
}).sort("started_at", 1).to_list(100)

# Calculate trends
avg_bpms = [s["avg_bpm"] for s in sessions]
if len(avg_bpms) > 1:
    overall_avg = sum(avg_bpms) / len(avg_bpms)
    trend = "increasing" if avg_bpms[-1] > avg_bpms[0] else "decreasing"
    trend_magnitude = avg_bpms[-1] - avg_bpms[0]
```

## Peak HR Events
```python
sessions = await db.hr_sessions.find({
    "user_id": target_user_id,
    "started_at": {"$gte": start_date_utc}
}).sort("started_at", -1).to_list(50)

# Find highest peak HRs
peak_events = [
    {
        "session_id": s["session_id"],
        "started_at": s["started_at"],
        "max_bpm": s["max_bpm"],
        "duration_minutes": s["duration_seconds"] // 60
    }
    for s in sessions
]
peak_events.sort(key=lambda x: x["max_bpm"], reverse=True)
```

# Output Guidance

## Summary — write for the user directly
- Session: "Your last HR session was **38 minutes** at an average of **112 bpm** (range 88–145). You hit a peak of **145 bpm**, suggesting moderate-to-high intensity effort."
- Multiple: "You logged **4 HR sessions** this week, averaging **118 bpm** across all sessions. Your peak was **156 bpm** on Wednesday."
- Trend: "Your average session HR has been trending up slightly (from 110 bpm last week to 118 bpm this week), suggesting increased intensity or reduced fitness."
- Recovery: "Your HR recovered **22 bpm** over your session (from 128 to 106), showing good recovery capacity."
- No data: "No HR sessions logged for that period yet."

Rules:
- Use bold for key metrics (duration, avg/min/max BPM, peaks)
- Context matters: 140 bpm is different meaning at rest vs. during sprint
- Mention intensity level when relevant (resting, moderate, high)
- Highlight recovery if measured
- Be encouraging when trends show improvement

## Data structure
Return clean, display-ready data:

```json
{
  "summary": "You completed 4 HR sessions this week, averaging 118 bpm with peak of 156 bpm. Your HR has been trending up, indicating increased training intensity.",
  "data": {
    "sessions": [
      {
        "session_id": "abc123",
        "started_at": "2026-04-10T15:30:00Z",
        "duration_minutes": 38,
        "avg_bpm": 112,
        "min_bpm": 88,
        "max_bpm": 145,
        "reading_count": 2280,
        "intensity_estimate": "moderate-high"
      }
    ],
    "metrics": {
      "sessions_count": 4,
      "avg_of_averages": 118,
      "highest_peak": 156,
      "lowest_trough": 82,
      "week_trend": "increasing"
    },
    "timeseries_sample": {
      "session_id": "abc123",
      "buckets": [
        {
          "bucket_start": "2026-04-10T15:30:00Z",
          "avg_bpm": 95,
          "min_bpm": 88,
          "max_bpm": 112
        }
      ]
    }
  }
}
```

Do NOT include internal IDs, raw readings arrays, or database metadata.

# Proactive Mode Guidance

When used in proactive checks, assess cardiovascular fitness and cardiac concerns:

## Resting HR Assessment
- **Nudge** if: resting HR consistently >85 bpm at rest (elevated resting rate, may indicate stress, fitness loss, or cardiac concern)
- **Nudge** if: resting HR jumped 15+ bpm unexpectedly (may indicate illness, overtraining, or stress)
- **Do not nudge** for: athletic users with naturally lower resting rates (45–60 bpm)

## Exercise HR Response
- **Nudge** if: max HR during exercise dropped significantly (20%+) vs. recent baseline (may indicate fatigue, deconditioning, or illness)
- **Nudge** if: HR fails to return to resting levels 10+ minutes post-exercise (poor recovery, concerning)
- **Do not nudge** for: expected variation with exercise intensity

## HR Recovery
- **Nudge** if: recovery rate is slow (HR doesn't drop 20+ bpm within 2 min post-exercise) AND user is not athletic
- **Nudge** if: recovery has worsened significantly (used to recover in 3 min, now takes 8+ min)
- **Do not nudge** for: expected post-exercise elevation

## Peak HR Concern
- **Nudge** if: peak HR exceeds 85–90% of age-predicted max repeatedly AND user is not training deliberately at high intensity
- **Nudge** if: any single peak HR >160 bpm in a user with known cardiac condition (flag for medical review)

## Chronic Condition Context
- Users with ICD-10 cardiac codes: Lower thresholds, more sensitive to HR irregularities
- Users post-surgery: May have restricted HR zones (follow protocol)
- Athletes: Different baseline expectations, focus on recovery metrics

# Failure Handling
- Retry on DB errors
- If no sessions found, return empty with note: "No HR sessions logged yet."
- Partial data acceptable (time-series may be incomplete)
- Never expose raw error messages
