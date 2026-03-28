---
skill_id: health_data_query
title: Health Data Query
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [sleep, activity, exercise, walk test, rest day, heart rate, hrv, steps, health, fitness]
keywords: [sleep, slept, sleeping, last night, bedtime, wake up, sleep quality, sleep score, sleep hours, deep sleep, rem sleep, light sleep, how did I sleep, sleep data, activity, activities, exercise, steps, workout, how active, calories burned, walk test, 6 minute walk, walking test, heart rate, resting heart rate, hrv, heart rate variability, rest day, rest days, recovery, how many rest days, active days, fitness data, health data, how was my, how am I doing, my health, my activity, my sleep]
summary: Query focused health data for a single domain — sleep sessions, activity records, walk tests, or rest days. Use this for specific health metric questions, not broad multi-domain summaries.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    domain:
      type: string
      description: "sleep | activity | walk_test | rest_days"
    time_reference:
      type: string
      description: "last night | today | yesterday | this week | last 7 days | specific date"
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
Use this skill when the user asks a focused question about one health domain: sleep, physical activity, walk test results, or rest days. The schema already describes all collection fields — write queries directly from it.

# When To Use
- "How did I sleep last night?"
- "How many hours did I sleep this week?"
- "What was my sleep quality score?"
- "How active was I today / this week?"
- "Show me my activity history"
- "What was my heart rate during exercise?"
- "When was my last walk test?"
- "How many rest days have I had?"
- "What's my resting heart rate?"
- Parent asking about their child's sleep or activity

# Do NOT Use When
- User wants tasks/medications → use `tasks_query`
- User wants a combined health report across multiple domains → use `comprehensive_health_assessment`

# Runtime Rules
- `user_timezone`, `ZoneInfo`, `timezone`, `timedelta`, `datetime` are all pre-loaded — do NOT import them
- Use the `db` variable directly — collections are in the schema

# Timezone: Computing Time Ranges
```python
local_tz = ZoneInfo(user_timezone)
today_local = datetime.now(local_tz).date()

# last night / yesterday
yesterday_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc) - timedelta(days=1)
yesterday_end_utc = yesterday_start_utc + timedelta(days=1)

# today
today_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc)
today_end_utc = today_start_utc + timedelta(days=1)

# last 7 days
week_end_utc = datetime.now(timezone.utc)
week_start_utc = week_end_utc - timedelta(days=7)
```

# Domain Query Examples

## Sleep (`sleep_sessions` collection)
```python
# Last night's sleep
session = await db.sleep_sessions.find_one(
    {"user_id": target_user_id, "bedtime": {"$gte": yesterday_start_utc, "$lt": yesterday_end_utc}},
    sort=[("bedtime", -1)]
)
# Fields: bedtime, wake_time, total_sleep_minutes, time_awake_minutes,
#         stages ([{stage, duration_minutes, percentage}]), resting_heart_rate,
#         sleep_quality_score (0-100), source
```

## Activity (`activities` collection)
```python
# This week's activities
acts = await db.activities.find({
    "user_id": target_user_id,
    "start_time": {"$gte": week_start_utc.isoformat(), "$lt": week_end_utc.isoformat()}
}).to_list(100)
# Fields: activity_type_name, duration_minutes, intensity, avg_heart_rate,
#         max_heart_rate, source, start_time
```

## Walk Test (`walk_tests` collection)
```python
# Most recent walk test
test = await db.walk_tests.find_one(
    {"user_id": target_user_id},
    sort=[("date", -1)]
)
# Fields: date (YYYY-MM-DD), distance_meters, duration_seconds,
#         avg_heart_rate, max_heart_rate, recovery_heart_rate
```

## Rest Days (`rest_days` collection — check schema for exact fields)
```python
rest = await db.rest_days.find(
    {"user_id": target_user_id}
).sort("date", -1).to_list(30)
```

# Output Guidance

## Summary — write for the user directly
- Sleep: "You slept **7h 20min** last night with a quality score of **82/100**. You got 28% deep sleep, which is great for recovery."
- Activity: "You were active **4 days** this week with a total of **3h 15min** of exercise. Your most intense session was a **45-min run** on Wednesday."
- Walk test: "Your most recent 6-minute walk test was on **Mar 15** — you covered **480 meters**, which is a good result for your condition."
- No data: "No [domain] data found for that period."

Rules:
- Be specific with numbers
- Reference the user's health condition when relevant (e.g., "good for someone with your condition")
- Show times in local timezone
- Bold key metrics

## Data structure
Return clean, display-ready data. No internal IDs. Format datetimes as readable strings.

# Failure Handling
- Retry on DB errors
- If no data found, return empty with a friendly note — don't fail the job
- Fail immediately on permission denied
