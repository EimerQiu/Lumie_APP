# Med-Reminder PRD Supplement Implementation

**Date:** 2026-03-05
**Scope:** Missing modules from Med-Reminder PRD Supplement

## Decisions Made

1. **Status rename: "overdue" -> "expired"** - PRD Supplement uses "expired" terminology. Added `EXPIRED` enum value alongside legacy `OVERDUE`. Backend lazily migrates old "overdue" records to "expired" on read. Frontend normalizes "overdue" to "expired" in `TaskStatus.fromString()`.

2. **Admin authority model** - Admin can manage tasks for any user who is a member of any team the admin manages. Authority check: task is in admin's team, OR admin created the task, OR task's user is in one of admin's teams.

3. **Reward calculation is client-side** - Per PRD, the backend only provides paginated task data. All range selection and reward/fine math happens in the Flutter UI.

4. **FamilyMemberSelector** - Only renders if user is admin of at least one team. Defaults to "Personal Tasks" (no team/member selection). Admin must select both a team AND a member to assign a team task.

## New Files Created

### Backend
- `lumie_backend/app/api/admin_task_routes.py` - Admin API routes (4 endpoints)
- `lumie_backend/app/services/admin_task_service.py` - Admin task business logic

### Frontend
- `lumie_activity_app/lib/features/tasks/providers/admin_tasks_provider.dart` - State management for admin dashboard
- `lumie_activity_app/lib/features/tasks/screens/admin_dashboard_screen.dart` - Admin global task view
- `lumie_activity_app/lib/features/tasks/screens/reward_calc_screen.dart` - Reward/fine calculator
- `lumie_activity_app/lib/features/tasks/widgets/family_member_selector.dart` - Reusable team/member assignment widget

## Modified Files

### Backend
- `lumie_backend/app/models/task.py` - Added `EXPIRED` status, admin models (`AdminTaskData`, `AdminTaskListResponse`, `AdminTaskCompleteRequest`, `RptTaskItem`)
- `lumie_backend/app/services/task_service.py` - Updated `_check_overdue_tasks()` to use "expired" and normalize legacy "overdue"
- `lumie_backend/app/main.py` - Registered admin_task_router

### Frontend
- `lumie_activity_app/lib/shared/models/task_models.dart` - Added `expired` enum, normalized "overdue"->"expired", added admin models (`AdminTaskData`, `AdminTaskListResponse`, `RptTaskItem`)
- `lumie_activity_app/lib/core/constants/api_constants.dart` - Added admin endpoint constants
- `lumie_activity_app/lib/core/services/task_service.dart` - Added admin API methods (getAdminTaskList, adminCompleteTask, adminDeleteTask, getRewardCalcTasks)
- `lumie_activity_app/lib/features/tasks/providers/tasks_provider.dart` - Renamed `overdueTasks` -> `expiredTasks`
- `lumie_activity_app/lib/features/tasks/screens/tasks_list_screen.dart` - Added admin dashboard AppBar button, updated empty state with admin link
- `lumie_activity_app/lib/features/tasks/screens/create_task_screen.dart` - Integrated FamilyMemberSelector, passes team_id/user_id to createTask
- `lumie_activity_app/lib/features/tasks/screens/batch_generate_screen.dart` - Integrated FamilyMemberSelector, passes team_id/user_id to preview/generate
- `lumie_activity_app/lib/main.dart` - Registered AdminTasksProvider, admin dashboard and reward calc routes

## API Endpoints Added

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/admin/task-list-ios` | Global admin task view with email filter, pagination |
| POST | `/api/v1/admin/task_complete` | Admin marks any member's task as completed |
| DELETE | `/api/v1/admin/delete_task/{task_id}` | Admin permanently deletes a task |
| GET | `/api/v1/admin/reward-calc` | Tasks for reward calculation (paginated, chronological) |

## New DB Collections/Indexes

No new collections. Existing `tasks` collection indexes are sufficient for admin queries (user_id+status, user_id+open_datetime, team_id+user_id).

## Testing Checklist

- [ ] Admin dashboard loads for users who are team admins
- [ ] Admin dashboard returns 403 for non-admin users
- [ ] Email search filters tasks correctly
- [ ] Member quick-filter chips load and filter
- [ ] Previous/Upcoming task split works correctly
- [ ] Load More Previous/Upcoming pagination works
- [ ] Pull-to-refresh resets pagination
- [ ] Admin swipe-to-complete updates status badge (task stays visible)
- [ ] Admin swipe-to-delete removes task from list
- [ ] Reward calculator: email search loads tasks
- [ ] Reward calculator: checkbox range selection works
- [ ] Reward calculator: live reward/fine calculation updates
- [ ] FamilyMemberSelector shows for admins only
- [ ] FamilyMemberSelector defaults to "Personal Tasks"
- [ ] Task creation with team/member assignment works
- [ ] Batch generation with team/member assignment works
- [ ] "expired" status displays correctly (red badge)
- [ ] Legacy "overdue" tasks are normalized to "expired"
- [ ] Empty state shows admin dashboard link

## Future Work / What's Deferred

- Push notifications for task reminders
- Task edit/update endpoint
- Admin dashboard: team icon button to open team management sheet
- Reward calculation: export/share reward summary
- Task card color assignment: currently hash-based (6 colors), PRD mentions 16 gradient pairs
