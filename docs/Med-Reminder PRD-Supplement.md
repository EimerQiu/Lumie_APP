# Med-Reminder PRD — Supplement

> **Purpose**: This document supplements the existing `## Med-Reminder` section in the main PRD. It documents features fully implemented in Automom that were omitted from the original PRD, causing incomplete development of the new app. All sections below should be merged into the main PRD's Med-Reminder chapter.

---

## Missing Module 1: Admin Dashboard (Global Task View)

### Overview

The Admin Dashboard is a dedicated management view available exclusively to team admins. It provides a **global view of all tasks across the team**, enabling admins to monitor, complete, or delete any member's tasks without being restricted to their own task list. This is fundamentally different from the member-facing task list (Section 2.2), which shows only the current user's own tasks.

In Automom, the admin role is equivalent to the team admin role in the Lumie Team System. Any user who is admin of at least one team gains access to this dashboard.

---

### Role Requirement

| User Role | Can Access Admin Dashboard |
|---|---|
| Team admin (of any team) | ✅ Yes |
| Regular member | ❌ No — member-facing task list only |

The admin dashboard tab is only rendered if the current user holds the `admin` role on any team.

---

### Layout

The Admin Dashboard is split into two primary sections rendered in a single scrollable list:

#### Previous Tasks Section

Tasks whose `open_datetime` is at or before the current time. Sorted ascending by `open_datetime` (oldest first).

- A **"Load More Previous Tasks"** button appears at the **top** of this section
- Clicking it fetches 10 more previous tasks (paginated, offset-based)
- While loading, a spinner is shown inline

#### Upcoming Tasks Section

Tasks whose `open_datetime` is after the current time. Sorted ascending by `open_datetime`.

- A **"Load More Upcoming Tasks"** button appears at the **bottom** of this section
- Same paginated behavior as Previous Tasks
- Pull-to-refresh reloads both sections from offset 0

---

### User Search / Filter

**Email search bar** at the top:

- A text field where the admin enters a member's email address
- A search (magnifying glass) button triggers `GET /admin/task-list-ios?email={email}&...`
- If the field is left empty and the admin clicks search, an alert is shown: "Please enter an email address to search"
- When no email is entered, the view may show all tasks visible to the admin

**Family member quick-filter chips:**

When the admin belongs to at least one team as admin, a **horizontal scrollable row of member chips** appears below the search bar. Each chip shows a team member's name. Tapping a chip auto-fills the email field and immediately fetches that member's tasks. This is the primary way admins navigate between members.

- Chips use distinct background colors (indigo / purple / blue / teal / cyan variants)
- Duplicate members across teams are deduplicated (each member appears only once)
- A "team icon" button on the far left of the chip row opens the family/team management sheet

---

### Task Card (Admin View)

Each task row in the admin view displays richer information than the member-facing card:

| Field | Source | Display |
|---|---|---|
| Task name | `rpttask_name` | Large, bold headline |
| Task description | `rpttask_info` | Secondary line, gray |
| Time window | `open_datetime` → `close_datetime` | Formatted datetime range |
| Task type | `rpttask_type` | Caption, gray |
| Status badge | `status` | Colored pill (see below) |
| Assigned user | `username` | Caption: "User: {name}" |
| Team name | `family_name` | Caption: "Team: {name}" (shown only if present) |
| Subtask list | `rpttask_list[]` | Listed under "Subtasks:" header if non-empty |

**Status badge color mapping:**

| Status | Badge color |
|---|---|
| `completed` | Green |
| `pending` | Blue |
| `expired` | Red |

---

### Admin Actions on Tasks

**Swipe-left actions on each task card:**

- **Complete** (green): Admin marks the task as completed on behalf of the assigned user. Sends `POST /admin/task_complete`. On success, the task's status badge updates to "Completed" in place (no removal from list — unlike the member-facing view).
- **Delete** (red): Admin permanently deletes the task. Sends `DELETE /admin/delete_task/{task_id}`. On success, the task is removed from the local list immediately.

These actions are available for **any** task visible to the admin, regardless of which user it belongs to.

---

### Data Model (Admin Task)

The admin task object contains additional fields beyond the basic `Task` model used in the member view:

```
AdminTaskData {
  task_id: string,
  user_id: string,
  username: string,              // Display name of assigned user
  task_type: string,
  open_datetime: ISO8601 string,
  close_datetime: ISO8601 string,
  status: "pending" | "completed" | "expired",
  rpttask_id: string,            // Template ID (if from a template)
  rpttask_name: string,          // Task/template name
  rpttask_info: string,          // Task description
  rpttask_type: string,          // Task type from template
  rpttask_list: [RptTaskItem],   // Time-window subtasks from template
  small_task_id: string,         // Sub-task index within a template occurrence
  min_interval: int,             // Minimum interval (minutes) from template
  family_id: string | null,      // Team ID if assigned via a team
  family_name: string | null     // Team display name
}

RptTaskItem {
  id: int,
  name: string,           // Window name (e.g., "Morning", "Afternoon")
  open_time: int,         // Minutes from midnight (e.g., 480 = 08:00)
  close_time: int         // Minutes from midnight (e.g., 570 = 09:30)
}
```

---

### API Endpoints (Admin Dashboard)

```
GET /admin/task-list-ios
  Query params:
    email: string (filter by user email, optional)
    time_zone: string (IANA timezone, e.g. "America/Los_Angeles")
    current_time: ISO8601 datetime with timezone offset
    previous_offset: int (pagination offset for previous tasks, default 0)
    upcoming_offset: int (pagination offset for upcoming tasks, default 0)
  Response: [AdminTaskData]
  Notes:
    - Returns 10 previous tasks and 10 upcoming tasks per page by default
    - Pagination controlled by offset params

POST /admin/task_complete
  Request Body:
    { "task_id": string, "time_zone": string }
  Response: 200 OK
  Notes:
    - Updates task status to "completed" server-side
    - Does NOT remove the task from the admin list (it stays visible)

DELETE /admin/delete_task/{task_id}
  Response: 200 OK
  Notes:
    - Permanently deletes the task
    - Immediately removes from admin list on success
```

---

### Pagination Behavior

- Initial load: `previous_offset=0`, `upcoming_offset=0`
- "Load More Previous" → increment `previous_offset` by 10, append results to top section
- "Load More Upcoming" → increment `upcoming_offset` by 10, append results to bottom section
- Duplicate detection: tasks already in the list (by `task_id`) are filtered out before appending
- Pull-to-refresh: resets both offsets to 0 and replaces the full task list

---

## Missing Module 2: Reward / Incentive Calculation System

### Overview

The Reward Calculation view is an admin-only tool that allows team admins to calculate a **net reward or fine** for a member based on their task completion history over a selected date range. This feature connects task completion data directly to a configurable allowance or incentive system.

It is accessed from the Admin Dashboard via a **dollar-sign (💲) icon button** in the search bar area. The admin must have entered a member's email before activating this view.

---

### Workflow

1. Admin enters member email in the search bar
2. Admin taps the dollar-sign icon → the Reward Calculation view opens and loads the member's task history
3. Tasks are displayed chronologically (ascending `close_datetime`)
4. Admin **selects exactly two tasks** using checkboxes — these define the start and end of the date range
5. All tasks between (and including) the two selected tasks are counted
6. The system automatically calculates:
   - Number of **completed** tasks in range
   - Number of **expired** tasks in range
   - **Net reward** = (completed × reward_per_task) − (expired × fine_per_task)
7. The admin can adjust `reward_per_task` and `fine_per_task` amounts in real-time text fields
8. Results update immediately as the admin changes inputs

---

### UI Layout

**Header bar:**

- Back button (returns to global task view)
- Range count label: shows "X tasks in range" once two tasks are selected, or "Select end task" if only one is selected

**Reward settings panel:**

```
[ Completed ] reward  [____] ×  {completed_count}
[ Expired   ] fine    [____] ×  {expired_count}
                     | Total reward: {net_value}
```

- `Completed` and `Expired` are shown as colored status badges (green / red)
- Reward and fine per-task are numeric input fields (decimal)
- Total reward is calculated live and displayed in blue
- If net reward is negative, it represents a net fine

**Task list:**

- Tasks sorted ascending by `close_datetime`
- Each task row includes a checkbox on the left
- Tasks within the selected range have a light blue background highlight
- A "Load More Tasks" button at the top fetches 10 additional (older) tasks

---

### Range Selection Logic

```
Selected tasks are stored as a set of task IDs.
The range is defined as [min_index, max_index] within the sorted list.

If fewer than 2 tasks selected: no range, calculation shows 0 / 0 / 0
If 2 or more tasks selected:
  start_index = earliest selected task's index in sorted list
  end_index = latest selected task's index in sorted list
  count = end_index - start_index + 1
  (inclusive of both endpoints)

Tasks within range are evaluated for status:
  completed_count = count of tasks in range with status == "completed"
  expired_count = count of tasks in range with status == "expired"
  pending tasks are neither rewarded nor fined

Net reward = (completed_count × reward_per_task) - (expired_count × fine_per_task)
```

---

### API Endpoints (Reward Calculation)

```
GET /admin/reward-calc
  Query params:
    email: string (member email, required)
    time_zone: string (IANA timezone identifier)
    offset: int (pagination offset for loading more, default 0)
  Response: [AdminTaskData]
  Notes:
    - Returns tasks in chronological order suitable for reward calculation
    - Pagination: 10 tasks per page (older tasks loaded on demand)
    - The calculation itself is done entirely client-side
```

---

## Missing Module 3: Task Expiry System

### Overview

The current PRD lists `"expired"` as a task status but does not describe the business logic that causes tasks to expire or how expiry is handled across the app. This section defines that behavior.

---

### Expiry Definition

A task becomes **expired** when the current time exceeds the task's `close_datetime` and the task has not been marked as completed. The transition from `pending` → `expired` is computed server-side at query time, not through a scheduled job (though either implementation is acceptable).

---

### Expiry Handling by View

**Member-facing task list (SimpleView):**

- Fetches only **pending** tasks for the current user
- Expired tasks are **not shown** in this view
- After the `close_datetime` passes, the task naturally disappears from the list on the next refresh (every 180 seconds)

**Admin Dashboard:**

- Shows tasks in **all statuses**: pending, completed, and expired
- Expired tasks display a **red "Expired" badge**
- Expired tasks remain in the admin list for historical review
- Admin can still delete expired tasks via swipe action

**Reward Calculation:**

- Expired tasks are explicitly counted as **negatives** in the reward calculation
- `expired_count` contributes to the fine deduction: `expired_count × fine_per_task`

---

### Expiry Edge Cases

| Scenario | Behavior |
|---|---|
| Task completed before close_datetime | Status = "completed", never expires |
| Task not completed by close_datetime | Status becomes "expired" on next server query |
| Admin completes task after expiry | Admin view updates status to "completed"; reward calculation reflects this |
| Task deleted by admin | Removed from all views; not counted in reward calculation |

---

## Missing Module 4: Task Assignment UI (FamilyMemberSelector)

### Overview

The FamilyMemberSelector is a reusable UI component used inside both single-task creation and batch task generation flows. It allows the creator to assign a task to either themselves (personal) or a specific member of a specific team.

This component is critical for the admin workflow: without it, admins cannot create tasks for team members.

---

### Component Behavior

The selector renders two sub-sections:

#### Family / Team Selection

A **horizontal scrollable card row** showing:
- "Personal Tasks" card (default, blue-purple gradient) — assigns task to the current user
- One card per team the admin manages — assigns the task to that team context

Selecting a team card changes the member selection below.

#### Member Selection

Appears only when a team is selected. Shows individual member cards (one per member of the selected team). The admin selects the specific member to assign the task to.

If "Personal Tasks" is selected, no member picker is shown; the task is assigned to the current user's `user_id`.

---

### Assignment Logic

```
If selectedFamilyId == nil:
  task.user_id = current_user.user_id
  task.family_id = nil

If selectedFamilyId != nil AND selectedMemberId != nil:
  task.user_id = selectedMemberId
  task.family_id = selectedFamilyId
```

Both `user_id` and `family_id` are sent in the task creation request body.

---

### Usage

This component is embedded in:
1. **Single Task Creation** (Add Task screen)
2. **Batch Task Generation** (Create Tasks from Template screen)

In both cases, the admin must first load their administered teams, then optionally select a family and member. The component defaults to "Personal Tasks" (current user) if no selection is made.

---

## Amendments to Existing Sections

### Amendment to Section 2.2 — Task List Display

Add the following behavior that was omitted:

**Empty State:** When the user has no pending tasks, the task list shows an empty state with:
- A calendar icon
- "No Tasks Available" heading
- Explanatory text: directing the user to check the Admin Dashboard for all previous and upcoming tasks
- A direct link/button to open the Admin Dashboard

**Task Card Colors:** The gradient color pairs used for task progress bars should be assigned consistently. In Automom this is done by random selection from a set of 16 gradient pairs on each render; for production, color should be deterministically derived from the task ID (e.g., `hash(task_id) mod 16`) to avoid flickering on re-render.

---

### Amendment to Section 2.3 — Task Creation

Add the following detail:

**Timezone field:** Task creation includes an explicit timezone picker. The selected timezone governs how `open_datetime` and `close_datetime` are interpreted and stored. Defaults to the device's current timezone.

**Template shortcut in creation view:** The single-task creation screen also embeds the full template list (see Section 3.2). This allows admins to create batch tasks from a template directly from the task creation sheet, without navigating to a separate templates screen.

---

### Amendment to Section 3.4 — Batch Task Generation

Add the following detail:

**Assigned user defaults:** When the batch task creation sheet is opened, `assigned_user_id` defaults to the current user's own ID. The admin can change this via the FamilyMemberSelector (see Missing Module 4 above).

**API Endpoint (actual):**

The batch creation uses a single server-side endpoint, not individual per-task `POST /api/v1/tasks/` calls:

```
POST /repeat_task/create_tasks/{template_id}
  Request Body:
    {
      "from_date": "yyyy-MM-dd HH:mm",
      "days": int (1–30),
      "timezone": string,
      "assigned_user_id": string,
      "family_id": string | null
    }
  Response: 200 OK (server generates all tasks)
```

The server calculates all task instances from the template's time windows and the given date range, rather than the client sending one request per task.

---

## Summary of All Missing Features

| Feature | Priority | Description |
|---|---|---|
| Admin Dashboard | P0 | Global task view, search by email, per-member task management |
| Admin Task Completion | P0 | Admin can mark any member's task complete |
| Admin Task Deletion | P0 | Admin can delete any member's task |
| Family Member Quick Chips | P0 | One-tap filter by member in admin view |
| Task Pagination | P1 | Load 10 more previous / upcoming tasks on demand |
| Task Expiry Logic | P0 | Expired status definition, display, and reward impact |
| Reward Calculation | P1 | Admin tool for date-range reward/fine calculation |
| Reward Range Selection | P1 | Checkbox-based range selection in reward view |
| FamilyMemberSelector | P0 | Reusable assignment UI for task creation flows |
| Empty State (task list) | P1 | Empty state with link to admin dashboard |
| Timezone in task creation | P0 | Explicit timezone picker for task times |
| Batch task via single API | P0 | Server-side batch generation endpoint |