---
skill_id: workout_exercise_query
title: Workout & Exercise Query
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [workout, exercise, strength, session, personal record, pr, sets, reps, volume, gym]
keywords: [my workouts, exercise log, strength training, sets and reps, personal record, pr, how many workouts, workout history, session details, exercise performance, volume, max weight, lifted, trained, gym session, workout progress]
summary: Query completed workout sessions with exercise details, sets/reps, personal records, and performance metrics. Supports time-range queries and individual session lookups.
proactive_eligible: true
proactive_domain: strength
proactive_priority: 75
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    time_reference:
      type: string
      description: "today | yesterday | this week | last 7 days | last 14 days | this month | all"
    exercise_filter:
      type: string
      description: "optional: exercise name or muscle group to filter by"
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

Use this skill when the user asks about their workout history, exercise performance, sets/reps, personal records, or workout progression. Provides detailed session logs with exercise performance metrics.

# When To Use
- "What did I work out this week?"
- "Show me my bench press history"
- "How many workouts have I done?"
- "What was my heaviest deadlift?"
- "Break down my last workout session"
- "How many sets did I do for squats?"
- "Did I hit any PRs recently?"
- "Show my chest workout sessions"
- Parent asking about child's exercise progress

# Do NOT Use When
- User wants activity summary (ring detected activities) → use `health_data_query` domain=activity
- User wants workout templates (not sessions) → document separately
- User wants advice on progressive overload → use advisor directly

# Schema

See:
- [`WorkoutSession` in models/workout.py](../../models/workout.py) — completed workout logs
- [`CompletedExercise` in models/workout.py](../../models/workout.py) — exercise details within session
- [`PersonalRecord` in models/workout.py](../../models/workout.py) — PR records

### Relevant fields for workout queries:
- `session_id` (string) — unique session identifier
- `started_at` (datetime ISO 8601) — when workout began
- `ended_at` (datetime ISO 8601) — when workout ended
- `duration_seconds` (integer) — total workout duration
- `exercises` (array of CompletedExercise objects)
  - `exercise_name` (string) — name of exercise
  - `sets` (array of CompletedSet objects)
    - `actual_reps` (integer) — reps completed
    - `actual_weight` (float, optional) — weight used
    - `status` (string) — "completed", "failed", "pr", "skipped"
    - `is_pr` (boolean) — marks personal record
- `total_sets` (integer) — total sets in session
- `total_reps` (integer) — total reps completed
- `total_volume` (float) — sum(weight × reps) across all sets
- `prs` (array) — list of PRs achieved in this session
- `heart_rate_avg` (integer, optional) — average HR during workout
- `heart_rate_max` (integer, optional) — peak HR during workout
- `notes` (string, optional) — session notes

# Runtime Rules
- `user_timezone`, `ZoneInfo`, `timezone`, `timedelta`, `datetime` are all pre-loaded — do NOT import them
- Use the `db` variable directly
- The `user_id` and `target_user_id` variables are pre-loaded

# Timezone: Computing Date Ranges
```python
local_tz = ZoneInfo(user_timezone)
today_local = datetime.now(local_tz).date()

# TODAY (sessions started since local midnight)
today_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc)
today_end_utc = today_start_utc + timedelta(days=1)

# THIS WEEK (Mon–Sun)
days_since_monday = today_local.weekday()
week_start_local = today_local - timedelta(days=days_since_monday)
week_start_utc = datetime(week_start_local.year, week_start_local.month, week_start_local.day, tzinfo=local_tz).astimezone(timezone.utc)
week_end_utc = week_start_utc + timedelta(days=7)

# LAST 7 DAYS
seven_days_ago_utc = datetime.now(timezone.utc) - timedelta(days=7)

# LAST 14 DAYS
fourteen_days_ago_utc = datetime.now(timezone.utc) - timedelta(days=14)

# THIS MONTH
month_start_local = today_local.replace(day=1)
month_start_utc = datetime(month_start_local.year, month_start_local.month, month_start_local.day, tzinfo=local_tz).astimezone(timezone.utc)
month_end_utc = (month_start_local.replace(day=28) + timedelta(days=4)).replace(day=1)
month_end_utc = datetime(month_end_utc.year, month_end_utc.month, month_end_utc.day, tzinfo=local_tz).astimezone(timezone.utc)
```

# Query Examples

## Sessions This Week
```python
sessions = await db.workout_sessions.find({
    "user_id": target_user_id,
    "started_at": {"$gte": week_start_utc, "$lt": week_end_utc}
}).sort("started_at", -1).to_list(50)
```

## Sessions for a Specific Exercise
```python
# Note: exercises are nested, so we need to search within array
sessions = await db.workout_sessions.find({
    "user_id": target_user_id,
    "started_at": {"$gte": start_date_utc, "$lt": end_date_utc},
    "exercises.exercise_name": {"$regex": "bench", "$options": "i"}
}).sort("started_at", -1).to_list(50)
```

## Single Session with Full Details
```python
session = await db.workout_sessions.find_one({
    "user_id": target_user_id,
    "session_id": session_id
})

if session:
    # Iterate exercises and sets
    for exercise in session.get("exercises", []):
        exercise_name = exercise["exercise_name"]
        for set_obj in exercise.get("sets", []):
            reps = set_obj.get("actual_reps")
            weight = set_obj.get("actual_weight")
            is_pr = set_obj.get("is_pr", False)
```

## Recent Personal Records
```python
# PRs are stored in session.prs array
sessions_with_prs = await db.workout_sessions.find({
    "user_id": target_user_id,
    "started_at": {"$gte": start_date_utc},
    "prs": {"$exists": True, "$ne": []}
}).sort("started_at", -1).to_list(50)

all_prs = []
for session in sessions_with_prs:
    for pr in session.get("prs", []):
        all_prs.append({
            "exercise": pr.get("exercise_name"),
            "pr_type": pr.get("pr_type"),  # "max_weight", "max_reps", "max_volume"
            "value": pr.get("value"),
            "achieved_at": session.get("started_at")
        })
```

## Workout Volume Trend
```python
sessions = await db.workout_sessions.find({
    "user_id": target_user_id,
    "started_at": {"$gte": start_date_utc, "$lt": end_date_utc}
}).sort("started_at", 1).to_list(100)

# Calculate daily volume
volume_by_date = {}
for session in sessions:
    date = session["started_at"].date().isoformat()
    total_volume = session.get("total_volume", 0)
    if date not in volume_by_date:
        volume_by_date[date] = 0
    volume_by_date[date] += total_volume
```

# Output Guidance

## Summary — write for the user directly
- Week overview: "You completed **5 workouts** this week with **312 total reps** and **4,280 lbs** of volume. You hit **2 PRs** — great progress!"
- Exercise focus: "You trained **chest** 3 times last week, averaging **18 sets** per session. Your bench press max is now **185 lbs** (up from 175 last month)."
- Single session: "Your last workout was **62 minutes** of leg day with **4 exercises, 16 sets, 68 reps, 2,840 lbs volume**. Average HR was **132 bpm**."
- No data: "No workout sessions logged for that period yet."

Rules:
- Use bold for key metrics (session count, PRs, volume, weight)
- Compare to recent history when possible ("up from X")
- Highlight PRs explicitly
- Reference muscle groups or exercise names when contextual
- Show duration in minutes for readability

## Data structure
Return clean, display-ready data:

```json
{
  "summary": "You completed 5 workouts this week averaging 62 minutes each, with total volume of 4,280 lbs and 2 personal records.",
  "data": {
    "sessions": [
      {
        "session_id": "abc123",
        "date": "2026-04-10",
        "template_name": "Chest Day",
        "duration_minutes": 62,
        "exercises": [
          {
            "exercise_name": "Bench Press",
            "sets_completed": 4,
            "best_weight": 185,
            "total_reps": 18,
            "is_pr": false
          }
        ],
        "total_sets": 16,
        "total_reps": 68,
        "total_volume": 2840,
        "prs": [
          {
            "exercise": "Bench Press",
            "type": "max_weight",
            "value": 185
          }
        ],
        "heart_rate": {
          "avg": 132,
          "max": 165
        }
      }
    ],
    "metrics": {
      "sessions_count": 5,
      "avg_duration_minutes": 62,
      "total_volume": 4280,
      "prs_count": 2,
      "total_sets": 80,
      "total_reps": 340
    }
  }
}
```

Do NOT include internal IDs or raw database documents.

# Proactive Mode Guidance

When used in proactive checks, assess workout consistency and progression:

## Workout Frequency
- **Nudge** if: no workouts in last 7 days AND user's baseline shows 3+ weekly sessions (motivational check-in)
- **Nudge** if: frequency dropped >50% vs. prior 2 weeks (sudden drop may indicate injury or motivation issues)
- **Do not nudge** for: scheduled rest week, deload week

## Progressive Overload
- **Nudge** if: volume/weight stagnant for 2+ weeks on a lift that was progressing
- **Nudge** if: sets/reps trending down sharply (suggests fatigue or form issues)
- **Do not nudge** for: normal fluctuation or intentional deload

## Performance Metrics
- **Nudge** if: avg HR during workouts climbing consistently (may indicate overtraining or deconditioning)
- **Nudge** if: duration shortened by >30% recent (may indicate incomplete sessions)

## Personal Records
- **Do not nudge** for: healthy PR progression (celebrate instead)

# Failure Handling
- Retry on DB errors
- If no sessions found, return empty with note — expected for new users
- Partial data acceptable (some sessions may lack HR data, etc.)
- Never expose raw database errors to user
