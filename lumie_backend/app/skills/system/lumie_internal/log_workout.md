---
skill_id: log_workout
title: Log Workout Session
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [workout, strength, log, exercise, sets, reps, weight, training, gym, session, fitness]
keywords: [log workout, log a workout, log my workout, I worked out, I did a workout, help me log, record workout, save workout, add workout, I trained, gym session, I exercised, I did squats, I lifted, I did pushups, I did pull-ups, strength training, I worked out today, log my training, save my session, I just finished a workout]
summary: Log a completed strength or workout session for the user — parses exercise names, sets, reps, and weight from natural language and saves to workout history.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    workout_title:
      type: string
      description: "Short title for this workout (e.g. 'Upper Body', 'Leg Day'). If not provided by user, infer from exercises."
    workout_date:
      type: string
      description: "Date of the workout in 'yyyy-MM-dd' format (user's local timezone). Use today if not specified."
    duration_minutes:
      type: integer
      description: "Approximate duration in minutes. 0 if unknown."
    exercises:
      type: array
      description: "List of exercises performed"
      items:
        type: object
        properties:
          name:
            type: string
            description: "Exercise name (e.g. 'Goblet Squat', 'Push-Up', 'Romanian Deadlift')"
          equipment:
            type: string
            enum: [bodyweight, dumbbell, barbell, machine, cable, band]
            description: "Equipment used. Default bodyweight if not mentioned."
          sets:
            type: array
            items:
              type: object
              properties:
                reps:
                  type: integer
                  description: "Number of reps completed"
                weight:
                  type: number
                  description: "Weight used (lbs). Omit or null if bodyweight."
    notes:
      type: string
      description: "Any notes the user mentioned about the workout"
output_schema:
  type: object
  properties:
    summary:
      type: string
      description: "Friendly confirmation of what was logged"
    session_id:
      type: string
    nav_hint:
      type: string
      description: "strength — navigate to Strength history"

---

# Purpose
Log a completed workout session for the user. Parses natural-language descriptions like
"I did 3 sets of squats at 25lb and 3 sets of push-ups" into structured exercise data
and saves it directly to the user's workout history.

# When To Use
- User says: "help me log a workout", "I just finished working out", "log my session"
- User describes exercises they completed: "I did squats, deadlifts, lunges"
- User wants to record a past workout verbally instead of using the manual log

# Clarification-First Policy
Before logging, verify you have at least the exercises. Missing reps/weight is acceptable
(log what's known, omit the rest). Only ask for clarification if:
- No exercises were mentioned at all
- An exercise name is completely ambiguous and cannot be inferred

Do NOT ask for clarification if:
- Reps or weight are missing (just omit them — log the exercise with what's known)
- The exact workout date is unclear (default to today)
- The user didn't name the workout (infer from exercises or use "My Workout")

Clarification response format (no write):
```python
_result = {
    "summary": "What exercises did you do? Just tell me the movements and I'll log them.",
    "session_id": "",
    "nav_hint": "strength",
}
```

# Runtime Rules
- All time helpers pre-loaded: `datetime`, `timedelta`, `timezone`, `ZoneInfo`, `uuid`, `asyncio`
- No imports allowed
- `user_timezone` contains the user's IANA timezone string
- `target_user_id` is the requesting user's ID
- `db` is the MongoDB connection

# Execution Plan

## Step 1: Resolve workout date and times
```python
from_date = workout_date if workout_date else datetime.now(ZoneInfo(user_timezone)).strftime("%Y-%m-%d")
tz = ZoneInfo(user_timezone)

# Parse date in user's timezone
date_dt = datetime.strptime(from_date, "%Y-%m-%d")
local_start = date_dt.replace(hour=9, minute=0, second=0, tzinfo=tz)  # default 9 AM local
local_end = local_start + timedelta(minutes=max(duration_minutes or 45, 1))

started_at = local_start.astimezone(timezone.utc)
ended_at = local_end.astimezone(timezone.utc)
duration_seconds = (duration_minutes or 45) * 60
```

## Step 2: Build exercise documents
```python
exercise_docs = []
total_sets = 0
total_reps = 0
total_volume = 0.0

for ex in (exercises or []):
    ex_name = ex.get("name", "Exercise")
    equipment = ex.get("equipment", "bodyweight")
    raw_sets = ex.get("sets", [])

    # Try to find matching exercise_id from library
    library_match = await db.exercises.find_one(
        {"name": {"$regex": f"^{ex_name}$", "$options": "i"}, "is_active": True},
        {"exercise_id": 1}
    )
    exercise_id = library_match["exercise_id"] if library_match else f"custom_{uuid.uuid4().hex[:8]}"

    set_docs = []
    for i, s in enumerate(raw_sets):
        reps = s.get("reps") or 0
        weight = s.get("weight")
        set_doc = {
            "set_index": i,
            "target_reps": reps,
            "target_weight": weight,
            "actual_reps": reps,
            "actual_weight": weight,
            "status": "completed",
            "is_pr": False,
            "rpe": None,
            "notes": None,
            "was_camera_tracked": False,
        }
        set_docs.append(set_doc)
        total_sets += 1
        total_reps += reps
        total_volume += (weight or 0) * reps

    exercise_docs.append({
        "exercise_id": exercise_id,
        "exercise_name": ex_name,
        "equipment_type": equipment,
        "pose_type": None,
        "set_type": "straight",
        "group_id": None,
        "block_name": None,
        "sets": set_docs,
    })
```

## Step 3: Detect PRs
```python
new_prs = []
for ex_doc in exercise_docs:
    eid = ex_doc["exercise_id"]
    ex_sets = ex_doc["sets"]

    max_weight = max((s.get("actual_weight") or 0 for s in ex_sets), default=0)
    max_reps = max((s.get("actual_reps") or 0 for s in ex_sets), default=0)
    max_volume = max(((s.get("actual_weight") or 0) * (s.get("actual_reps") or 0) for s in ex_sets), default=0)

    for pr_type, value in [("max_weight", max_weight), ("max_reps", float(max_reps)), ("max_volume", max_volume)]:
        if value <= 0:
            continue
        existing = await db.personal_records.find_one(
            {"user_id": target_user_id, "exercise_id": eid, "pr_type": pr_type}
        )
        if existing and existing.get("value", 0) >= value:
            continue
        pr_doc = {
            "pr_id": f"pr_{uuid.uuid4().hex[:12]}",
            "user_id": target_user_id,
            "exercise_id": eid,
            "exercise_name": ex_doc["exercise_name"],
            "pr_type": pr_type,
            "value": value,
            "previous_value": existing["value"] if existing else None,
            "session_id": "",  # filled after session_id is set
            "achieved_at": datetime.utcnow(),
        }
        new_prs.append(pr_doc)
```

## Step 4: Build and insert session
```python
session_id = f"sess_{uuid.uuid4().hex[:12]}"
title = workout_title or _infer_title(exercises or [])

# Backfill session_id into PRs
for pr in new_prs:
    pr["session_id"] = session_id

session_doc = {
    "session_id": session_id,
    "user_id": target_user_id,
    "template_id": None,
    "template_name": title,
    "started_at": started_at,
    "ended_at": ended_at,
    "duration_seconds": duration_seconds,
    "exercises": exercise_docs,
    "total_sets": total_sets,
    "total_reps": total_reps,
    "total_volume": total_volume,
    "prs": new_prs,
    "heart_rate_avg": None,
    "heart_rate_max": None,
    "notes": notes or None,
    "source": "advisor_added",
    "created_by": "advisor",
    "creator_id": target_user_id,
    "advisor_notes": None,
    "created_at": datetime.utcnow(),
}

await db.workout_sessions.insert_one(session_doc)

# Upsert PRs
for pr in new_prs:
    await db.personal_records.update_one(
        {"user_id": target_user_id, "exercise_id": pr["exercise_id"], "pr_type": pr["pr_type"]},
        {"$set": pr},
        upsert=True,
    )
```

## Step 5: Helper — infer workout title
```python
def _infer_title(exs):
    if not exs:
        return "My Workout"
    names = [e.get("name", "") for e in exs[:3]]
    lower = " ".join(names).lower()
    if any(w in lower for w in ["squat", "deadlift", "lunge", "leg"]):
        return "Leg Day"
    if any(w in lower for w in ["bench", "push", "chest", "tricep"]):
        return "Push Day"
    if any(w in lower for w in ["row", "pull", "lat", "bicep", "back"]):
        return "Pull Day"
    if any(w in lower for w in ["shoulder", "press", "lateral"]):
        return "Shoulder Day"
    return "My Workout"
```

## Step 6: Build result
```python
ex_count = len(exercise_docs)
pr_count = len(new_prs)

summary = f"Logged! I saved **{title}** — {ex_count} exercise{'s' if ex_count != 1 else ''}, {total_sets} sets."
if pr_count > 0:
    summary += f" 🏆 You hit {pr_count} new PR{'s' if pr_count != 1 else ''}!"

_result = {
    "summary": summary,
    "session_id": session_id,
    "nav_hint": "strength",
}
```

# Failure Handling
- If no exercises: return clarification asking what they did (no write)
- If DB insert fails: return error summary with session_id = ""
- If PR detection fails: log session without PRs (non-critical)
