---
skill_id: tasks_create
title: Create Task or Reminder
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [tasks, create, add, reminder, set, medicine, medicine reminder, schedule, deadlines, batch, template, recurring]
keywords: [add task, create task, set task, add reminder, create reminder, set reminder, medicine tomorrow, task due, make a task, schedule a task, new task, schedule medicine, schedule reminder, remind me, set deadline, deadline task, task with deadline, batch tasks, use template, from template, generate tasks]
summary: Create a single task with a deadline, multiple recurring tasks across dates and time windows, or batch tasks from a template.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    task_name:
      type: string
      description: "Name of the task"
    task_type:
      type: string
      enum: [Medicine, Study, Exercise, Nutrition, Work, Hobbies, Social, Life]
      description: "Type of task"
    mode:
      type: string
      enum: [deadline, recurring, template]
      description: "deadline = single task; recurring = multiple dates × time windows; template = use a saved template"
    open_datetime:
      type: string
      description: "DEADLINE mode: start time in user's local timezone, format 'yyyy-MM-dd HH:mm'"
    close_datetime:
      type: string
      description: "DEADLINE mode: end time in user's local timezone, format 'yyyy-MM-dd HH:mm'"
    dates:
      type: array
      items:
        type: string
      description: "RECURRING mode: list of dates in 'yyyy-MM-dd' format"
    times:
      type: array
      items:
        type: object
        properties:
          open_time:
            type: string
            description: "Time in format 'HH:mm'"
          close_time:
            type: string
            description: "Time in format 'HH:mm'"
      description: "RECURRING mode: list of time windows with open_time and close_time"
    template_id:
      type: string
      description: "TEMPLATE mode: ID of the saved task template to use"
    start_date:
      type: string
      description: "TEMPLATE mode: start date in 'yyyy-MM-dd' format"
    end_date:
      type: string
      description: "TEMPLATE mode: end date in 'yyyy-MM-dd' format (inclusive)"
    frequency_minutes:
      type: integer
      description: "TEMPLATE mode: how often the template repeats in minutes (must exceed template span)"
    task_info:
      type: string
      description: "Optional notes or details for the task"
output_schema:
  type: object
  properties:
    summary:
      type: string
      description: "Human-readable summary of what was created"
    created_count:
      type: integer
      description: "Number of tasks created"
    nav_hint:
      type: string
      description: "Navigation hint for UI (task_list)"

---

# Purpose
Create one or more tasks for the user. Supports:
- **Deadline mode**: Single task with a start time and end time
- **Recurring mode**: Multiple tasks across multiple dates and time windows
- **Template mode**: Batch create tasks from a saved template across a date range

# When To Use
- "Add a medicine task tomorrow at 8-9 AM"
- "Create a work task due on May 1 from 2-4 PM"
- "Set a dentist appointment on Friday 3-4 PM"
- "Add medicine reminders for the next 3 days, 8 AM to 9 AM and 6 PM to 7 PM"
- "Generate my Daily Med template for the next 2 weeks"
- "Create tasks using the Phosphate template from April 22 to May 5, daily"

# Required Inputs (by mode)
- **deadline mode**: `task_name`, `task_type`, `mode: "deadline"`, `open_datetime`, `close_datetime`
- **recurring mode**: `task_name`, `task_type`, `mode: "recurring"`, `dates`, `times`
- **template mode**: `task_name`, `task_type`, `mode: "template"`, `template_id`, `start_date`, `end_date`, `frequency_minutes`

# Runtime Rules
- All time helpers are pre-loaded: `datetime`, `timedelta`, `timezone`, `ZoneInfo`, `uuid`, `asyncio`
- No imports allowed
- `user_timezone` contains the user's IANA timezone string (e.g. "America/Los_Angeles")
- `target_user_id` is the user to assign tasks to
- `db` is the MongoDB connection

# Data Model

## Task document (insert into `db.tasks`)
```python
{
    "task_id": str(uuid.uuid4()),
    "task_name": str,
    "task_type": str,  # "Medicine", "Study", etc.
    "open_datetime": "YYYY-MM-DD HH:MM",  # UTC, NO Z suffix
    "close_datetime": "YYYY-MM-DD HH:MM",  # UTC, NO Z suffix
    "user_id": target_user_id,
    "created_by": target_user_id,
    "team_id": None,
    "rpttask_id": None,
    "task_info": str or None,
    "attachments": [],
    "created_at": datetime.utcnow(),
    "updated_at": datetime.utcnow(),
}
```

**Key points:**
- `open_datetime` and `close_datetime` are stored as `"YYYY-MM-DD HH:MM"` strings in UTC (no Z suffix, no timezone indicator)
- `created_at` and `updated_at` are Python datetime objects (Motor handles serialization)
- All times provided by the user are in local time; convert to UTC before storing

# Execution Plan

## Step 1: Validate inputs
If `mode == "deadline"`:
  - Require `open_datetime`, `close_datetime`
  - Parse both as local times in `user_timezone`
  - Validate close > open

If `mode == "recurring"`:
  - Require `dates` (non-empty) and `times` (non-empty)
  - Validate each time window (close > open)

If `mode == "template"`:
  - Require `template_id`, `start_date`, `end_date`, `frequency_minutes`
  - Validate `start_date` ≤ `end_date`
  - Validate `frequency_minutes` > 0

## Step 2: Convert local times to UTC
```python
def local_to_utc(local_time_str: str) -> str:
    """Convert 'YYYY-MM-DD HH:MM' local time to UTC, return 'YYYY-MM-DD HH:MM'."""
    local_dt = datetime.strptime(local_time_str, "%Y-%m-%d %H:%M")
    tz = ZoneInfo(user_timezone)
    local_with_tz = local_dt.replace(tzinfo=tz)
    utc_dt = local_with_tz.astimezone(timezone.utc)
    return utc_dt.strftime("%Y-%m-%d %H:%M")
```

## Step 3: Create task document(s)
For each task to create:
1. Generate `task_id = str(uuid.uuid4())`
2. Convert `open_datetime`, `close_datetime` to UTC using the helper above
3. Build task dict matching the schema above
4. Insert via `await db.tasks.insert_one(task_dict)`

**For deadline mode:**
```python
created_count = 0
for _ in range(1):  # Just one iteration
    task_dict = {
        "task_id": str(uuid.uuid4()),
        "task_name": task_name,
        "task_type": task_type,
        "open_datetime": local_to_utc(open_datetime),
        "close_datetime": local_to_utc(close_datetime),
        "user_id": target_user_id,
        "created_by": target_user_id,
        "team_id": None,
        "rpttask_id": None,
        "task_info": task_info,
        "attachments": [],
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
    }
    await db.tasks.insert_one(task_dict)
    created_count += 1
```

**For recurring mode:**
```python
created_count = 0
errors = []
for date_str in dates:
    for tw in times:
        try:
            open_local = f"{date_str} {tw['open_time']}"
            close_local = f"{date_str} {tw['close_time']}"
            task_dict = {
                "task_id": str(uuid.uuid4()),
                "task_name": task_name,
                "task_type": task_type,
                "open_datetime": local_to_utc(open_local),
                "close_datetime": local_to_utc(close_local),
                "user_id": target_user_id,
                "created_by": target_user_id,
                "team_id": None,
                "rpttask_id": None,
                "task_info": task_info,
                "attachments": [],
                "created_at": datetime.utcnow(),
                "updated_at": datetime.utcnow(),
            }
            await db.tasks.insert_one(task_dict)
            created_count += 1
        except Exception as e:
            errors.append(f"{date_str}: {str(e)}")
```

**For template mode:**
```python
created_count = 0
errors = []

# Load template
template = await db.task_templates.find_one({"id": template_id})
if not template:
    _result = {
        "summary": f"I couldn't find a template with ID {template_id}.",
        "created_count": 0,
        "nav_hint": "task_list",
    }
else:
    # Parse dates
    start_dt = datetime.strptime(start_date, "%Y-%m-%d")
    end_dt = datetime.strptime(end_date, "%Y-%m-%d")
    end_of_range = end_dt + timedelta(days=1)  # Inclusive
    now = datetime.utcnow()
    now_str = now.strftime("%Y-%m-%d %H:%M")

    # Iterate through date range, applying template at each frequency
    current_anchor = start_dt
    while current_anchor < end_of_range:
        for window in template.get("time_window_list", []):
            try:
                window_name = window.get("name", "")
                open_time = window.get("open_time", "08:00")
                close_time = window.get("close_time", "09:00")
                is_next_day = window.get("is_next_day", False)

                # Parse times
                open_h, open_m = map(int, open_time.split(":"))
                close_h, close_m = map(int, close_time.split(":"))

                # Build local datetimes
                open_dt_local = current_anchor + timedelta(hours=open_h, minutes=open_m)
                close_dt_local = current_anchor + timedelta(hours=close_h, minutes=close_m)
                if is_next_day:
                    close_dt_local += timedelta(days=1)

                open_datetime_local = open_dt_local.strftime("%Y-%m-%d %H:%M")
                close_datetime_local = close_dt_local.strftime("%Y-%m-%d %H:%M")

                # Convert to UTC
                def local_to_utc_inner(local_str):
                    local_dt = datetime.strptime(local_str, "%Y-%m-%d %H:%M")
                    tz = ZoneInfo(user_timezone)
                    local_with_tz = local_dt.replace(tzinfo=tz)
                    utc_dt = local_with_tz.astimezone(timezone.utc)
                    return utc_dt.strftime("%Y-%m-%d %H:%M")

                open_datetime_utc = local_to_utc_inner(open_datetime_local)
                close_datetime_utc = local_to_utc_inner(close_datetime_local)

                # Skip windows that have already closed
                if close_datetime_utc <= now_str:
                    continue

                # If already open, start from now
                if open_datetime_utc < now_str:
                    open_datetime_utc = now_str

                task_dict = {
                    "task_id": str(uuid.uuid4()),
                    "task_name": f"{task_name} - {window_name}" if window_name else task_name,
                    "task_type": task_type,
                    "open_datetime": open_datetime_utc,
                    "close_datetime": close_datetime_utc,
                    "user_id": target_user_id,
                    "created_by": target_user_id,
                    "team_id": None,
                    "rpttask_id": template_id,
                    "task_info": task_info,
                    "attachments": [],
                    "created_at": now,
                    "updated_at": now,
                }
                await db.tasks.insert_one(task_dict)
                created_count += 1
            except Exception as e:
                errors.append(f"Window {current_anchor.strftime('%Y-%m-%d')}: {str(e)}")

        current_anchor += timedelta(minutes=frequency_minutes)
```

## Step 4: Build result
```python
if created_count == 0:
    summary = "I wasn't able to create any tasks."
    if errors:
        summary += f" {errors[0]}"
elif created_count == 1:
    summary = f"Done! I've created **{task_name}**."
else:
    summary = f"Done! I've created **{created_count}** **{task_name}** tasks."

_result = {
    "summary": summary,
    "created_count": created_count,
    "nav_hint": "task_list",
}
```

# Failure Handling
- Retry on MongoDB connection errors
- Fail immediately on invalid timezone, bad datetime format, missing template
- If some tasks fail in recurring or template mode, continue with others and report errors in summary
- If template not found, return early with error message and created_count = 0
