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
      description: "TEMPLATE mode: repeat cadence in minutes. Advisor safety rule: minimum 1440 (daily). Must also be greater than template span."
    task_info:
      type: string
      description: "Optional notes or details for the task"
    team_name:
      type: string
      description: "Optional: Name of the team the tasks belong to (e.g. 'Yumo family'). User must be an admin of the team. If not provided and team_task is not true, tasks are personal."
    team_task:
      type: boolean
      description: "Optional: Set to true when the user clearly indicates the task is for their team/family but did NOT name a specific team (e.g. 'create a team task', 'add a family task', 'remind everyone in our team'). When true and team_name is empty, the skill auto-resolves to the user's only admin team if they belong to exactly one. Ignored when team_name is provided."
    user_id:
      type: string
      description: "Optional: Assign tasks to another team member by user_id (team admins only). If not provided, assigned to the requesting user."
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

**Personal tasks:**
- "Add a medicine task tomorrow at 8-9 AM"
- "Create a work task due on May 1 from 2-4 PM"
- "Set a dentist appointment on Friday 3-4 PM"
- "Add medicine reminders for the next 3 days, 8 AM to 9 AM and 6 PM to 7 PM"
- "Generate my Daily Med template for the next 2 weeks" (defaults to daily)

**Team tasks (family, group, etc.):**
- "Create exercise tasks for next week in the Yumo family team"
- "Generate the Daily Meds template for my daughter in our family team"
- "Set up medicine reminders for Emma in the Ymo family team from tomorrow through next Friday"
- "Create a study task on May 5 from 7-9 PM in the family team for my son"

**Team task without a named team (single-team shortcut):**
- "Create a team task tomorrow 8-9 AM to take vitamins"
- "Add a family task for next week to walk the dog"
- "Remind everyone in our team to log activity tonight 8-9 PM"
- For these, the user clearly wants a team task but did NOT name a specific team. The advisor MUST set `team_task = true` and leave `team_name` empty. Do NOT ask "which team?" — the skill auto-resolves to the user's only admin team if they belong to exactly one. If the user belongs to multiple admin teams, the skill itself returns a clarification.

**Worked example (must follow):**
- User: "Create exercise tasks for next week in the Yumo family"
- Template windows: 1 (Morning)
- Date range: 7 days (inclusive)
- Required cadence: daily (`frequency_minutes = 1440`)
- Required result: exactly 7 tasks (1 per day), not 168

# Required Inputs (by mode)
- **deadline mode**: `task_name`, `task_type`, `mode: "deadline"`, `open_datetime`, `close_datetime`
- **recurring mode**: `task_name`, `task_type`, `mode: "recurring"`, `dates`, `times`
- **template mode**: `task_name`, `task_type`, `mode: "template"`, `template_id`, `start_date`, `end_date`
  - Optional: `frequency_minutes` (defaults to 1440 = daily if not provided)
  - Advisor safety rule: always enforce `frequency_minutes >= 1440` for template mode
  - If user says "next week" / "this week" / "for 7 days", use `frequency_minutes = 1440` (daily)

# Clarification-First Policy (required)
Before ANY write, check whether critical scheduling/target info is missing or ambiguous.
If missing/ambiguous, ask a concise clarification question and DO NOT create tasks yet.

Critical fields by mode:
- `deadline`: `task_name`, `task_type`, `open_datetime`, `close_datetime`
- `recurring`: `task_name`, `task_type`, `dates`, `times[].open_time`, `times[].close_time`
- `template`: `template_id`, `start_date`, `end_date` (and a resolvable team/member target if team assignment is requested)

Ambiguity examples that MUST trigger clarification:
- User asks to "create a task" but gives no time window
- User gives only one endpoint ("tomorrow at 8") without clear open+close range
- User says "for Eimer" but target member/team cannot be resolved uniquely
- User asks "next week" but no template can be uniquely identified

Cases that MUST NOT trigger clarification (the skill resolves them):
- User clearly wants a team/family task but doesn't name the team. Pass `team_task = true` (with `team_name` empty) and let the skill auto-resolve to the user's only admin team. Only fall back to clarification if the skill itself returns one (multi-team case).

Hard prohibitions:
- Never auto-fill `open_datetime = now`
- Never auto-fill `close_datetime = now + 24h`
- Never auto-create a generic 24-hour task because details are missing
- Never guess team member identity when multiple candidates exist

Clarification response format (no write):
```python
_result = {
  "summary": "Need one detail before I create it: what start and end time should I use?",
  "created_count": 0,
  "nav_hint": "task_list"
}
```

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
  - If either time is missing/unclear: return clarification and stop (no writes)

If `mode == "recurring"`:
  - Require `dates` (non-empty) and `times` (non-empty)
  - Validate each time window (close > open)
  - If dates/times are missing or ambiguous: return clarification and stop (no writes)

If `mode == "template"`:
  - Require `template_id`, `start_date`, `end_date`
  - Validate `start_date` ≤ `end_date`
  - If `frequency_minutes` missing, set to `1440`
  - Validate `frequency_minutes` > 0
  - Safety rule for advisor-generated template tasks: enforce `frequency_minutes >= 1440` (daily minimum)
  - Validate `frequency_minutes > template_span_minutes`
  - Do not use `template.min_interval` as generation cadence
  - Sanity-check count before inserts:
    - `expected_count = anchors_in_range × template_window_count`
    - For 7 days, 1 window, daily cadence => expected_count must be 7
    - If expected_count is unexpectedly high (for example > 3 × days × windows), stop and return an error summary
  - If template/team/assignee cannot be resolved confidently: return clarification and stop (no writes)

## Template Mode Policy (strict)
- Template mode is for daily-or-longer scheduling only.
- Never generate template tasks with sub-day cadence (`frequency_minutes < 1440`).
- If user intent is hourly/minutely repetition, do not force template mode. Use recurring mode with explicit `dates` + `times`, or return a clarification summary with `created_count = 0`.

## Step 1.5: Resolve team name to team_id
Two paths:
- **`team_name` provided** → look it up and verify the requester is an admin.
- **`team_name` empty AND `team_task` is true** → auto-resolve to the user's only admin team. If they have exactly one active admin membership in a non-deleted team, use it. If zero or more than one, return a clarification (no writes).

```python
team_id = None

if team_name:
    # Find team by name (case-insensitive)
    team = await db.teams.find_one({
        "name": {"$regex": f"^{team_name}$", "$options": "i"},
        "is_deleted": False
    })

    if not team:
        _result = {
            "summary": f"I couldn't find a team named '{team_name}'.",
            "created_count": 0,
            "nav_hint": "task_list",
        }
        # Early return - skip task creation
    else:
        team_id = team["team_id"]

        # Verify target_user_id is an admin of this team
        admin_check = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": target_user_id,
            "role": "admin",
            "status": "member"
        })

        if not admin_check:
            _result = {
                "summary": f"You must be an admin of '{team_name}' to create tasks there.",
                "created_count": 0,
                "nav_hint": "task_list",
            }
            # Early return - skip task creation

elif team_task:
    # Auto-resolve: user said "team/family task" but didn't name the team.
    admin_memberships = await db.team_members.find({
        "user_id": target_user_id,
        "role": "admin",
        "status": "member",
    }).to_list(50)

    # Filter to teams that still exist (not soft-deleted)
    candidate_teams = []
    for m in admin_memberships:
        t = await db.teams.find_one(
            {"team_id": m["team_id"], "is_deleted": False},
            {"team_id": 1, "name": 1},
        )
        if t:
            candidate_teams.append(t)

    if len(candidate_teams) == 0:
        _result = {
            "summary": "You're not an admin of any team, so I can't create a team task. Want me to create it as a personal task instead?",
            "created_count": 0,
            "nav_hint": "task_list",
        }
        # Early return - skip task creation
    elif len(candidate_teams) == 1:
        team_id = candidate_teams[0]["team_id"]
    else:
        names = ", ".join(t.get("name", "?") for t in candidate_teams)
        _result = {
            "summary": f"You belong to multiple teams ({names}). Which team should I add this task to?",
            "created_count": 0,
            "nav_hint": "task_list",
        }
        # Early return - skip task creation
```

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
        "team_id": team_id,
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
                "team_id": team_id,
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
    # Set frequency default to daily (1440 minutes) if not provided
    freq_minutes = frequency_minutes if frequency_minutes else 1440

    # Safety rule: template mode must be daily-or-longer to avoid accidental
    # over-generation (e.g., 168 tasks for one week).
    if freq_minutes < 1440:
        freq_minutes = 1440

    # IMPORTANT: do not use template.min_interval as generation cadence.
    # min_interval is a completion/postpone rule, not a repeat-anchor interval.
    
    # Parse dates
    start_dt = datetime.strptime(start_date, "%Y-%m-%d")
    end_dt = datetime.strptime(end_date, "%Y-%m-%d")
    end_of_range = end_dt + timedelta(days=1)  # Inclusive
    now = datetime.utcnow()
    now_str = now.strftime("%Y-%m-%d %H:%M")

    # Validate frequency against template span: frequency must be longer than the
    # template's full open→close span, otherwise windows overlap and explode count.
    def _to_min(t):
        h, m = map(int, t.split(":"))
        return h * 60 + m
    wins = template.get("time_window_list", [])
    if wins:
        opens = [_to_min(w.get("open_time", "00:00")) for w in wins]
        closes = [
            _to_min(w.get("close_time", "00:00")) + (1440 if w.get("is_next_day", False) else 0)
            for w in wins
        ]
        template_span = max(closes) - min(opens)
        if freq_minutes <= template_span:
            _result = {
                "summary": (
                    f"Can't create tasks: frequency ({freq_minutes} min) must be greater than "
                    f"template span ({template_span} min)."
                ),
                "created_count": 0,
                "nav_hint": "task_list",
            }
            # Early return - skip creation

    # Expected-count sanity check before inserts.
    # For 7-day range, 1 window, daily cadence => expected_count = 7.
    total_days = (end_dt - start_dt).days + 1
    win_count = max(1, len(wins))
    anchor_count = ((total_days * 1440 - 1) // freq_minutes) + 1
    expected_count = anchor_count * win_count
    if expected_count > (3 * total_days * win_count):
        _result = {
            "summary": (
                f"Skipped creation because expected task count ({expected_count}) is unusually high "
                f"for {total_days} day(s) and {win_count} window(s)."
            ),
            "created_count": 0,
            "nav_hint": "task_list",
        }
        # Early return - skip creation

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
                    "team_id": team_id,
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

        current_anchor += timedelta(minutes=freq_minutes)
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
