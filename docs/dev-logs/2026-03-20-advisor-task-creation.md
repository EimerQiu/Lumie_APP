# Advisor Task Creation via Chat

**Date:** 2026-03-20
**Feature:** Enable the AI Advisor to create tasks/reminders through natural language conversation

## Overview

Extended the Advisor Chat's Claude tool_use system with a new `create_task` tool. When a user asks to set a reminder or add a task via chat, Claude extracts structured data (name, type, times, dates) and the backend creates tasks through the existing `TaskService` — no Docker sandbox needed. The response includes a `nav_hint` so the Flutter UI shows a "View your tasks" chip that navigates to the tasks screen.

## Key Decisions

1. **Direct TaskService call, not sandbox** — The existing analysis system runs AI-generated code in a read-only Docker sandbox. Task creation requires write access, so instead we added a new tool that calls `TaskService.create_task()` directly. All existing validation (subscription limits, timezone conversion, time ordering) is reused.
2. **Response type stays `"direct"`** — No new response type needed. Task creation is fast (no polling), so we return a `"direct"` reply with a `nav_hint` field added to the response.
3. **Single tasks, not templates** — Claude creates individual tasks for each date × time window combination. If the user says "every day this week", Claude lists all dates and the backend loops through them. Template creation via chat is deferred.
4. **Today's date + timezone in system prompt** — Claude needs current date context to compute relative dates ("this week", "tomorrow"). The user's profile timezone is included so Claude can inform the tool correctly.

## New Files Created

None — all changes are additions to existing files.

## Modified Files

### Backend (`lumie_backend/app/`)
- `services/advisor_service.py`
  - Added `CREATE_TASK_TOOL` definition (task_name, task_type, times[], dates[], task_info)
  - Added `_handle_create_task()` — loops dates × time windows, calls `TaskService.create_task()`, returns reply with `nav_hint: "task_list"`
  - Updated system prompt: task creation guidance, today's date context, user timezone
  - Registered both tools (`run_data_analysis` + `create_task`) in Claude API call
  - Refactored tool_use routing to dispatch by tool name
- `api/advisor_routes.py`
  - Added `nav_hint` field to `AdvisorChatResponse` model
  - Passes `nav_hint` from service result to response

### Frontend (`lumie_activity_app/lib/`)
- `core/services/advisor_service.dart`
  - Added `navHint` field to `AdvisorResponse`, parsed from `nav_hint` in JSON
- `features/advisor/screens/advisor_screen.dart`
  - Added `navHint` field to `_Message`
  - Passes `navHint` through on direct replies
  - Added `_buildNavHintChip()` in `_ChatBubble` — renders "View your tasks" chip navigating to `TasksListScreen`

## API Changes

No new endpoints. Existing `POST /api/v1/advisor/chat` response now includes optional `nav_hint` field:

```json
{
  "type": "direct",
  "reply": "Done! I've created **Take Metformin** for you.",
  "nav_hint": "task_list"
}
```

## Task Creation Tool Schema

```json
{
  "task_name": "Take Metformin",
  "task_type": "Medicine",
  "times": [{"open_time": "08:00", "close_time": "09:00"}],
  "dates": ["2026-03-20", "2026-03-21", "2026-03-22"],
  "task_info": "optional notes"
}
```

## Testing Checklist

- [ ] User asks "remind me to take my medicine at 8am tomorrow" → task created, nav chip shown
- [ ] User asks "set a meditation reminder every morning this week" → multiple tasks created
- [ ] User asks "what are my tasks today" → still routes to `run_data_analysis` (not `create_task`)
- [ ] User asks general question → still returns direct reply without nav_hint
- [ ] Subscription date-range limit enforced (free = 7 days)
- [ ] Invalid time/date input handled gracefully with error message
- [ ] Nav hint chip navigates to TasksListScreen

## Future Work

- Template creation via chat ("set a recurring daily reminder")
- Team task assignment via chat ("remind [child name] to...")
- Task editing/deletion via chat
- Confirmation step before creating many tasks (e.g., 30+ days)
