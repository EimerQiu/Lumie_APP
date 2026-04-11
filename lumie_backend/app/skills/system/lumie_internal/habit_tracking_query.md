---
skill_id: habit_tracking_query
title: Habit Tracking Query
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [habits, mood, energy, fatigue, wellness, daily, tracking, log]
keywords: [my mood, how am I feeling, energy level, fatigue, hunger, workload, how have I been, habit tracking, daily log, condition metric, wellness check, how's my energy, am I tired]
summary: Query daily habit and wellness tracking entries — mood, energy, fatigue, hunger, workload — for a specific date range or today. Provides snapshot of user's subjective wellness over time.
proactive_eligible: true
proactive_domain: wellness
proactive_priority: 55
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    time_reference:
      type: string
      description: "today | yesterday | this week | last 7 days | last 14 days | specific date | date range"
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

Use this skill when the user asks about their daily wellness habits, mood, energy levels, fatigue, hunger, or workload. Captures subjective health signals that complement objective ring data.

# When To Use
- "How have I been feeling this week?"
- "What was my mood yesterday?"
- "How's my energy level been?"
- "Show me my fatigue trends"
- "Check my daily wellness log"
- "How has my workload been?"
- "What was my hunger level today?"
- Parent asking about child's reported wellness

# Do NOT Use When
- User wants objective metrics (sleep, activity, HR) → use `health_data_query`
- User wants medication/task tracking → use `tasks_query`

# Schema

See [`HabitEntryResponse` in models/habit.py](../../models/habit.py)

### Relevant fields for habit queries:
- `date` (string, "YYYY-MM-DD") — local date of the entry
- `mood` (integer 1–5, optional) — 1=very bad, 5=great
- `energy` (string enum, optional) — "low", "moderate", "high"
- `hunger` (string enum, optional) — "low", "normal", "high"
- `workload` (string enum, optional) — "light", "moderate", "heavy"
- `fatigue` (string enum, optional) — "low", "moderate", "high"
- `condition_metric` (float, optional) — user-defined metric (e.g., pain level, blood pressure)
- `updated_at` (datetime ISO) — when entry was last updated

# Runtime Rules
- `user_timezone`, `ZoneInfo`, `timezone`, `timedelta`, `datetime` are all pre-loaded — do NOT import them
- Use the `db` variable directly
- The `user_id` and `target_user_id` variables are pre-loaded

# Timezone: Computing Date Ranges
```python
local_tz = ZoneInfo(user_timezone)
today_local = datetime.now(local_tz).date()

# TODAY
today_str = today_local.isoformat()  # "2026-04-10"

# YESTERDAY
yesterday_str = (today_local - timedelta(days=1)).isoformat()

# THIS WEEK (Mon–Sun in user's timezone)
days_since_monday = today_local.weekday()
week_start_local = today_local - timedelta(days=days_since_monday)
week_end_local = week_start_local + timedelta(days=7)

# LAST 7 DAYS
seven_days_ago_str = (today_local - timedelta(days=7)).isoformat()

# LAST 14 DAYS
fourteen_days_ago_str = (today_local - timedelta(days=14)).isoformat()
```

# Query Examples

## Today's Habit Entry
```python
today_str = datetime.now(ZoneInfo(user_timezone)).date().isoformat()
entry = await db.habits.find_one({
    "user_id": target_user_id,
    "date": today_str
})
if entry:
    # Found today's entry
    mood = entry.get("mood")  # 1-5 or None
    energy = entry.get("energy")  # "low" | "moderate" | "high" or None
    fatigue = entry.get("fatigue")
else:
    # No entry logged today
    pass
```

## Last 7 Days of Habit Entries
```python
local_tz = ZoneInfo(user_timezone)
today_local = datetime.now(local_tz).date()
start_date = (today_local - timedelta(days=7)).isoformat()
end_date = today_local.isoformat()

entries = await db.habits.find({
    "user_id": target_user_id,
    "date": {"$gte": start_date, "$lte": end_date}
}).sort("date", -1).to_list(7)
```

## Mood Trend Over Time
```python
# Get all entries for a user (or limit to last N days)
entries = await db.habits.find({
    "user_id": target_user_id,
    "date": {"$gte": start_date, "$lte": end_date}
}).sort("date", 1).to_list(100)

# Extract moods
moods = [e.get("mood") for e in entries if e.get("mood")]
if moods:
    avg_mood = sum(moods) / len(moods)
    min_mood = min(moods)
    max_mood = max(moods)
```

## Energy and Fatigue Patterns
```python
entries = await db.habits.find({
    "user_id": target_user_id,
    "date": {"$gte": start_date, "$lte": end_date}
}).sort("date", 1).to_list(100)

# Count energy levels
energy_counts = {"low": 0, "moderate": 0, "high": 0}
for e in entries:
    energy = e.get("energy")
    if energy and energy in energy_counts:
        energy_counts[energy] += 1

# Identify fatigue patterns
high_fatigue_days = [
    e["date"] for e in entries
    if e.get("fatigue") == "high"
]
```

# Output Guidance

## Summary — write for the user directly
- Today: "You logged a mood of **4/5** and **moderate** energy. Fatigue is **low**."
- Week: "Your mood averaged **3.8/5** over the past week, trending upward. Energy is mostly **moderate** with 2 **high** days."
- Trend: "Your fatigue has improved from high 3 days ago to low today — great sign of recovery."
- No data: "No habit entries logged for that period yet."

Rules:
- Be conversational, not clinical
- Highlight positive trends and improvements
- Reference specific dates when relevant
- Acknowledge missing entries without being judgmental

## Data structure
Return clean, display-ready data:

```json
{
  "summary": "Your mood has been trending upward this week, averaging 3.8/5. Energy levels are mostly moderate with occasional high days.",
  "data": {
    "entries": [
      {
        "date": "2026-04-10",
        "mood": 4,
        "energy": "moderate",
        "hunger": "normal",
        "workload": "moderate",
        "fatigue": "low",
        "condition_metric": null,
        "updated_at": "2026-04-10T18:30:00Z"
      }
    ],
    "metrics": {
      "avg_mood": 3.8,
      "mood_range": [3, 5],
      "days_logged": 7,
      "most_common_energy": "moderate",
      "high_fatigue_days": 2
    }
  }
}
```

Do NOT include internal IDs or database metadata.

# Proactive Mode Guidance

When used in proactive checks, flag wellness concerns:

## Mood
- **Nudge** if: mood consistently <3 over last 7+ days (suggests low mood)
- **Nudge** if: sharp downward trend (mood dropped 2+ points in 2 days)
- **Do not nudge** for: single low mood entry or normal fluctuations

## Energy
- **Nudge** if: energy "low" for 4+ consecutive days (sustained fatigue)
- **Nudge** if: contrasts sharply with recent activity (low energy despite high activity)
- **Do not nudge** for: occasional low days without pattern

## Fatigue
- **Nudge** if: fatigue "high" for 3+ days AND avg_sleep < 6 hours (combined signal)
- **Nudge** if: fatigue remains high despite good sleep (suggests overtraining or stress)
- **Do not nudge** for: single high fatigue day post-workout

## Workload
- **Nudge** if: workload "heavy" for 5+ consecutive days without rest days
- **Do not nudge** for: occasional heavy days (normal)

## Chronic Condition Context
- Adjust thresholds for users with ICD-10 codes: fatigue and mood have higher significance
- Correlate with activity and sleep data for full context

# Failure Handling
- Retry on DB errors
- If no entries found, return empty with friendly note — don't fail
- If partial data available (some fields missing), return what's available
- Never expose raw database errors to user
