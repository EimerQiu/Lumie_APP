# Habit Tracker — Dev Log

**Date:** 2026-03-28

---

## Decisions Made

- **Bottom sheet, not a page** — Habit logging is a quick ≤10-second interaction; a `showModalBottomSheet` keeps the user in context without a navigation push.
- **Partial upsert** — The PUT `/habit/entry` endpoint only overwrites fields that are non-null in the payload. This means the user can update a single card without wiping others already logged the same day.
- **date = YYYY-MM-DD in client local time** — Ring timestamps use local time; habit entries are tied to local calendar days, so the client sends its local date string. Backend stores it as-is (no UTC conversion needed for day-keyed data).
- **Null = "not selected"** — No field is mandatory. The UI shows an outlined/empty state for unselected cards and never pushes the user.
- **Tap-to-deselect** — Tapping the already-selected mood emoji or pill deselects it (sets back to null). This matches the "editable until midnight" requirement without adding a separate clear button.
- **Confirmation then auto-dismiss** — After saving, a green checkmark is shown for 1.2 s then the sheet closes automatically. No manual dismiss needed.
- **icd10Code drives condition metric card** — The drawer reads `context.read<AuthProvider>().profile?.icd10Code` and passes `hasConditionMetric: icd10Code != null` to the sheet. Users without a condition code never see the numeric input card.

---

## New Files

### Backend
- `lumie_backend/app/models/habit.py` — `HabitEntryUpsert`, `HabitEntryResponse` Pydantic models
- `lumie_backend/app/services/habit_service.py` — `HabitService` with `upsert_entry`, `get_entry`, `get_today_context`
- `lumie_backend/app/api/habit_routes.py` — `PUT /habit/entry`, `GET /habit/entry/{date}`

### Frontend (Flutter)
- `lumie_activity_app/lib/shared/models/habit_models.dart` — `HabitEntry` Dart model
- `lumie_activity_app/lib/core/services/habit_service.dart` — `HabitService` (singleton) wrapping the two API endpoints
- `lumie_activity_app/lib/features/dashboard/widgets/habit_tracker_sheet.dart` — `HabitTrackerSheet` bottom sheet with `_MoodCard`, `_PillCard`, `_ConditionMetricCard`, `_CardShell` sub-widgets

---

## Modified Files

- `lumie_backend/app/main.py` — imported and registered `habit_router` at `/api/v1`
- `lumie_activity_app/lib/features/dashboard/screens/dashboard_screen.dart` — added `import` + drawer `_DrawerItem` for "Habit Tracker"

---

## API Endpoints Added

| Method | Path | Description |
|--------|------|-------------|
| `PUT` | `/api/v1/habit/entry` | Upsert today's entry (partial fields ok) |
| `GET` | `/api/v1/habit/entry/{date}` | Get entry for YYYY-MM-DD (or null) |

---

## New DB Collections

- `habit_entries` — keyed on `{user_id, date}` (compound unique via upsert filter)
  - No index created yet; add `{user_id: 1, date: 1}` unique index before production

---

## Testing Checklist

- [ ] Open drawer → "Habit Tracker" is second item in list (right after "Today")
- [ ] Tap entry → bottom sheet opens (no full navigation)
- [ ] First open: all cards empty (no selection)
- [ ] Select mood emoji → highlighted; tap again → deselected
- [ ] Select energy pill → highlighted; tap again → deselected
- [ ] Tap "Log for Today" → spinner, then checkmark confirmation, then auto-dismiss
- [ ] Reopen same day → previously saved values are pre-selected
- [ ] Update one card, save → other cards remain unchanged
- [ ] `PUT /habit/entry` with only `{ date, mood: 3 }` → only mood written, rest null preserved
- [ ] `GET /habit/entry/2026-03-28` returns saved entry; GET non-existent date returns null
- [ ] Condition metric card hidden when `hasConditionMetric = false`
- [ ] Condition metric card visible and accepts decimal input when `true`

---

## Future Work / Deferred

- **Index:** Add `{ user_id: 1, date: 1 }` unique index on `habit_entries`
- **ICD-10 label mapping:** Currently shows generic "Condition Metric" label; map common codes (I10 → "Blood Pressure (mmHg)", E11 → "Blood Sugar", etc.) to a friendlier field label
- **Advisor integration:** Use `habit_service.get_today_context(user_id, date)` in advisor context builder when generating insights
- **Adaptive goal integration:** Wire fatigue/workload from `get_today_context` into the adaptive goal adjustment logic
- **Trends view:** History chart of mood/energy/fatigue over time (deferred — no screen yet)
- **Offline queue:** Cache unsaved entries in SharedPreferences and retry on next launch
