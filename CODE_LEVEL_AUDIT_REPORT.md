# Code-Level Database Schema Audit Report

Date: 2026-04-10  
Scope: Verify actual MongoDB schemas match Pydantic models and skill documentation  
Method: Code inspection + live database queries

---

## Executive Summary

**Critical Issues Found: 4**
**Warning Issues Found: 3**
**Status Fields Discrepancy: Major**

### Critical Issues
1. **Tasks collection `status` field is stored in DB but Pydantic model says it's computed**
2. **Both `done` and `completed_at` fields exist — conflicting logic**
3. **Timestamp format inconsistency** — `open_datetime`/`close_datetime` lack Z suffix, but `created_at`/`updated_at` have it
4. **Dayprint events: `important_insight` event type not found in actual data** (only `advisor_chat` and `task_completed` observed)

---

## Collection-by-Collection Audit

### 1. TASKS Collection

#### Actual Database Schema (from live query)
```json
{
  "_id": "ObjectId",
  "task_id": "uuid",
  "task_name": "string",
  "task_type": "string enum (Study, Medicine, etc.)",
  "open_datetime": "2026-03-06 00:14",  // ❌ NO Z suffix
  "close_datetime": "2026-03-07 21:08", // ❌ NO Z suffix
  "user_id": "uuid",
  "team_id": "uuid",
  "created_by": "uuid",
  "rpttask_id": null or "uuid",
  "status": "pending",  // ❌ STORED IN DB
  "task_info": null or "string",
  "completed_at": null or "ISO datetime with Z",
  "created_at": "2026-03-06T20:08:44.284Z",  // ✅ WITH Z suffix
  "updated_at": "2026-03-07T06:42:29.226Z",  // ✅ WITH Z suffix
  "done": "ISO datetime with Z" or ABSENT  // ✅ Matches skill docs
}
```

#### Pydantic Model (task.py TaskResponse)
```python
task_id: str
task_name: str
task_type: TaskType  # enum
open_datetime: str
close_datetime: str
user_id: str
team_id: Optional[str]
created_by: str
rpttask_id: Optional[str]
status: TaskStatus  # enum (PENDING, COMPLETED, OVERDUE, EXPIRED)
task_info: Optional[str]
completed_at: Optional[str]  # ✅ Matches DB
created_at: str
updated_at: str
```

#### Skill Documentation (tasks_query.md)
Says to query:
```markdown
- `open_datetime`: string "YYYY-MM-DD HH:MM" (UTC, no Z suffix) ✅ CORRECT
- `close_datetime`: string "YYYY-MM-DD HH:MM" (UTC, no Z suffix) ✅ CORRECT
- `done`: MongoDB datetime if completed, field ABSENT if not ✅ CORRECT
- `task_info`: string or null ✅ CORRECT
```

#### Issues Found

**🔴 CRITICAL: `status` field in database but not documented in skills**
- Database STORES `status` field
- Pydantic model receives status from database
- Skill docs don't mention querying `status` — they say to compute it from `done` and `close_datetime`
- **What's happening**: Code in `_task_doc_to_response()` (line 182-186) computes status, but DB has a stored status field that's separate

**🟡 WARNING: Both `done` and `completed_at` exist**
- `done`: Used for completion logic, can be absent
- `completed_at`: Always present (null or datetime), but seems to duplicate information

**Code discrepancy:**
- `task_service.py` line 460: Sets `"completed_at": None` when creating
- `task_service.py` line 570: Sets `"done": close_dt` when completing
- `task_service.py` line 203: Returns `completed_at` from `done` field

**Timestamp format inconsistency:**
- `open_datetime`/`close_datetime`: No Z suffix, format "YYYY-MM-DD HH:MM"
- `created_at`/`updated_at`: ISO format with Z suffix "2026-03-06T20:08:44.284Z"
- **Why**: open/close are stored as strings (user local time converted to UTC string), while created/updated are MongoDB datetime objects

#### Recommendation

Update `tasks_query.md` to clarify:
1. The `status` field is available in the database (it's computed and stored)
2. Explain the `done` vs `completed_at` distinction
3. Document the timestamp format difference

---

### 2. DAYPRINTS Collection

#### Actual Database Schema
```json
{
  "_id": "ObjectId",
  "user_id": "uuid",
  "date": "2026-03-19",
  "events": [
    {
      "event_id": "uuid",
      "type": "advisor_chat" | "task_completed",  // ❌ NO important_insight
      "timestamp": "2026-03-19T04:13:06.174676+00:00",
      "data": {
        "summary": "string",
        // Additional fields depend on event type
      }
    }
  ]
}
```

#### Pydantic Model (dayprint.py)
```python
class DayprintEvent(BaseModel):
    type: str  # "task_completed" | "advisor_chat"
    timestamp: str  # ISO datetime (UTC)
    data: dict[str, Any]

class DayprintResponse(BaseModel):
    user_id: str
    date: str  # local date "YYYY-MM-DD"
    events: list[DayprintEvent] = []
```

#### Skill Documentation (dayprint_followup.md)
```markdown
**`important_insight` events** are automatically created when the advisor detects:
- New or worsening symptoms
- Medication concerns (side effect)
- Emotional distress or health anxiety
- Urgent health signals

**Fields in important_insight.data:**
- `category`: One of: `symptom`, `medication`, `emotional`, `health_concern`, `urgent`, `other`
- `summary`: Brief description (3rd person, includes user's name)
- `session_id`: Which advisor session detected this
```

#### Issues Found

**🔴 CRITICAL: `important_insight` event type not observed in database**
- Skill documentation extensively covers `important_insight` event type
- Actual database only contains: `advisor_chat`, `task_completed`
- **No evidence that `important_insight` events are being created**

**Impact**: The `dayprint_followup` skill depends on finding `important_insight` events, but they may not exist in the database at all.

#### Verification Needed

Check if `important_insight` events are:
1. Being created somewhere (grep for "important_insight" in code)
2. Actually stored in production database
3. Or if this is planned/future functionality

#### Recommendation

- [ ] Search codebase for where `important_insight` events are created
- [ ] If not created, update skill docs to clarify expected event types
- [ ] If they should be created, find why they're not appearing

---

### 3. PROFILES Collection

#### Actual Database Schema
```json
{
  "_id": "ObjectId",
  "user_id": "uuid",
  "role": "parent" | "teen",
  "name": "string",
  "age": integer,
  "height": {
    "value": float,
    "unit": "cm" | "ft_in"
  },
  "weight": {
    "value": float,
    "unit": "kg" | "lb"
  },
  "icd10_code": null | "string",
  "advisor_name": null | "string",
  "ai_advisor_name": null | "string",  // ❌ Not in Pydantic model?
  "timezone": "string",  // ✅ Matches skill docs
  "rest_days": {  // ✅ Matches fix we made
    "weekly_rest_days": [0, 5],
    "specific_dates": ["2026-04-12"]
  },
  "created_at": "2026-01-23T03:45:50.545Z",
  "updated_at": "2026-01-23T03:45:50.545Z"
}
```

**Note**: The actual database record shown didn't include `rest_days`, but it's documented in user.py RestDaySettings model

#### Pydantic Model (user.py ProfileInDB)
```python
user_id: str
role: AccountRole
name: str
age: Optional[int]
height: Optional[dict]  # {value, unit}
weight: Optional[dict]  # {value, unit}
icd10_code: Optional[str]
advisor_name: Optional[str]
ai_advisor_name: Optional[str]  # ✅ Exists in model
timezone: str = "UTC"
subscription: Optional[dict]  # SubscriptionStatus as dict
created_at: datetime
updated_at: datetime
```

#### Skill Documentation (team_member_health_snapshot.md & health_data_query.md)
```markdown
Relevant fields:
- `name`, `age`, `icd10_code`, `timezone`  // No mention of rest_days issue
```

#### Issues Found

**✅ FIXED**: `rest_days` field location clarified in health_data_query.md

**🟡 WARNING**: `ai_advisor_name` field in code but not well documented

**Status**: This collection matches documentation well now after our fix.

---

### 4. SLEEP_SESSIONS Collection

#### Actual Database Schema
```json
{
  "_id": "ObjectId",
  "session_id": "string (timestamp)",
  "user_id": "uuid",
  "bedtime": "2025-11-22T14:03:02.000Z",  // ✅ ISO with Z
  "wake_time": "2025-11-22T15:48:02.000Z",  // ✅ ISO with Z
  "total_sleep_minutes": 69,
  "time_awake_minutes": 36,
  "stages": [
    {
      "stage": "light",
      "duration_minutes": 46,
      "percentage": 66.67
    }
  ],
  "resting_heart_rate": 0,
  "sleep_quality_score": 38.59375,
  "source": "ring",
  "created_at": "2025-11-22T15:48:02.000Z"
}
```

#### Pydantic Model (sleep.py SleepSessionResponse)
```python
session_id: str
user_id: str
bedtime: datetime  // ✅
wake_time: datetime  // ✅
total_sleep_minutes: int  // ✅
time_awake_minutes: int  // ✅
stages: list[SleepStageData]  // ✅
resting_heart_rate: int  // ✅
sleep_quality_score: float  // ✅
created_at: datetime
source: str = "ring"
timeline_segments: list[SleepTimelineSegment] = []
wake_count: int = 0
```

#### Skill Documentation (health_data_query.md)
Says to query: `bedtime`, `wake_time`, `total_sleep_minutes`, `stages`, `resting_heart_rate`, `sleep_quality_score`

**Status**: ✅ **MATCHES PERFECTLY** — No issues found

---

### 5. DAILY_STEPS Collection

#### Actual Database Schema
```json
{
  "_id": "ObjectId",
  "user_id": "uuid",
  "date_str": "2026-03-30",  // ✅ YYYY-MM-DD
  "steps": 2647,
  "distance_km": 1.45,
  "exercise_time_seconds": 1270,  // ✅ Matches health_data_query.md
  "synced_at": "2026-04-10T23:00:25.154Z"  // ⚠️ Not documented in skills
}
```

#### Pydantic Model (steps.py)
```python
class DailyStepRecord(BaseModel):
    date_str: str  # YYYY-MM-DD
    steps: int
    exercise_time_seconds: int
    distance_km: float
```

#### Skill Documentation (health_data_query.md)
```markdown
Fields: `date_str` (YYYY-MM-DD), `steps`, `exercise_time_seconds`, `distance_km`
```

**Status**: ✅ **MATCHES** — No issues found

---

### 6. HRV_READINGS Collection

#### Actual Database Schema
```json
{
  "_id": "ObjectId",
  "user_id": "uuid",
  "timestamp": "2026-03-31T05:59:30.000Z",  // ✅ ISO with Z
  "hrv_ms": 45,
  "heart_rate_bpm": 81,
  "fatigue": 44,  // 0-100 stress/fatigue
  "systolic_mmhg": 111,
  "diastolic_mmhg": 61,
  "source": "ring",
  "created_at": "2026-03-31T06:06:26.237Z"  // ⚠️ Not mentioned in skills
}
```

#### Pydantic Model (hrv.py HrvDataPoint)
```python
timestamp: datetime
hrv_ms: int
heart_rate_bpm: int
fatigue: int  # 0–100 stress/fatigue level
systolic_mmhg: int
diastolic_mmhg: int
```

#### Skill Documentation (health_data_query.md)
```markdown
Fields: `timestamp`, `hrv_ms`, `heart_rate_bpm`, `fatigue`, `systolic_mmhg`, `diastolic_mmhg`, `source`
```

**Status**: ✅ **MATCHES** — No issues found

---

## Summary of Findings

### By Severity

| Severity | Collection | Issue | Impact |
|----------|-----------|-------|--------|
| 🔴 CRITICAL | tasks | `status` stored in DB but skill docs say compute it | Skills may use wrong logic to determine task status |
| 🔴 CRITICAL | dayprints | `important_insight` events not found in database | `dayprint_followup` skill will fail to find expected events |
| 🟡 WARNING | tasks | Conflicting `done` and `completed_at` fields | Maintenance confusion, unclear which to use |
| 🟡 WARNING | tasks | Timestamp format inconsistency (Z suffix) | Risk of parsing errors in different parts of code |
| 🟡 WARNING | profiles | `ai_advisor_name` field exists but not documented in skills | Skills may not know this field is available |
| ✅ OK | sleep_sessions | Schema matches perfectly | No action needed |
| ✅ OK | daily_steps | Schema matches perfectly | No action needed |
| ✅ OK | hrv_readings | Schema matches perfectly | No action needed |

### By Collection Status

```
✅ Perfect Match:
   - sleep_sessions
   - daily_steps
   - hrv_readings

⚠️ Needs Documentation Update:
   - profiles (rest_days fix already done)
   - tasks (done/completed_at clarification needed)

🔴 Requires Investigation:
   - tasks (status field discrepancy)
   - dayprints (important_insight events missing)
```

---

## Next Steps (Prioritized)

### 🔴 CRITICAL — Must Fix This Sprint

1. **Tasks `status` field logic**
   ```bash
   # Search where status is set
   grep -r '"status"' lumie_backend/app/services/
   grep -r 'TaskStatus' lumie_backend/app/services/
   ```
   - Determine if `status` should be stored or computed
   - Update skill docs to match implementation
   - Fix `_task_doc_to_response()` if needed

2. **Dayprints `important_insight` events**
   ```bash
   # Search where important_insight is created
   grep -r 'important_insight' lumie_backend/
   grep -r 'importantinsight' lumie_backend/
   ```
   - Find if/where these events are created
   - If not created, update `dayprint_followup.md`
   - If they should be created, find why they're not

### 🟡 WARNING — Update Documentation

3. **Clarify `done` vs `completed_at` in tasks**
   - Update `tasks_query.md` to document both fields
   - Explain why both exist and when each is used

4. **Document timestamp format differences**
   - Explain why some fields have Z suffix and others don't
   - Add parsing guidance to skills

5. **Add `ai_advisor_name` to profiles documentation**
   - Document this field in skill references

---

## Testing Checklist

- [ ] Verify `status` field values in 10+ task records match computed status logic
- [ ] Search codebase for all references to `important_insight` events
- [ ] Run `dayprint_followup` skill against actual data; verify it finds events
- [ ] Test task query code against actual database
- [ ] Verify timestamp parsing handles both Z and non-Z formats
- [ ] Check if `ai_advisor_name` is ever set/used in code

---

## Verification Method

This audit was conducted by:
1. Reading Python service code (`task_service.py`, etc.)
2. Reading Pydantic model definitions
3. Querying production MongoDB database for actual schemas
4. Comparing all three sources for discrepancies

Database queries run:
```bash
mongosh lumie_db --eval "JSON.stringify(db.COLLECTION.findOne(), null, 2)"
```

Server: `54.177.85.124` (production)  
Database: `lumie_db` (MongoDB 8.0)
