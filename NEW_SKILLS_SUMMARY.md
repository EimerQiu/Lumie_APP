# New Skills Created Summary

Date: 2026-04-10  
Status: ✅ Complete

Created 4 new lumie_internal skills with full Pydantic model linking and production-ready documentation.

---

## Skills Created

### 1. **habit_tracking_query** ✅
**File**: `lumie_backend/app/skills/system/lumie_internal/habit_tracking_query.md`

**Purpose**: Query daily wellness habits (mood, energy, fatigue, hunger, workload)

**Schema Links**:
- [`HabitEntryResponse` in models/habit.py](../../models/habit.py)

**Key Features**:
- Daily wellness log queries (mood 1–5, energy, fatigue, hunger, workload)
- Time-range support (today, week, custom)
- Mood trends and energy pattern detection
- Proactive wellness concern flagging

**Collection**: `habits`

**When To Use**:
- "How have I been feeling this week?"
- "Show me my fatigue trends"
- "What was my mood yesterday?"

---

### 2. **workout_exercise_query** ✅
**File**: `lumie_backend/app/skills/system/lumie_internal/workout_exercise_query.md`

**Purpose**: Query completed workout sessions with exercise performance metrics

**Schema Links**:
- [`WorkoutSession` in models/workout.py](../../models/workout.py)
- [`CompletedExercise` in models/workout.py](../../models/workout.py)
- [`PersonalRecord` in models/workout.py](../../models/workout.py)

**Key Features**:
- Session queries with full exercise breakdowns
- Sets/reps/weight tracking
- Personal record detection and reporting
- Volume trends and progressive overload analysis
- Proactive frequency and progression monitoring

**Collection**: `workout_sessions`

**When To Use**:
- "What did I work out this week?"
- "Show me my bench press history"
- "Did I hit any PRs recently?"
- "Show my chest workout sessions"

---

### 3. **spo2_data_query** ✅
**File**: `lumie_backend/app/skills/system/lumie_internal/spo2_data_query.md`

**Purpose**: Query blood oxygen saturation (SpO2) readings from the Lumie Ring

**Schema Links**:
- [`Spo2ReadingResponse` in models/spo2.py](../../models/spo2.py)

**Key Features**:
- Latest SpO2 reading retrieval
- Time-range queries (24h, 7d, 14d)
- Clinical interpretation (95–100% normal, <90% urgent)
- Low SpO2 event detection
- Proactive hypoxemia concern flagging

**Collection**: `spo2_readings`

**When To Use**:
- "What's my blood oxygen level?"
- "Show me my SpO2 readings"
- "Is my oxygen saturation normal?"

---

### 4. **hr_session_analysis** ✅
**File**: `lumie_backend/app/skills/system/lumie_internal/hr_session_analysis.md`

**Purpose**: Analyze completed heart rate measurement sessions with time-series data

**Schema Links**:
- [`HrSessionSummary` in models/hr_session.py](../../models/hr_session.py)
- [`HrSessionTimeseriesResponse` in models/hr_session.py](../../models/hr_session.py)

**Key Features**:
- Session summary queries (duration, avg/min/max BPM)
- Time-series bucket analysis
- HR recovery rate calculation
- Trend detection across multiple sessions
- Peak HR event identification
- Proactive resting HR and recovery monitoring

**Collection**: `hr_sessions`, `hr_session_buckets`

**When To Use**:
- "Show me my heart rate sessions"
- "What was my heart rate during last workout?"
- "Analyze my HR recovery"
- "Show my peak HR events"

---

## Pydantic Models (Already Existed)

All 4 skills link to existing, well-documented Pydantic models:

| Model File | Models Used |
|---|---|
| **habit.py** | `HabitEntryResponse` |
| **workout.py** | `WorkoutSession`, `CompletedExercise`, `PersonalRecord` |
| **spo2.py** | `Spo2ReadingResponse` |
| **hr_session.py** | `HrSessionSummary`, `HrSessionTimeseriesResponse` |

No new Pydantic models needed to be created—all 4 skills use existing, production-tested models.

---

## Documentation Quality

Each skill includes:

✅ **Metadata section** — skill_id, title, capability_id, tags, keywords  
✅ **Purpose & use cases** — when to invoke the skill  
✅ **Schema links** — clickable links to Pydantic models  
✅ **Runtime rules** — pre-loaded variables, timezone handling  
✅ **Query examples** — Python code showing common patterns  
✅ **Output guidance** — natural language summaries + structured data  
✅ **Proactive mode logic** — concern detection thresholds & nudge signals  
✅ **Failure handling** — graceful degradation & error messages  

---

## Clinical Context

Three skills include clinically relevant thresholds:

**spo2_data_query**:
- Normal: 95–100%
- Low-grade: 90–94% (monitor)
- Concerning: <90% (urgent)

**hr_session_analysis**:
- Resting HR elevation thresholds
- Recovery rate expectations
- Peak HR concerns for cardiac conditions
- Age-predicted max HR considerations

**health_data_query** (existing):
- Sleep quality interpretation
- Activity intensity levels
- HRV stress scoring

---

## Integration Patterns

All 4 new skills follow established patterns from:
- `tasks_query.md`
- `health_data_query.md`
- `ring_live_measure.md`

**Consistent approach across all skills**:
1. Link to Pydantic models (single source of truth)
2. Time-range query support with timezone awareness
3. Practical interpretation guidance
4. Proactive nudge thresholds
5. Chronic condition context

---

## Proactive Eligibility

All 4 skills are marked `proactive_eligible: true` with assigned:
- **Proactive domain** (wellness, strength, respiratory, cardiac)
- **Proactive priority** (55–90) — reflects clinical/behavioral importance
- **Proactive mode** (assessment) — autonomous health checks

This enables the proactive advisor to autonomously:
- Check habit compliance and mood trends
- Monitor workout frequency and recovery
- Flag low SpO2 events
- Assess HR patterns and recovery capacity

---

## Testing Recommendations

### habit_tracking_query
- [ ] Verify habits collection exists in DB
- [ ] Test mood trend aggregation over 7 days
- [ ] Test energy/fatigue pattern detection
- [ ] Verify proactive mood concern thresholds

### workout_exercise_query
- [ ] Test session queries with nested exercise arrays
- [ ] Verify PR detection logic
- [ ] Test volume trend calculation
- [ ] Verify proactive frequency nudge (no workouts 7+ days)

### spo2_data_query
- [ ] Test low SpO2 event detection (<95%, <90%)
- [ ] Verify clinical interpretation messaging
- [ ] Test proactive hypoxemia flagging
- [ ] Verify chronic condition threshold adjustments

### hr_session_analysis
- [ ] Test time-series bucket retrieval
- [ ] Verify recovery rate calculation
- [ ] Test peak HR detection
- [ ] Verify resting HR elevation concern flagging

---

## Code-Level Audit Notes

As identified in the earlier code-level audit:
- ✅ Sleep, activity, steps, HRV collections verified against DB
- ✅ Timestamp formats documented (ISO 8601 with Z)
- ⚠️ Tasks collection has `status` field discrepancy (documented in CODE_LEVEL_AUDIT_REPORT.md)
- ⚠️ Dayprints collection: `important_insight` events not found (investigate separately)

These new skills do NOT depend on the problematic collections, so they should work independently.

---

## File Locations

```
lumie_backend/app/skills/system/lumie_internal/
├── habit_tracking_query.md          (new)
├── workout_exercise_query.md        (new)
├── spo2_data_query.md              (new)
├── hr_session_analysis.md          (new)
├── tasks_query.md                  (existing, updated)
├── health_data_query.md            (existing, updated)
├── dayprint_followup.md            (existing, updated)
├── team_member_health_snapshot.md  (existing, updated)
├── ring_live_measure.md            (existing, updated)
└── comprehensive_health_assessment.md (existing, updated)
```

---

## Next Steps

1. **Deploy skills** — Copy 4 skill files to production server
2. **Run proactive test** — Trigger proactive advisor with each domain (wellness, strength, respiratory, cardiac)
3. **Validate queries** — Run sample queries against production DB
4. **Monitor logs** — Check for skill execution errors/timeouts
5. **Address code-level audit issues** — Separately handle tasks `status` field and dayprints `important_insight` events

---

## Summary

✅ **4 new skills** created with full documentation  
✅ **All linked to existing Pydantic models** (no model creation needed)  
✅ **Proactive mode enabled** for autonomous health monitoring  
✅ **Clinical context included** for sensitive metrics (SpO2, HR recovery)  
✅ **Consistent pattern** with existing skills  

Ready for deployment and proactive advisor integration.
