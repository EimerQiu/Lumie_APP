# Skill Files & Pydantic Model Audit

Date: 2026-04-10  
Reviewed: 6 skill files, 3 key Pydantic models

## Summary

**Finding**: Skill `.md` files duplicate schema information that should link to Pydantic models.

**Goal**: Make it easy for developers to find the **single source of truth** when implementing a skill query.

---

## Current State

### ✅ What's Working
- Pydantic models are well-documented with Field descriptions and enums
- Skill files have practical query examples
- Models contain all necessary validation and type info

### ❌ Problems
1. **Duplication** — Schema descriptions in skill files duplicate what's in models
2. **No Links** — Skill files don't reference the Pydantic models
3. **Discovery Tax** — Implementing a skill requires reading `.md` + `.py` in parallel
4. **Maintenance Risk** — If a model changes, the skill `.md` docs can go stale

---

## Skill-by-Skill Audit

| Skill | Collections | Model Links | Issue |
|-------|------------|------------|-------|
| **tasks_query** | `tasks` | ❌ None | Inline field docs duplicate task.py |
| **health_data_query** | `sleep_sessions`, `daily_steps`, `hr_readings`, `hrv_readings`, `temperature_readings`, `spo2_readings`, `activities`, `walk_tests`, `rest_days` | ❌ None | Heavy inline duplication; multiple models not linked |
| **dayprint_followup** | `dayprints`, `profiles` | ❌ None | Inline descriptions; models not referenced |
| **team_member_health_snapshot** | `profiles`, `team_members`, `sleep_sessions`, `activities`, `daily_steps`, `hrv_readings`, `tasks` | ❌ None | Lists fields inline; no model references |
| **ring_live_measure** | `ring_command_requests` | ❌ None | Has query examples but no model link |
| **comprehensive_health_assessment** | (none—synthesizes from other skills) | N/A | OK (no DB queries) |

---

## Detailed Findings

### 1. tasks_query.md

**Current state (lines 67–75):**
```markdown
## tasks collection fields
- `task_name`: string — For template-generated tasks...
- `task_type`: "Medicine" | "Study" | "Exercise" | ...
- `open_datetime`: string "YYYY-MM-DD HH:MM" ...
- `close_datetime`: string ...
```

**Issue**: These field descriptions duplicate info in `models/task.py` (lines 35–43)

**Fix**: Replace with link
```markdown
## Schema
See [`TaskModel` in models/task.py](../../models/task.py)

Relevant fields for this skill:
- `task_name` (string)
- `task_type` (TaskType enum)
- `open_datetime` (string, "YYYY-MM-DD HH:MM" UTC format)
- `close_datetime` (string, "YYYY-MM-DD HH:MM" UTC format)
- `done` (MongoDB datetime if completed, field absent if not)
- `task_info` (string or null)
```

### 2. health_data_query.md

**Current state (lines 40–67):** Inline schema for 8+ collections with full field docs

**Issue**: 
- Duplicates `activity.py`, `hrv.py`, `hr.py`, `sleep.py`, `spo2.py`, `temperature.py` docs
- No links to models — developers must hunt for corresponding `.py` files
- Makes it hard to keep docs in sync when models change

**Fix**: Replace collection contracts with links
```markdown
## Collection Schemas

- `sleep_sessions` — See [SleepSession model](../../models/sleep.py)
- `daily_steps` — See [DailySteps model](../../models/steps.py)
- `hr_readings` — See [HRReading model](../../models/hr.py)
- `hrv_readings` — See [HRVReading model](../../models/hrv.py)
- `temperature_readings` — See [TemperatureReading model](../../models/temperature.py)
- `spo2_readings` — See [SPO2Reading model](../../models/spo2.py)
- `activities` — See [ActivityRecord model](../../models/activity.py)
- `walk_tests` — See [WalkTestResult model](../../models/activity.py)

Practical interpretation rules (keep these, since they add context for queries):
- `daily_steps` is one document per day, keyed by `(user_id, date_str)` ...
```

### 3. dayprint_followup.md

**Current state (lines 95–104):** Describes `dayprints` and `profiles` inline

**Issue**: No link to `models/dayprint.py` or `models/user.py` (profiles)

**Fix**: Add links
```markdown
## Collection Schemas
- `dayprints` — See [DayprintResponse model](../../models/dayprint.py)
- `profiles` — See [Profile model](../../models/user.py)

Event structure (from DayprintEvent):
- `type`: Event type (e.g. "important_insight", "advisor_chat")
- `timestamp`: ISO datetime (UTC)
- `data`: Object with event-specific fields
```

### 4. team_member_health_snapshot.md

**Current state (lines 64–90):** Lists fields inline for 6 collections

**Issue**: Duplication; no model links

**Fix**: Replace with
```markdown
## Data Scope and Schemas

This snapshot uses ring-synced data from:
- `profiles` — See [Profile model](../../models/user.py)
- `team_members` — See [TeamMember model](../../models/team.py)
- `sleep_sessions` — See [SleepSession model](../../models/sleep.py)
- `activities` — See [ActivityRecord model](../../models/activity.py)
- `daily_steps` — See [DailySteps model](../../models/steps.py)
- `hrv_readings` — See [HRVReading model](../../models/hrv.py)
- `tasks` — See [TaskResponse model](../../models/task.py)

Relevant fields per domain:
- From `sleep_sessions`: bedtime, wake_time, total_sleep_minutes, ...
```

### 5. ring_live_measure.md

**Current state (lines 65–79):** Describes result data contract inline

**Issue**: No reference to `models/ring_command.py` (if it exists)

**Fix**: Add link (after checking if model exists)
```markdown
## Result Data Contract

See [RingCommandRequest model](../../models/ring_command.py) for full schema.

Expected result shapes:
```

---

## Action Items

### Priority 1: Link skill files to models
- [ ] tasks_query.md → link to models/task.py
- [ ] health_data_query.md → link to models/{sleep,hr,hrv,spo2,temperature,activity,steps}.py
- [ ] dayprint_followup.md → link to models/dayprint.py, models/user.py
- [ ] team_member_health_snapshot.md → link to relevant model files
- [ ] ring_live_measure.md → link to models/ring_command.py (verify exists)

### Priority 2: Remove duplication
- Delete inline field descriptions that are already in models
- Keep **only**:
  - Links to model files
  - Practical interpretation rules (e.g., "daily_steps is keyed by...")
  - Query examples with context

### Priority 3: Verify model existence
- Check if models exist for all referenced collections
- Create missing models if needed (e.g., `ring_command.py`, `rest_days.py`, `profiles.py`)

---

## New Pattern: Schema Section in Skills

Once implemented, every skill `.md` should have this structure:

```markdown
## Schema

See:
- [TaskModel](../../models/task.py) for task fields
- [DayprintResponse](../../models/dayprint.py) for dayprint structure

Relevant fields for **this skill**:
- `task_name` (string) — task display name
- `open_datetime` (string, ISO format) — window opens
```

This gives developers:
1. **Single source of truth** — the Pydantic model
2. **Context for the skill** — which fields matter for *this* query
3. **Discoverability** — links are clickable

---

## Impact

| Aspect | Current | After Fix |
|--------|---------|-----------|
| Docs sync risk | High (duplication) | Low (single source) |
| Developer discovery time | Slow (search for model file) | Fast (click link) |
| Maintenance | Hard (update 2 places) | Easy (update 1 place) |
| Skill `.md` size | Large (full field docs) | Compact (links + context) |
