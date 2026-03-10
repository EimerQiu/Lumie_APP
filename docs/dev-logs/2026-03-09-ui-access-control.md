# UI Polish, Access Control & Reusable FAB

**Date:** 2026-03-09
**Scope:** Role-based UI improvements, task card colors, reusable animated FAB widget

---

## Decisions Made

1. **"Admin Dashboard" renamed to "All Tasks"** — The screen is now accessible to all team members (read-only), not just admins. Renaming reduces confusion and reflects its actual purpose.

2. **Role-based access in All Tasks screen** — Admins get swipe-to-complete and swipe-to-delete. Non-admins see a "View only" notice and no swipe. The check uses `_isUserAdminOfTeam()` which compares the task's `family_id` against the user's loaded teams.

3. **Teams must load before tasks** — Fixed a race condition where `_isUserAdminOfTeam()` was called before `TeamsProvider` had data. `initState` now awaits `teamsProvider.loadTeams()` before calling `loadMemberChips()` and `loadTasks()`.

4. **Email search hidden for non-admins** — Both `admin_dashboard_screen.dart` and `reward_calc_screen.dart` now conditionally hide the email search field using `AdminTasksProvider.isAdmin`.

5. **AnimatedFAB extracted as reusable widget** — The animated FAB menu was inline in `tasks_list_screen.dart`. Extracted to `lib/shared/widgets/animated_fab.dart` so any screen in the app can use it with a simple `items: [...]` list. The screen no longer needs `TickerProviderStateMixin`.

6. **Task card gradient colors** — Expanded from 16 to 24 diverse gradient pairs (Apple System Colors) to reduce color collision probability for tasks created in quick succession. Color is determined by `taskId.hashCode.abs() % 24`.

7. **Members can create team tasks** — Backend updated so team members (not only admins) can create tasks associated with their team, but only assigned to themselves. Admins can still assign to any member. `FamilyMemberSelector` shows a "Task Privacy" mode for members (team selection only, no member picker).

---

## New Files Created

### Frontend
- `lumie_activity_app/lib/shared/widgets/animated_fab.dart` — Reusable animated FAB with expandable menu items
  - `AnimatedFAB` widget — manages its own `AnimationController`, no `TickerProviderStateMixin` needed in parent
  - `FABMenuItem` data class — `{ icon, label, onTap }`

---

## Modified Files

### Frontend
- `lib/features/tasks/screens/tasks_list_screen.dart`
  - Renamed FAB button tooltip/label to "All Tasks", icon changed to `Icons.checklist`
  - Replaced inline FAB implementation with `AnimatedFAB` widget
  - Removed `TickerProviderStateMixin`, `AnimationController`, `_isMenuExpanded`, `_buildAnimatedFAB`, `_toggleMenu`, `_AnimatedMenuButton`

- `lib/features/tasks/screens/admin_dashboard_screen.dart`
  - Renamed screen title from "Admin Dashboard" to "All Tasks"
  - Fixed `initState`: now loads teams before tasks to ensure admin check works
  - Added `_isUserAdminOfTeam()` for per-task admin status (enables/disables swipe)
  - Non-admin members see tasks in read-only mode with "View only" badge
  - Email search hidden for non-admins via `provider.isAdmin`

- `lib/features/tasks/screens/reward_calc_screen.dart`
  - Email search section hidden for non-admins using `Consumer<AdminTasksProvider>`
  - Added 24 gradient color pairs for task card consistency

- `lib/features/tasks/widgets/task_card.dart`
  - Expanded gradient pairs from 16 → 24 for better color diversity

- `lib/features/tasks/widgets/family_member_selector.dart`
  - Detects admin vs member mode (`_isAdminMode`)
  - Admins: "Assign To" with team + member selection
  - Members: "Task Privacy" with team selection only (no member picker required)

- `lib/features/tasks/providers/admin_tasks_provider.dart`
  - Added `isAdmin` property
  - Non-admins no longer get an early return; they access dashboard in read-only mode

### Backend
- `lumie_backend/app/services/task_service.py`
  - `create_task()` and `batch_generate()` now allow team members to create team tasks (assigned to self only)
  - Admins can still assign tasks to other members

- `lumie_backend/app/services/admin_task_service.py`
  - `get_admin_task_list()` now allows non-admin access
  - Non-admins see only their own tasks; admins see all team members' tasks

---

## API Endpoints Changed

None — all changes are in existing endpoints' authorization logic.

---

## Testing Checklist

- [ ] Admin can swipe to complete/delete tasks in All Tasks screen
- [ ] Non-admin member sees tasks in read-only mode (no swipe, "View only" badge)
- [ ] Email search not visible for non-admin in All Tasks screen
- [ ] Email search not visible for non-admin in Reward Calculator
- [ ] Team member can create a team task (assigned to self)
- [ ] Team member cannot assign a team task to another member
- [ ] Admin can assign a team task to any team member
- [ ] AnimatedFAB works correctly on Med-Reminder task list screen
- [ ] Task cards show diverse colors (no two adjacent tasks with same color)
- [ ] All Tasks screen loads correctly after teams are fetched

---

## Future Work / Deferred

- Consider extracting gradient color pairs into a shared constant file (currently duplicated in `task_card.dart` and `reward_calc_screen.dart`)
- Non-admin Reward Calculator: auto-loads current user's tasks without requiring email input
- AnimatedFAB could accept a `mainIcon` and `color` override for use in other feature screens
