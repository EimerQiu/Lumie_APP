# Med-Reminder Feature - Development Log

**Date:** 2026-03-01
**Status:** Implementation complete, ready for testing
**Scope:** Full feature - Tasks + Templates + Batch Generation + Team task coordination

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Subscription limit (Free) | 6 active tasks | User preference (PRD said 2) |
| Push notifications | Deferred | Build task system first, add notifications later |
| Overdue detection | Lazy (on fetch) | No cron job needed; backend marks overdue when tasks are queried |
| Task ownership | `user_id` = assignee, `created_by` = creator | Only assignee completes; both can delete |
| Date format | String `"yyyy-MM-dd HH:mm"` | Per PRD spec; avoids timezone conversion issues |

---

## Backend

### New Files

| File | Purpose |
|------|---------|
| `lumie_backend/app/models/task.py` | Pydantic models: TaskType (7 types), TaskStatus, TaskCreate, TaskResponse, TimeWindow, TemplateCreate/Response, BatchGenerateRequest/Response |
| `lumie_backend/app/services/task_service.py` | TaskService class: CRUD tasks/templates, subscription limit checks, batch generation, team admin authorization, lazy overdue marking |
| `lumie_backend/app/api/task_routes.py` | FastAPI router with 10 endpoints (template routes before parameterized routes to avoid path conflicts) |

### Modified Files

| File | Change |
|------|--------|
| `lumie_backend/app/core/subscription_helpers.py` | Added `TASK_LIMIT_FREE=6`, `TASK_LIMIT_PRO=999999`, `get_task_limit()`, `raise_task_limit_error()` |
| `lumie_backend/app/core/database.py` | Added indexes for `tasks` (5 indexes) and `task_templates` (2 indexes) collections |
| `lumie_backend/app/main.py` | Registered `task_router` with `/api/v1` prefix |

### API Endpoints

```
POST   /api/v1/tasks                     Create task (sub limit checked)
GET    /api/v1/tasks                     List tasks (?status=&date=)
POST   /api/v1/tasks/{task_id}/complete   Complete task
DELETE /api/v1/tasks/{task_id}            Delete task

GET    /api/v1/tasks/templates            List templates
POST   /api/v1/tasks/templates            Create template
GET    /api/v1/tasks/templates/{id}       Get template detail
DELETE /api/v1/tasks/templates/{id}       Delete template

POST   /api/v1/tasks/batch/preview        Preview batch generation
POST   /api/v1/tasks/batch/generate       Execute batch generation
```

### New MongoDB Collections

| Collection | Key Indexes |
|------------|-------------|
| `tasks` | `task_id` (unique), `[user_id, status]`, `[user_id, open_datetime]`, `[team_id, user_id]`, `created_by` |
| `task_templates` | `id` (unique), `created_by` |

---

## Frontend

### New Files

| File | Purpose |
|------|---------|
| `lib/shared/models/task_models.dart` | Dart models: Task (with progress calc, color index), TaskType, TaskStatus, RepeatTaskTemplate, TimeWindow, response wrappers |
| `lib/core/services/task_service.dart` | Singleton API client with token management, 403 subscription error parsing |
| `lib/features/tasks/providers/tasks_provider.dart` | ChangeNotifier state: task list, templates, 180s auto-polling, subscription limit display |
| `lib/features/tasks/widgets/task_card.dart` | Dark card with 6 gradient combos (PRD spec), swipe-to-complete/delete via Dismissible |
| `lib/features/tasks/widgets/task_type_selector.dart` | Horizontal chip row for 7 task categories |
| `lib/features/tasks/widgets/time_window_editor.dart` | Time window input: name field, time pickers, midnight toggle |
| `lib/features/tasks/screens/tasks_list_screen.dart` | Main list: pull-to-refresh, subscription banner, FAB with limit check, complete/delete dialogs |
| `lib/features/tasks/screens/create_task_screen.dart` | Form: name, type selector, date/time pickers, optional notes |
| `lib/features/tasks/screens/templates_list_screen.dart` | Template cards with "Create Tasks" and delete actions |
| `lib/features/tasks/screens/create_template_screen.dart` | Template form with dynamic time window list |
| `lib/features/tasks/screens/batch_generate_screen.dart` | Date range picker, preview button, generate button |

### Modified Files

| File | Change |
|------|--------|
| `lib/features/auth/providers/auth_provider.dart` | Added `TaskService` instance, renamed `_setTeamServiceToken()` to `_setServiceTokens()` (sets both team + task tokens), clears task token on logout |
| `lib/main.dart` | Registered `TasksProvider` in MultiProvider, added 5 named routes + 1 `onGenerateRoute`, added "Med-Reminder" nav item in Settings screen, initialized `TasksProvider` subscription tier |
| `lib/core/constants/api_constants.dart` | Added task endpoint constants |

### Navigation Flow

```
Settings (Me tab) > "Med-Reminder" > TasksListScreen
  -> FAB "Add Task" > CreateTaskScreen
  -> AppBar "Templates" icon > TemplatesListScreen
      -> FAB "New Template" > CreateTemplateScreen
      -> "Create Tasks" button > BatchGenerateScreen
```

---

## Task Type Categories

Medicine, Life, Study, Exercise, Work, Meditation, Love

## Card Gradient Colors (6 combos, selected by `taskId.hashCode % 6`)

1. Orange -> Red (#FF9500 -> #FF3B30)
2. Blue -> Purple (#007AFF -> #5856D6)
3. Green -> Yellow (#34C759 -> #FFCC00)
4. Pink -> Purple (#FF2D55 -> #5856D6)
5. Teal -> Blue (#5AC8FA -> #007AFF)
6. Indigo -> Pink (#5856D6 -> #FF2D55)

---

## Testing Checklist

- [ ] Backend: Start server, verify all 10 endpoints via `/docs`
- [ ] Create task: verify subscription limit at 6 for free users
- [ ] Complete task: verify only assignee can complete
- [ ] Delete task: verify both assignee and creator can delete
- [ ] Template: create with multiple time windows
- [ ] Batch generate: preview shows correct count, generate creates tasks
- [ ] Team tasks: admin creates task for member, member sees it
- [ ] Upgrade prompt: shown when free user hits limit
- [ ] Auto-polling: tasks refresh every 180s
- [ ] Overdue: tasks past close_datetime show "Overdue" badge

---

## Not Included (Future Work)

- Push notifications for task reminders
- Task edit/update endpoint
- Task completion analytics (P2 per PRD)
- Notification preferences in Settings
