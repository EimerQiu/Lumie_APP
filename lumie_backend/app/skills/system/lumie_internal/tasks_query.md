---
skill_id: tasks_query
title: Tasks and Medications Query
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [tasks, medications, reminders, reminder, schedule, today, tomorrow, week, upcoming, overdue, history, med, meds, medicine, find, search]
keywords: [what should I do, tasks today, medicine today, medication schedule, upcoming tasks, what's due, reminders, reminder, take medicine, daily schedule, what medication, tomorrow tasks, this week, next week, tasks this week, overdue tasks, missed tasks, pending tasks, all tasks, task history, task schedule, task list, what do I have, any tasks, any reminders, med reminder, med-reminder, medication reminder, meds, my meds, take my meds, med schedule, medicine schedule, medicine reminder, find task, search task, task about, task detail, specific task, find a task, look for task, task named, task called, booking, appointment, task with]
summary: Query tasks and medication reminders for any time range (today, tomorrow, this week, etc.) or search for a specific task by keyword or name. Covers all 7 task types.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    target_user_hint:
      type: string
    time_reference:
      type: string
      description: "today | tomorrow | this week | next week | yesterday | specific date | upcoming | overdue | all"
    keyword:
      type: string
      description: "optional keyword to search tasks by name or topic"
output_schema:
  type: object
  properties:
    summary:
      type: string
    tasks:
      type: array
---

# Purpose
The primary skill for all task and medication queries — whether the user wants to see their schedule for a time period, or find a specific task by keyword.

# When To Use
- "What should I do now / today?"
- "What medicine do I need to take?"
- "Any tasks tomorrow / this week?"
- "Show me upcoming reminders"
- "Did I miss any tasks yesterday?"
- "Any overdue medications?"
- "I have a task about flight booking, find the detail"
- "Find my dentist appointment task"
- "Search for a task called..."
- "What task do I have about X?"
- Parent asking about their child's schedule

# Do NOT Use When
- User wants overall health summary → use `comprehensive_health_assessment`

# Required Inputs
- Either a time reference (today, tomorrow, this week, etc.) OR a keyword to search by — infer from the question

# Runtime Rules
- Use `lumie_db` runtime
- `user_timezone`, `ZoneInfo`, `timezone`, `timedelta`, `datetime` are all pre-loaded — do NOT import them

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Query from: `tasks`

# Data Model

## tasks collection fields
- `task_name`: string — For template-generated tasks: `"{template_name} - {window_name}"` (e.g., "Daily Med - 9AM Phosphate"). Use the part after " - " as the display name.
- `task_type`: "Medicine" | "Life" | "Study" | "Exercise" | "Work" | "Meditation" | "Love"
- `open_datetime`: string "YYYY-MM-DD HH:MM" (UTC, no Z suffix) — window opens
- `close_datetime`: string "YYYY-MM-DD HH:MM" (UTC, no Z suffix) — window closes
- `done`: MongoDB datetime if completed, field ABSENT if not completed
- `task_info`: string or null — optional notes

# Execution Plan

## Mode A — Time-range query (user asks about a period)

### Step 1 — Determine query range
```python
local_tz = ZoneInfo(user_timezone)
today_local = datetime.now(local_tz).date()

# TODAY
range_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc)
range_end_utc = range_start_utc + timedelta(days=1)

# TOMORROW
range_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc) + timedelta(days=1)
range_end_utc = range_start_utc + timedelta(days=1)

# THIS WEEK (Mon–Sun)
days_since_monday = today_local.weekday()
monday_local = today_local - timedelta(days=days_since_monday)
range_start_utc = datetime(monday_local.year, monday_local.month, monday_local.day, tzinfo=local_tz).astimezone(timezone.utc)
range_end_utc = range_start_utc + timedelta(days=7)

# YESTERDAY
range_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc) - timedelta(days=1)
range_end_utc = range_start_utc + timedelta(days=1)

# UPCOMING (next 7 days)
range_start_utc = datetime.now(timezone.utc)
range_end_utc = range_start_utc + timedelta(days=7)
```

### Step 2 — Query
```python
start_str = range_start_utc.strftime("%Y-%m-%d %H:%M")
end_str = range_end_utc.strftime("%Y-%m-%d %H:%M")
tasks = await db.tasks.find({
    "user_id": target_user_id,
    "open_datetime": {"$lt": end_str},
    "close_datetime": {"$gt": start_str},
}).to_list(200)
```

## Mode B — Keyword search (user wants a specific task by name/topic)

```python
import re
keyword = "flight"  # extract from user's question

pattern = re.compile(keyword, re.IGNORECASE)
all_tasks = await db.tasks.find({"user_id": target_user_id}).to_list(500)
tasks = [t for t in all_tasks if pattern.search(t.get("task_name", "") or "") or pattern.search(t.get("task_info", "") or "")]
tasks = sorted(tasks, key=lambda t: t.get("open_datetime", ""), reverse=True)[:10]
```

## Step 3 — Compute status (both modes)
```python
now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
for t in tasks:
    if t.get("done"):
        status = "completed"
    elif t.get("close_datetime", "") < now_str:
        status = "missed"
    elif t.get("open_datetime", "") <= now_str:
        status = "active"
    else:
        status = "upcoming"
```

## Step 4 — Format for display
```python
local_tz = ZoneInfo(user_timezone)

def fmt_local(dt_str):
    try:
        dt_utc = datetime.strptime(dt_str, "%Y-%m-%d %H:%M").replace(tzinfo=timezone.utc)
        return dt_utc.astimezone(local_tz).strftime("%I:%M %p").lstrip("0")
    except Exception:
        return dt_str

def display_name(task_name):
    if " - " in task_name:
        return task_name.split(" - ", 1)[1]
    return task_name
```

# Output Guidance

## Summary
- Time-range: "You have **Vitamin D** to take right now. **DHA** is coming up at 4:00 PM. You took **Iron** this morning."
- Keyword search: "I found 2 tasks matching 'flight': **Flight Booking** (due Mar 30, 3:00 PM - 5:00 PM) with note: 'Book before April'."
- No results: "No tasks found for that period." / "No tasks matching '[keyword]'."

Rules: bold task names, local timezone times, mention missed tasks.

## Data arrays
```json
{"name": "Phosphate", "task_type": "Medicine", "time_window": "12:00 PM - 2:00 PM", "status": "active|completed|missed|upcoming", "task_info": "..."}
```
Do NOT include task_id, user_id, _id, or created_by.

# Failure Handling
- Retry on DB errors
- Fail immediately on permission denied
