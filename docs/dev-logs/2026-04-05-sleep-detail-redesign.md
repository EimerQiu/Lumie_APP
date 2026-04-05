# Sleep Detail Page Redesign + Mid-Night Wake-Up Handling

**Date:** 2026-04-05

---

## Decisions Made

### Timeline segments instead of aggregate-only stages
The previous sleep screen showed stage percentages from aggregate totals with no temporal ordering. The ring sends multiple per-night records (each is a contiguous sleep period). We now store and expose an ordered `timeline_segments` list built from those records so the frontend can render a proper Oura-style timeline bar.

### Stage order convention for fallback synthesis
When `timeline_segments` is empty (older records in the DB), the Flutter chart synthesises blocks in a fixed conventional order: awake → light → deep → rem. This is an approximation — the ring doesn't expose per-minute stage data — but is honest enough for a visual representation.

### Mid-night wake-up session boundary rules
Two ring records from the same night are kept in the same session ("awake" gap in the timeline) unless:
- Gap > 30 min AND the gap starts at or after 5:00 AM (user is morning-awake), OR
- Gap > 60 min at any time of night
These thresholds align with the spec and avoid splitting naps or short-restroom trips into separate sessions.

### Quality score description language
Score descriptions are tiered (≥80 / ≥65 / ≥50 / <50) and always use non-alarming language: "Better than your recent average", "Similar to your recent average", "Slightly below your usual", "Below your usual". Never "bad", "poor", or "failed".

### Empty state
The no-data state shows an explicit message — "No sleep data recorded for this night." — and renders zero charts, scores, or placeholders.

---

## New Files Created

### Backend
_(none — existing files extended)_

### Frontend
_(none — existing files rewritten)_

---

## Modified Files

### Backend
- `lumie_backend/app/models/sleep.py`
  - Added `SleepTimelineSegment` Pydantic model (`stage`, `start_offset_minutes`, `duration_minutes`)
  - Added `timeline_segments: list[SleepTimelineSegment] = []` and `wake_count: int = 0` to `SleepSessionResponse`

- `lumie_backend/app/services/sleep_service.py`
  - Added `_split_by_wake_boundaries(segs)` — splits same-night segments into sub-sessions based on gap duration thresholds
  - Added `_build_timeline_segments(segs, earliest_bedtime)` — builds ordered timeline blocks from ring records, inserting awake gaps between segments
  - Updated `_build_merged_doc` to include `timeline_segments` and `wake_count`
  - Updated `sync_sessions` to call `_split_by_wake_boundaries` before merging
  - Updated `_doc_to_response` to deserialise the two new fields

### Frontend
- `lumie_activity_app/lib/shared/models/sleep_models.dart`
  - Added `SleepTimelineSegment` class (`stage`, `startOffsetMinutes`, `durationMinutes`)
  - Added `timelineSegments` and `wakeCount` fields to `SleepSession` (both optional / backwards-compatible defaults)
  - Updated `SleepSession.fromJson` to parse the new fields

- `lumie_activity_app/lib/features/sleep/widgets/sleep_stage_chart.dart`
  - Complete rewrite as `SleepTimelineChart` (StatefulWidget)
  - Added `SleepStageColors` constants: awake=white, light=#FFF9C4, rem=#F9A825, deep=#E65100
  - Proportional block rendering using `Expanded(flex: durationMinutes)`
  - Tap-to-toggle inline tooltip (`_TooltipBubble`) showing stage name + duration
  - Start/end clock-time labels
  - Fallback `_effectiveSegments()` synthesises from aggregate totals for old data

- `lumie_activity_app/lib/features/sleep/screens/sleep_screen.dart`
  - Complete redesign; removed dependency on `GradientCard` and `SleepMetricCard`
  - **Quality score card** — `_ScoreRing` circular arc + non-alarming description + date/time window
  - **Timeline card** — `SleepTimelineChart` + stage breakdown rows (dot, label, duration, %)
  - **Metrics card** — 5 tiles in 2-column Wrap: Total Sleep, Time in Bed, Efficiency, Sleep Window, Wake-ups
  - **No-data state** — explicit message, no zero-value placeholders

---

## API Endpoints Changed

`GET /api/v1/sleep/latest` and `GET /api/v1/sleep/history` responses now include:
```json
{
  "timeline_segments": [
    { "stage": "light", "start_offset_minutes": 0, "duration_minutes": 90 },
    { "stage": "awake", "start_offset_minutes": 90, "duration_minutes": 12 },
    ...
  ],
  "wake_count": 1
}
```

---

## New DB Collections / Indexes

None. Existing `sleep_sessions` documents gain two new fields (`timeline_segments`, `wake_count`) on next sync upsert. Old documents without these fields return empty defaults via the response model.

---

## Testing Checklist

- [ ] Single-segment night (no wake-ups): timeline shows awake + light + deep + rem blocks
- [ ] Two-segment night with 20-min gap: both in same session, gap shows as awake block in timeline
- [ ] Two-segment night with 45-min gap before 5 AM: same session (45 < 60 min threshold)
- [ ] Two-segment night with 35-min gap at 5:30 AM: splits into two sessions (>30 min + past 5 AM)
- [ ] Two-segment night with 65-min gap at 3 AM: splits into two sessions (>60 min)
- [ ] Old DB record (no timeline_segments): fallback synthesised segments render without error
- [ ] No ring data: empty state shown with no charts or placeholders
- [ ] Tapping a timeline block shows tooltip; tapping again dismisses it
- [ ] Quality score descriptions match thresholds (≥80, ≥65, ≥50, <50)
- [ ] Sleep efficiency % matches totalSleepTime / totalTimeInBed

---

## Future Work / What's Deferred

- Per-minute hypnogram data: the ring only sends total minutes per stage per segment, so the within-segment stage order is a fixed approximation. A firmware change or different protocol command would be needed for true per-minute resolution.
- Historical average for quality description: currently uses fixed thresholds; a rolling 7-day average from the backend would make the description more accurate.
- Sleep history screen redesign to match this new design language.
