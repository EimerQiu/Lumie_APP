---
skill_id: today_tasks_and_medications
title: Today's Tasks and Medications
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [tasks, medications, reminders, schedule, today]
keywords: [what should I do, tasks today, medicine today, medication schedule, upcoming tasks, what's due, reminders, take medicine, daily schedule, what medication]
summary: Query today's tasks and medication reminders for the target user, showing what's due, completed, and upcoming.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    target_user_hint:
      type: string
    time_reference:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    pending_tasks:
      type: array
    completed_tasks:
      type: array
    upcoming_tasks:
      type: array
---

# Purpose
Use this skill when the user asks about their current tasks, medication schedule, or what they need to do today. This covers all 7 task types: Medicine, Life, Study, Exercise, Work, Meditation, Love.

# When To Use
- "What should I do now?"
- "What medicine do I need to take?"
- "Any upcoming reminders?"
- "What tasks are due today?"
- "Show me my schedule"
- "What medication should I take right now?"
- Parent asks about their child's tasks for today

# Required Inputs
- target user hint (often implicit)
- time reference (default: today in user's timezone)

# Runtime Rules
- Use `lumie_db` runtime
- Must include the requester's ping
- Must respect the user's timezone for date boundaries
- For team-admin queries, task access must be scoped to the correct team_id

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Query from: `tasks`, `profiles` (for timezone)
- Filter tasks by: user_id, open_datetime/close_datetime overlapping today
- Group by status: pending, completed, expired

# Data Model

## tasks collection fields
- `task_name`: string — human-readable name. For template-generated tasks, the format is `"{template_name} - {window_name}"` (e.g., "Meds_C - Cream", "Daily Med - 9AM Phosphate"). The window_name after the dash is the most useful part to show users.
- `task_type`: "Medicine" | "Life" | "Study" | "Exercise" | "Work" | "Meditation" | "Love"
- `open_datetime`: string "YYYY-MM-DD HH:MM" (UTC) — when the task window opens
- `close_datetime`: string "YYYY-MM-DD HH:MM" (UTC) — when the task window closes
- `status`: "pending" | "completed" | "expired"
- `done`: datetime or null — when the task was marked done
- `task_info`: string or null — optional notes

# Execution Plan
1. Resolve the target user
2. Get the user's timezone from their profile
3. Calculate today's date boundaries in the user's timezone (use ZoneInfo)
4. Query all tasks where open_datetime and close_datetime overlap with today
5. For each task, determine real status:
   - `done` is not null → completed
   - close_datetime < now → expired/missed
   - open_datetime <= now and close_datetime >= now → active right now (pending)
   - open_datetime > now → upcoming later today
6. Convert open_datetime/close_datetime to user's LOCAL time for display
7. Sort active and upcoming by open_datetime ascending

# Output Guidance

## Summary field (CRITICAL — this is what the user reads)
Write a **direct, actionable** summary in 2-3 sentences. Examples:
- "You have **Vitamin D** to take right now (due by 9:00 AM). You already took **Iron** earlier today. **DHA** is coming up at 4:00 PM."
- "You've completed all 3 medications for today — great job!"
- "You missed **Cream** (was due 1:00 AM - 8:00 AM). Your next medication is **Phosphate** at 12:00 PM."

Rules for summary:
- Use the **window name** (the part after " - " in task_name) as the medication/task display name, NOT the full task_name
- If task_name has no " - ", use the full task_name
- Show times in the user's LOCAL timezone (12-hour format with AM/PM)
- For medication queries: focus on what to take NOW and what's next
- For general task queries: list all pending tasks
- Bold the medication/task names using **markdown**
- Mention missed/expired tasks so the user is aware

## Data arrays
- Do NOT include task_id in the output — users don't need UUIDs
- Each task object should have: `name` (window name or task_name), `task_type`, `time_window` ("9:00 AM - 11:00 AM"), `status` ("active"|"completed"|"missed"|"upcoming")
- For completed tasks, include `completed_at` in local time

## Example result structure
```json
{
  "summary": "You need to take **Phosphate** right now (due by 2:00 PM). You already took **Vitamin D** this morning. **DHA** is coming up at 4:00 PM.",
  "active_now": [
    {"name": "Phosphate", "task_type": "Medicine", "time_window": "12:00 PM - 2:00 PM", "status": "active"}
  ],
  "upcoming": [
    {"name": "DHA", "task_type": "Medicine", "time_window": "4:00 PM - 7:00 PM", "status": "upcoming"}
  ],
  "completed": [
    {"name": "Vitamin D", "task_type": "Medicine", "time_window": "6:00 AM - 9:00 AM", "status": "completed", "completed_at": "7:30 AM"}
  ],
  "missed": [
    {"name": "Cream", "task_type": "Medicine", "time_window": "1:00 AM - 8:00 AM", "status": "missed"}
  ]
}
```

# Failure Handling
- Retry on query errors
- Fail immediately on permission denied
- If no tasks found, return empty arrays with a friendly note like "No tasks scheduled for today."
