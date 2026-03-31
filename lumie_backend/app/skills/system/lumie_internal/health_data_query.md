---
skill_id: health_data_query
title: Health Data Query
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [sleep, activity, exercise, walk test, rest day, heart rate, hrv, steps, health, fitness]
keywords: [sleep, slept, sleeping, last night, bedtime, wake up, sleep quality, sleep score, sleep hours, deep sleep, rem sleep, light sleep, how did I sleep, sleep data, activity, activities, exercise, steps, step count, how many steps, walked, distance, workout, how active, calories burned, walk test, 6 minute walk, walking test, heart rate, resting heart rate, bpm, pulse, continuous heart rate, hrv, heart rate variability, stress, fatigue, blood pressure, systolic, diastolic, temperature, body temperature, fever, temp, spo2, blood oxygen, oxygen saturation, oxygen level, o2, rest day, rest days, recovery, how many rest days, active days, fitness data, health data, how was my, how am I doing, my health, my activity, my sleep]
summary: Query focused health data for a single domain — sleep sessions, activity records, walk tests, or rest days. Use this for specific health metric questions, not broad multi-domain summaries.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    domain:
      type: string
      description: "sleep | activity | walk_test | rest_days | hrv | heart_rate | steps | temperature | spo2"
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

## Heart Rate (`hr_readings` collection)
```python
# Last 24 hours of continuous HR readings from the ring
readings = await db.hr_readings.find(
    {"user_id": target_user_id, "timestamp": {"$gte": yesterday_start_utc, "$lt": today_end_utc}}
).sort("timestamp", 1).to_list(500)
# Fields: timestamp, bpm
# Compute resting HR (lowest 10th percentile), peak HR, average
import statistics
bpms = [r["bpm"] for r in readings if r.get("bpm", 0) > 0]
avg_bpm = round(statistics.mean(bpms)) if bpms else None
resting_bpm = sorted(bpms)[len(bpms) // 10] if len(bpms) >= 10 else (min(bpms) if bpms else None)
peak_bpm = max(bpms) if bpms else None
```

## Daily Steps (`daily_steps` collection)
```python
# Last 7 days of ring step data
step_docs = await db.daily_steps.find(
    {"user_id": target_user_id, "date_str": {"$gte": (datetime.now(local_tz) - timedelta(days=7)).strftime("%Y-%m-%d")}}
).sort("date_str", -1).to_list(7)
# Fields: date_str (YYYY-MM-DD), steps, exercise_time_seconds, distance_km
# Today's steps
today_str = datetime.now(local_tz).strftime("%Y-%m-%d")
today_steps = await db.daily_steps.find_one({"user_id": target_user_id, "date_str": today_str})
```

## Temperature (`temperature_readings` collection)
```python
# Latest temperature reading
latest = await db.temperature_readings.find_one(
    {"user_id": target_user_id},
    sort=[("timestamp", -1)]
)
# Fields: timestamp, temp1_c, temp2_c, temp3_c (three sensor readings in °C)
# Last 7 days
readings = await db.temperature_readings.find(
    {"user_id": target_user_id, "timestamp": {"$gte": week_start_utc}}
).sort("timestamp", -1).to_list(200)
```

## SpO2 / Blood Oxygen (`spo2_readings` collection)
```python
# Latest SpO2 reading
latest = await db.spo2_readings.find_one(
    {"user_id": target_user_id},
    sort=[("timestamp", -1)]
)
# Fields: timestamp, spo2_percent (oxygen saturation 0–100%)
# Last 7 days
readings = await db.spo2_readings.find(
    {"user_id": target_user_id, "timestamp": {"$gte": week_start_utc}}
).sort("timestamp", -1).to_list(200)
```

## HRV / Stress / Blood Pressure (`hrv_readings` collection)
```python
# Last 7 days of HRV readings
readings = await db.hrv_readings.find(
    {"user_id": target_user_id, "timestamp": {"$gte": week_start_utc, "$lt": week_end_utc}}
).sort("timestamp", -1).to_list(200)
# Fields: timestamp, hrv_ms, heart_rate_bpm, fatigue (0-100 stress/fatigue score),
#         systolic_mmhg, diastolic_mmhg
# For a single most-recent reading:
latest = await db.hrv_readings.find_one(
    {"user_id": target_user_id},
    sort=[("timestamp", -1)]
)
```

# Output Guidance

## Summary — write for the user directly
- Sleep: "You slept **7h 20min** last night with a quality score of **82/100**. You got 28% deep sleep, which is great for recovery."
- Activity: "You were active **4 days** this week with a total of **3h 15min** of exercise. Your most intense session was a **45-min run** on Wednesday."
- Walk test: "Your most recent 6-minute walk test was on **Mar 15** — you covered **480 meters**, which is a good result for your condition."
- Heart rate: "Your resting heart rate over the last 24 hours was **58 bpm**, with a peak of **142 bpm**. Average was **74 bpm**."
- Temperature: "Your latest body temperature reading was **36.8°C** (sensor 1), taken at 7:42 AM."
- SpO2: "Your blood oxygen level was **98%** at your most recent reading — that's a healthy range."
- Steps: "You've taken **6,840 steps** today (**3.2 km**), with **47 minutes** of active movement."
- HRV: "Your latest HRV reading (**42ms**) is within your normal range. Your stress/fatigue score was **35/100** and blood pressure was **118/76 mmHg**."
- No data: "No [domain] data found for that period."

Rules:
- Be specific with numbers
- Reference the user's health condition when relevant (e.g., "good for someone with your condition")
- Show times in local timezone
- Bold key metrics

## Data structure
Return clean, display-ready data. No internal IDs. Format datetimes as readable strings.

# Proactive Mode Guidance

When this skill is used in **proactive mode** (the advisor is autonomously checking whether to
send a nudge, not responding to a user message), use the following criteria to flag concerns:

## Sleep
- **Nudge** if: quality score < 60, OR total sleep < 5 hours, OR resting HR during sleep is
  notably elevated vs. recent average (suggests poor recovery)
- **Nudge** if: no sleep data for 2+ consecutive days (ring may be off — worth checking in)
- **Do not nudge** if: sleep looks normal or only slightly below average

## Activity
- **Nudge** if: no activity recorded for 3+ days AND the user's recent baseline shows they are
  normally active (don't nudge a typically sedentary user for the same pattern)
- **Nudge** if: activity intensity/duration has dropped sharply (>50%) vs. the prior week
- **Do not nudge** for: a single rest day, low-intensity days in an otherwise active week

## Walk Test
- **Nudge** if: the most recent walk test distance has declined more than 10% vs. the previous
  test — this may indicate a change in the user's cardiopulmonary condition
- **Do not nudge** if: no new test has been completed (absence of data is not a concern here)

## HRV / Stress
- **Nudge** if: fatigue score > 70 consistently across the last 3+ readings (sustained high stress)
- **Nudge** if: HRV has dropped more than 20% vs. the user's 7-day average (sign of poor recovery)
- **Do not nudge** for: a single elevated stress reading — only patterns matter

## SpO2 / Blood Oxygen
- **Nudge** if: any reading is below 95% (clinically significant, especially for teens with cardiac or respiratory conditions)
- **Nudge** if: readings are consistently 95–97% over multiple days (borderline, worth flagging)
- **Do not nudge** for: isolated single readings — SpO2 can fluctuate during movement

## Temperature
- **Nudge** if: any sensor reading is above 38.0°C (potential fever)
- **Nudge** if: temperature has been trending upward over the last 3+ readings
- **Do not nudge** for: minor fluctuations within 36.0–37.5°C range

## Rest Days
- **Do not nudge** about rest days — they are intentional and user-configured

## Chronic Condition Consideration
- If the user has an ICD-10 code, be more sensitive to health signal changes — a trend that
  looks minor in a healthy teen may be significant for someone managing a chronic condition
- Interpret poor sleep and low activity together as a stronger signal than either alone

# Failure Handling
- Retry on DB errors
- If no data found, return empty with a friendly note — don't fail the job
- Fail immediately on permission denied
