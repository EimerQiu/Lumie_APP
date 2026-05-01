---
skill_id: tasks_complete
title: Complete Task
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [tasks, complete, finish, mark, done, completed, accomplishment, achievement, task completion, check off]
keywords: [mark task complete, mark task as done, finish task, complete task, check off task, task is done, i finished, i completed, mark as finished, done with, accomplished, checked off, completed a task, finished a task, task done]
summary: Mark a single task as completed by task ID. The advisor can complete any task they have authority over (personal task, team task they admin, or team member task they oversee).
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    task_id:
      type: string
      description: "The unique identifier of the task to complete. Optional if target_user_hint + task_name are provided."
    target_user_hint:
      type: string
      description: "Optional: Name or email (fuzzy match, case-insensitive). Examples: 'Eimer', 'eimer', 'alex@example.com', 'alex'. Matches user in your teams by name substring or email substring. Only works if you are a team admin. If not provided, defaults to your own tasks."
    task_name:
      type: string
      description: "Optional: Task name (fuzzy match, case-insensitive). Examples: 'phosphate', 'daily med', 'exercise'. Used with target_user_hint to find the task by name instead of task_id. If multiple matches, returns error with options."
    completed_at:
      type: string
      description: "Optional: ISO 8601 datetime when task was completed (e.g., '2026-04-29T14:30:00Z'). Must not be in the future. If not provided, uses close_datetime for expired tasks or now for active tasks."
    time_zone:
      type: string
      description: "Optional: User's IANA timezone. Currently unused (reserved for future use)."
    date_hint:
      type: string
      description: "Optional: Date context for filtering tasks (e.g., 'yesterday', 'today', 'tomorrow', or '2026-04-28'). Limits search to tasks with close_datetime on that date."
output_schema:
  type: object
  properties:
    summary:
      type: string
      description: "Human-readable confirmation message"
    task_id:
      type: string
      description: "The completed task ID"
    username:
      type: string
      description: "Name of the user who completed the task"
    task_name:
      type: string
      description: "Name of the completed task"
    nav_hint:
      type: string
      description: "Navigation hint for UI (task_detail or task_list)"

---

# Purpose
Mark a task as completed. Used by advisors (typically parents/admins) to acknowledge that a user (child) has finished a task, or for the user to mark their own task as done.

**IMPORTANT FOR ADVISORS:** When user says "Complete X's task", extract X as `target_user_hint`. Example: "Complete Eimer's phosphate task" → target_user_hint="Eimer", task_name="phosphate". Do NOT ask for confirmation; the skill will look up the user in the team automatically.

# When To Use
- **Own task by ID**: "Mark task 12345 as complete"
- **Own task by name**: "Complete the phosphate reminder" (matches "Daily Med - 9AM Phosphate")
- **With date context** (filters to specific date): "Complete Eimer's phosphate task from yesterday" (searches only yesterday's tasks, not all 500 in DB)
- **Partial name match**: "Finish medicine" (fuzzy, case-insensitive substring)
- **Team member's task** (admin only): "Complete Eimer's phosphate task" (fuzzy match: "eimer" matches name "Eimer")
- **Team member's task** (admin only): "Mark alex's exercise task" (fuzzy match: "alex" matches email "alex@example.com")
- **Date + fuzzy combo**: "Mark alex's med task from yesterday" (filters to yesterday's tasks, then fuzzy matches "med")
- **Expired/missed task**: Auto-backdates to `close_datetime` when completing (e.g., task closed yesterday at 9 AM → marked complete at 9 AM)

# Pattern Recognition

## Extract target_user_hint from phrasing:
- "Complete **Eimer's** phosphate task" → target_user_hint="Eimer"
- "Mark **Alex's** medicine reminder" → target_user_hint="Alex"
- "Finish the task for **alex@example.com**" → target_user_hint="alex@example.com"
- "Complete the phosphate task for **the child**" → target_user_hint="the child" (will lookup by name)

## Extract date_hint from phrasing:
- "Complete Eimer's phosphate task **from yesterday**" → date_hint="yesterday"
- "Mark alex's med task **from today**" → date_hint="today"
- "Finish the exercise task **from 2026-04-28**" → date_hint="2026-04-28"
- "Complete the medicine task **for tomorrow**" → date_hint="tomorrow"

**Rule:** If user mentions date context (yesterday, today, tomorrow, or specific date), extract as date_hint. This narrows the search and avoids loading all tasks.

# Do NOT Use When
- User wants to see tasks → use `tasks_query`
- User wants to postpone a task → (future skill: tasks_postpone)
- User wants to delete a task → (future skill: tasks_delete)

# Required Inputs
**One of:**
- `task_id` — direct task identifier (simplest, no ambiguity)
- `target_user_hint` + `task_name` — user name/email + exact task name (for completing other team members' tasks)

# Optional Inputs
- `completed_at` — explicit completion timestamp (ISO 8601 format). 
  - If **not provided** (automatic): 
    - Expired tasks (close_datetime < now): use task's `close_datetime` to backdate
    - Active/future tasks: use current UTC time
  - If **provided**: use this value (must not be in the future; backend rejects future timestamps)
- `time_zone` — currently unused; reserved for future use.
- `target_user_hint` — (mentioned above) name or email of team member whose task to complete. Requires admin access to their team.

# Runtime Rules
- Use `lumie_db` runtime
- `datetime`, `timezone` are pre-loaded — do NOT import them
- Results from `tasks_query` can provide task_id for this skill

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Query and update: `tasks` collection

# Data Model

## Task Schema
See [`TaskResponse` in models/task.py](../../models/task.py)

### Relevant fields:
- `task_id` (string) — unique task identifier
- `task_name` (string) — display name
- `user_id` (string) — task owner
- `team_id` (string, optional) — if team task
- `completed_at` (datetime ISO 8601 with Z suffix, if present) — completion timestamp; field ABSENT if not completed
- `open_datetime` (string, "YYYY-MM-DD HH:MM" UTC) — window opens
- `close_datetime` (string, "YYYY-MM-DD HH:MM" UTC) — window closes
- `created_by` (string) — who created the task

# Execution Plan

## Step 0 — Resolve target user (if target_user_hint provided)
```python
import re

target_user_id = requesting_user_id  # Default to self

if target_user_hint:
    # Admin lookup: find the user by name or email (fuzzy match) within teams
    db = get_database()
    hint_lower = target_user_hint.lower().strip()
    
    # Strategy 1: Exact email match (fastest)
    user = await db.users.find_one({"email": hint_lower})
    if user:
        target_user_id = user["user_id"]
    else:
        # Strategy 2: Get admin team IDs, then fuzzy match by email or name
        admin_cursor = db.team_members.find({
            "user_id": requesting_user_id,
            "role": "admin",
            "status": "member"
        })
        admin_memberships = await admin_cursor.to_list(length=None)
        admin_team_ids = [m["team_id"] for m in admin_memberships]
        
        if not admin_team_ids:
            return {"summary": "You must be a team admin to complete other users' tasks"}
        
        # Now search for the user in your teams
        cursor = db.team_members.find({
            "team_id": {"$in": admin_team_ids},
            "status": "member"
        })
        team_members = await cursor.to_list(length=None)
        
        candidates = []
        for tm in team_members:
            user_doc = await db.users.find_one({"user_id": tm["user_id"]})
            profile = await db.profiles.find_one({"user_id": tm["user_id"]})
            
            # Email fuzzy match
            if user_doc and hint_lower in user_doc.get("email", "").lower():
                candidates.append(tm["user_id"])
            # Name fuzzy match (substring)
            elif profile and hint_lower in profile.get("name", "").lower():
                candidates.append(tm["user_id"])
        
        if len(candidates) == 1:
            target_user_id = candidates[0]
        elif len(candidates) > 1:
            # Multiple matches: show options
            names = []
            for uid in candidates[:3]:
                p = await db.profiles.find_one({"user_id": uid})
                u = await db.users.find_one({"user_id": uid})
                names.append(p.get("name") if p else u.get("email", "Unknown"))
            return {"summary": f"Multiple users match '{target_user_hint}': {', '.join(names)}. Please be more specific"}
        else:
            return {"summary": f"User '{target_user_hint}' not found in your teams"}
```

## Step 1 — Resolve task by task_id or task_name (fuzzy match)
```python
import re

task = None
resolved_task_id = None

if task_id:
    # Direct lookup by task_id (single result expected)
    task = await db.tasks.find_one({"task_id": task_id})
    if not task:
        return {"summary": "Task not found"}
    resolved_task_id = task_id
    
elif task_name:
    # Fuzzy lookup by user + task_name (MongoDB $regex for server-side matching)
    # Example: "phosphate" matches "Daily Med - 9AM Phosphate"
    
    # Build query with name filter
    query = {
        "user_id": target_user_id,
        "task_name": {"$regex": task_name, "$options": "i"}  # Case-insensitive regex
    }
    
    # Add date filter if date_hint provided (narrow search)
    if date_hint:
        from datetime import datetime, timedelta
        from zoneinfo import ZoneInfo
        
        local_tz = ZoneInfo(time_zone) if time_zone else ZoneInfo("UTC")
        
        # Parse date_hint (convert server UTC to user's local timezone)
        now_utc = datetime.utcnow().replace(tzinfo=timezone.utc)
        now_local = now_utc.astimezone(local_tz)
        
        if date_hint.lower() == "yesterday":
            target_date = (now_local - timedelta(days=1)).date()
        elif date_hint.lower() == "today":
            target_date = now_local.date()
        elif date_hint.lower() == "tomorrow":
            target_date = (now_local + timedelta(days=1)).date()
        else:
            # Assume it's a date string like "2026-04-28"
            try:
                target_date = datetime.strptime(date_hint, "%Y-%m-%d").date()
            except:
                target_date = None
        
        # Filter by close_datetime on that date (in UTC range)
        if target_date:
            start_utc = datetime(target_date.year, target_date.month, target_date.day, tzinfo=local_tz).astimezone(timezone.utc)
            end_utc = start_utc + timedelta(days=1)
            query["close_datetime"] = {
                "$gte": start_utc.strftime("%Y-%m-%d %H:%M"),
                "$lt": end_utc.strftime("%Y-%m-%d %H:%M")
            }
    
    matched_tasks = await db.tasks.find(query).to_list(length=100)
    
    # **CRITICAL: Stop here if not exactly one match**
    if len(matched_tasks) == 0:
        return {"summary": f"No task matching '{task_name}' found for {username}"}
    
    if len(matched_tasks) > 1:
        # Multiple matches: show options and ask for clarification
        task_list = ", ".join([f"'{t['task_name']}'" for t in matched_tasks[:5]])
        return {"summary": f"Found {len(matched_tasks)} tasks matching '{task_name}' for {username}: {task_list}. Please specify which one or use the exact task name."}
    
    # Exactly one match
    task = matched_tasks[0]
    resolved_task_id = task["task_id"]
else:
    return {"summary": "Please provide either task_id or task_name"}

# Get username for confirmation
profile = await db.profiles.find_one({"user_id": task["user_id"]})
username = profile.get("name", "Unknown") if profile else "Unknown"
```

## Step 2 — Check if already completed
```python
if task.get("completed_at"):
    return {"summary": f"Task '{task['task_name']}' is already completed"}
```

## Step 3 — Determine effective completion timestamp (use close_datetime for expired)
```python
from datetime import datetime, timezone

now = datetime.utcnow()  # Naive UTC
now_str = now.strftime("%Y-%m-%d %H:%M")
close_datetime = task.get("close_datetime", "")

# If user provided explicit completed_at, honor it (if not future)
if completed_at:
    try:
        # Parse ISO 8601 format (e.g., "2026-04-29T14:30:00Z")
        dt = datetime.fromisoformat(completed_at.replace('Z', '+00:00'))
        naive_completed_at = (
            dt.astimezone(timezone.utc).replace(tzinfo=None)
            if dt.tzinfo is not None
            else dt
        )
        # Only use provided time if it's not in the future
        if naive_completed_at <= now:
            effective_completed_at = naive_completed_at
        else:
            effective_completed_at = now  # Reject future timestamp
    except Exception:
        effective_completed_at = now  # Parse error: use now
else:
    # No explicit completed_at provided
    # If date_hint provided: always use close_datetime (user said "from [date]")
    # If no date_hint: use close_datetime for expired, else use now
    
    if date_hint:
        # User specified a date context: backdate to task's close_datetime
        try:
            effective_completed_at = datetime.strptime(close_datetime, "%Y-%m-%d %H:%M")
        except Exception:
            effective_completed_at = now  # Parse error: fall back to now
    elif close_datetime < now_str:
        # Task is expired: backdate completion to close time
        try:
            effective_completed_at = datetime.strptime(close_datetime, "%Y-%m-%d %H:%M")
        except Exception:
            effective_completed_at = now  # Parse error: fall back to now
    else:
        # Task is still active or upcoming: mark as completed now
        effective_completed_at = now
```

## Step 4 — Mark task complete (using resolved_task_id)
```python
await db.tasks.update_one(
    {"task_id": resolved_task_id},
    {"$set": {
        "completed_at": effective_completed_at,
        "updated_at": datetime.utcnow(),
    }}
)
```

## Step 5 — Return success
```python
return {
    "summary": f"✓ Marked {username}'s '{task['task_name']}' complete",
    "task_id": resolved_task_id,
    "username": username,
    "task_name": task["task_name"],
    "nav_hint": "task_detail"
}
```

# Output Guidance

## Success message
- Active/current task: "✓ **Alex** completed **Daily Med - 9AM Phosphate** now"
- Expired/past task: "✓ **Alex** completed **Daily Med - 9AM Phosphate** (marked at 9:00 AM, when task closed)"
- Team member completion (with target_user_hint): "✓ Marked **Eimer's Phosphate** task complete (was due yesterday at 9 AM)"
- Show username for admin/parent context
- Include full task name in bold
- For expired tasks, mention the backdate completion time
- Keep message concise and confirmatory

## Already completed
- "**Phosphate** task is already completed (on 2026-04-28 at 9:15 AM)"

## Error cases
- Task not found: "Task not found or you don't have permission to complete it"
- Permission denied: "You don't have permission to complete this task"

## Data arrays
None — single operation returns a summary object.

# Authorization Rules
User can complete a task if ANY of these are true:
1. Task is their own (owner)
2. Task is in a team they admin
3. They created the task
4. Task owner is a member of a team they admin

If none: return 403 Forbidden

# Failure Handling
- Task not found → 404 Not Found
- Permission denied → 403 Forbidden
- Already completed → 200 OK with "already completed" message (idempotent)
- Future completed_at timestamp → backend ignores and uses now instead (no error)
- DB errors → retry once, then fail
