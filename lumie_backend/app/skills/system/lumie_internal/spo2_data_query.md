---
skill_id: spo2_data_query
title: SpO2 (Blood Oxygen) Data Query
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [spo2, blood oxygen, oxygen saturation, o2, respiratory, breathing, health data]
keywords: [blood oxygen, spo2, oxygen saturation, o2 level, oxygen level, respiratory health, pulse ox, oximetry, how's my oxygen, oxygen readings, latest oxygen]
summary: Query blood oxygen saturation (SpO2) readings from the Lumie Ring. Returns point-in-time measurements and trends over time periods.
proactive_eligible: true
proactive_domain: respiratory
proactive_priority: 85
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    time_reference:
      type: string
      description: "latest | today | yesterday | this week | last 7 days | last 14 days"
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

Use this skill when the user asks about their blood oxygen saturation (SpO2) levels from the Lumie Ring. This is clinically important for users with respiratory conditions, cardiac conditions, or when monitoring oxygen levels during exercise.

# When To Use
- "What's my blood oxygen level?"
- "Show me my SpO2 readings"
- "How's my oxygen saturation?"
- "Is my oxygen level normal?"
- "Check my recent O2 levels"
- "Show my blood oxygen trend"
- Parent checking child's oxygen levels

# Do NOT Use When
- User wants other ring health metrics → use `health_data_query`
- User wants real-time measurement → use `ring_live_measure`
- User wants heart rate data → use `health_data_query` domain=heart_rate

# Schema

See [`Spo2ReadingResponse` in models/spo2.py](../../models/spo2.py)

### Relevant fields for SpO2 queries:
- `timestamp` (datetime ISO 8601 with Z suffix) — when reading was taken
- `spo2_percent` (integer 0–100) — oxygen saturation percentage
- `created_at` (datetime, optional) — when reading was synced to server

### Clinical Interpretation:
- **95–100%**: Normal range, healthy oxygen saturation
- **90–94%**: Lower than ideal, worth monitoring (especially for those with chronic conditions)
- **<90%**: Clinically significant, may warrant medical attention
- **88% or below**: Potential hypoxemia, urgent evaluation recommended

**Note:** Ring measurements are skin-adjacent sensors; core body oxygenation may differ from these readings. For clinical decisions, cuff-based pulse oximetry is authoritative.

# Runtime Rules
- `user_timezone`, `ZoneInfo`, `timezone`, `timedelta`, `datetime` are all pre-loaded — do NOT import them
- Use the `db` variable directly
- The `user_id` and `target_user_id` variables are pre-loaded

# Timezone: Computing Time Ranges
```python
local_tz = ZoneInfo(user_timezone)
today_local = datetime.now(local_tz).date()

# TODAY
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

# LAST 14 DAYS
fourteen_days_ago_utc = datetime.now(timezone.utc) - timedelta(days=14)
```

# Query Examples

## Latest SpO2 Reading
```python
latest = await db.spo2_readings.find_one(
    {"user_id": target_user_id},
    sort=[("timestamp", -1)]
)

if latest:
    spo2 = latest["spo2_percent"]
    timestamp = latest["timestamp"]
else:
    # No SpO2 data available
    spo2 = None
```

## SpO2 Readings Last 24 Hours
```python
readings = await db.spo2_readings.find({
    "user_id": target_user_id,
    "timestamp": {"$gte": yesterday_start_utc, "$lt": today_end_utc}
}).sort("timestamp", -1).to_list(500)

if readings:
    avg_spo2 = sum(r["spo2_percent"] for r in readings) / len(readings)
    min_spo2 = min(r["spo2_percent"] for r in readings)
    max_spo2 = max(r["spo2_percent"] for r in readings)
    count = len(readings)
else:
    # No data for past 24 hours
    pass
```

## SpO2 Trend Over Last 7 Days
```python
readings = await db.spo2_readings.find({
    "user_id": target_user_id,
    "timestamp": {"$gte": seven_days_ago_utc}
}).sort("timestamp", 1).to_list(1000)

# Group by date
daily_spo2 = {}
for reading in readings:
    date = reading["timestamp"].date().isoformat()
    if date not in daily_spo2:
        daily_spo2[date] = []
    daily_spo2[date].append(reading["spo2_percent"])

# Calculate daily averages
daily_avg = {
    date: sum(values) / len(values)
    for date, values in daily_spo2.items()
}
```

## Identify Low SpO2 Events
```python
readings = await db.spo2_readings.find({
    "user_id": target_user_id,
    "timestamp": {"$gte": start_date_utc}
}).sort("timestamp", -1).to_list(1000)

# Find readings below 95%
low_spo2_events = [
    {
        "timestamp": r["timestamp"],
        "spo2_percent": r["spo2_percent"]
    }
    for r in readings
    if r["spo2_percent"] < 95
]
```

# Output Guidance

## Summary — write for the user directly
- Latest: "Your latest SpO2 reading is **97%**, which is in the healthy range."
- Alert: "Your SpO2 dropped to **91%** today at 3:45 PM. This is lower than your usual readings — monitor it and contact your doctor if it persists."
- Trend: "Your SpO2 has been stable this week, averaging **96%** with a low of **94%**. That's healthy."
- No data: "No SpO2 readings available yet. Make sure your ring is synced."

Rules:
- Use bold for specific values and concern levels
- Provide clinical context (normal, low-grade, concerning)
- **Do NOT give medical advice**, but suggest monitoring or medical consultation for low readings
- Be clear about ring limitations (skin-adjacent sensor)
- For readings <90%, emphasize need for medical evaluation

## Data structure
Return clean, display-ready data:

```json
{
  "summary": "Your SpO2 readings this week have been stable, averaging 96% with no concerning dips.",
  "data": {
    "latest_reading": {
      "timestamp": "2026-04-10T14:30:00Z",
      "spo2_percent": 97
    },
    "readings": [
      {
        "timestamp": "2026-04-10T14:30:00Z",
        "spo2_percent": 97
      },
      {
        "timestamp": "2026-04-10T12:15:00Z",
        "spo2_percent": 96
      }
    ],
    "metrics": {
      "reading_count": 48,
      "avg_spo2": 96.2,
      "min_spo2": 94,
      "max_spo2": 98,
      "low_readings_count": 2  // count below 95%
    }
  }
}
```

Do NOT include internal IDs or raw database documents.

# Proactive Mode Guidance

When used in proactive checks, flag oxygen saturation concerns:

## SpO2 Thresholds (Medical Science Based)

- **Normal (95–100%)**: No action needed
- **Low-grade (90–94%)**: Monitor; suggest checking again or consulting doctor if persistent
- **Concerning (<90%)**: Flag as urgent concern; recommend medical evaluation

## Pattern Detection

- **Nudge** if: any reading <90% in last 24 hours (clinically significant)
- **Nudge** if: 3+ readings in 90–94% range over last 7 days (borderline, worth monitoring)
- **Nudge** if: downward trend: avg SpO2 dropped 3%+ compared to prior week (may indicate changing condition)
- **Nudge** if: multiple readings <95% after activity (exercise-induced drop, worth monitoring if unexpectedly large)
- **Do not nudge** for: single borderline reading (90–95%) without pattern
- **Do not nudge** for: isolated low reading during sleep (overnight dips can be normal)

## Chronic Condition Context

- If user has cardiac/respiratory ICD-10 code: Lower thresholds — nudge at 93% or lower
- If user has asthma, COPD, or cardiac condition: Monitor trends more closely
- Baseline matters: Compare to user's normal range, not just absolute values

## Recommendation Format

```python
if min_spo2 < 90:
    concern_type = "urgent"
    recommendation = "SpO2 below 90% detected. Please seek medical evaluation."
elif any_reading_below_95 and icd10_code:
    concern_type = "elevated"
    recommendation = "SpO2 readings below 95% with your condition. Monitor closely and consult your doctor."
elif avg_spo2 < 94:
    concern_type = "moderate"
    recommendation = "SpO2 averaging in the low range. Consider checking with your doctor."
else:
    concern_type = None
```

# Failure Handling
- Retry on DB errors
- If no SpO2 data found, return empty with note: "No SpO2 readings available. Sync your ring to collect data."
- Never expose raw error messages to user
- Handle partial data gracefully (missing readings in range is OK)
