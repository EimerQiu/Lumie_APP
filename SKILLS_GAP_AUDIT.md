# Lumie Skills Gap Audit Report
**Date:** 2026-04-11  
**Status:** 8 New Features Without AI Skills

---

## Executive Summary

| Metric | Value |
|--------|-------|
| **Total Collections/Models** | 20 |
| **Existing Skills** | 6 |
| **Coverage** | 30% |
| **Missing Skills** | 8 |

---

## Current Skills Coverage ✅

### 6 Existing Skills
1. **comprehensive_health_assessment** — Overall health synthesis
2. **dayprint_followup** — Daily event analysis
3. **health_data_query** — Sleep, activity, HR, HRV, temperature, blood oxygen
4. **ring_live_measure** — Smart ring live measurement
5. **tasks_query** — Med reminders and task management
6. **team_member_health_snapshot** — Parent/admin team member health

---

## 8 Features Without Dedicated Skills ⚠️

### 🔴 HIGH PRIORITY (User-Facing Features)

#### 1. **habit_tracking_query** (NEW)
- **Collection:** `habit`
- **Endpoint:** `/api/v1/habits/entry`
- **What it queries:** Daily habit entries, completion rates
- **User question examples:**
  - "How many times did I exercise this week?"
  - "Show my habit history"
  - "Am I on track with my habits?"
- **Status:** Feature exists, API ready, **skill needed**

#### 2. **workout_exercise_query** (NEW)
- **Collection:** `workout`
- **Endpoint:** `/api/v1/workouts/exercises`
- **What it queries:** Exercises, workout plans, muscle groups, splits
- **User question examples:**
  - "What exercises should I do today?"
  - "Show my favorite workouts"
  - "Create a workout plan for me"
- **Status:** Feature exists, API ready, **skill needed**

#### 3. **ring_command_management** (NEW)
- **Collection:** `ring_command`
- **Endpoint:** `/api/v1/ring-command`
- **What it queries:** Pending ring commands, execution results, status
- **User question examples:**
  - "Check my pending ring commands"
  - "Did the ring measurement complete?"
  - "What's my latest ring data?"
- **Status:** Feature exists, API ready, **skill needed**

#### 4. **spo2_data_query** (NEW)
- **Collection:** `spo2`
- **Endpoint:** `/api/v1/spo2`
- **What it queries:** Blood oxygen readings, trends, historical data
- **User question examples:**
  - "Show my blood oxygen levels"
  - "How's my oxygen saturation?"
  - "Is my SpO2 in a healthy range?"
- **Status:** Feature exists, API ready, **skill needed**
- **Note:** Mentioned in health_data_query but no dedicated endpoint skill

#### 5. **hr_session_analysis** (NEW)
- **Collection:** `hr_session`
- **Endpoint:** `/api/v1/hr/sessions`
- **What it queries:** Detailed heart rate sessions, recovery, performance
- **User question examples:**
  - "Show my HR recovery sessions"
  - "Compare heart rate between workouts"
  - "Analyze my cardio performance"
- **Status:** Feature exists, API ready, **skill needed**
- **Note:** Different from generic `hr_readings` - session-specific analysis

#### 6. **analysis_job_query** (NEW)
- **Collection:** `analysis`
- **Endpoint:** `/api/v1/analysis/jobs`
- **What it queries:** Health analysis jobs, AI results, historical analyses
- **User question examples:**
  - "What health analysis have I run?"
  - "Show my stress analysis results"
  - "Run a fatigue analysis on my data"
- **Status:** Feature exists, API ready, **skill needed**

#### 7. **proactive_nudge_query** (NEW)
- **Collection:** `proactive`
- **Endpoint:** `/api/v1/proactive/run/{user_id}`
- **What it queries:** Proactive recommendations, nudge decisions
- **User question examples:**
  - "Give me a health nudge"
  - "What's recommended for me?"
  - "Any important health advice?"
- **Status:** Feature exists, API ready, **skill needed**
- **Note:** May have overlap with advisor/decision-making system

### 🟡 LOWER PRIORITY (Internal/System)

#### 8. **hr_readings_sync** (Lower Priority)
- **Collection:** `hr`
- **Note:** Basic HR readings already covered in `health_data_query`
- **Status:** May not need separate skill

---

## Impact Analysis

### What Users Can't Ask Right Now ❌
- "What exercises should I do?"
- "Show my workout history"
- "Check my blood oxygen levels"
- "Are my habits on track?"
- "Show my heart rate sessions"
- "What analysis have I run?"
- "Give me a health nudge"

### What Users CAN Ask ✅
- "What are my sleep patterns?"
- "Show my activity"
- "What tasks do I have?"
- "Get my team member's health snapshot"
- "Measure my ring data live"

---

## Recommendations

### Phase 1 (Do First - User-Facing)
1. ✅ **habit_tracking_query** — Commonly requested feature
2. ✅ **workout_exercise_query** — Growing fitness feature
3. ✅ **spo2_data_query** — Health monitoring priority

### Phase 2 (Do Next - Health Insights)
4. ✅ **ring_command_management** — Ring integration status
5. ✅ **hr_session_analysis** — Advanced cardio insights
6. ✅ **analysis_job_query** — AI analysis access

### Phase 3 (Later - Potentially Overlapping)
7. ⚠️ **proactive_nudge_query** — May overlap with existing advisor system

### Don't Need Skills
- `advisor_capability`, `execution_job`, `advisor_skill_credential` — Internal system metadata

---

## Implementation Notes

**File Location:** `lumie_backend/app/skills/system/lumie_internal/`

**Skill Files to Create:**
```
habit_tracking_query.md
workout_exercise_query.md
ring_command_management.md
spo2_data_query.md
hr_session_analysis.md
analysis_job_query.md
proactive_nudge_query.md
```

**Each Should Include:**
- Purpose and use cases
- Input schema (user intent)
- Required MongoDB queries
- Collection/model references
- Response format examples
- Teen-safe output rules

---

## Next Steps

Would you like me to create these missing skills? Recommend starting with **habit_tracking_query** and **workout_exercise_query** since they're the most user-requested features.
