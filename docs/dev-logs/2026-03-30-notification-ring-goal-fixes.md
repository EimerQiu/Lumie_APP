# 2026-03-30 — Notification Gate, Ring Auto-Connect, and Activity Goal

## Decisions made

### 1. Poor Sleep Notification Gate
Added two extra validity checks to `_get_latest_sleep` in `rest_days_service.py`:
- `source == 'ring'` — filters out any manually entered sessions
- `resting_heart_rate > 0` — confirms the ring was collecting PPG data (not just motion from a ring left on a table)

Combined with existing checks (180 min minimum, deep/REM stages present, nighttime window, quality ≥ 5) this ensures the "Poor Sleep Detected" sheet only appears when all physiological confirmation is present.

### 2A. Ring Auto-Reconnect on Disconnect
Extended `_autoReconnectWithRetry` from 3 attempts (exponential 2s/4s/8s) to **10 attempts at 30-second intervals** (5 minutes total). First attempt fires after a 5-second stabilisation delay. Ring shows "disconnected" status only after all 10 attempts fail — not immediately on a transient disconnect.

On app launch, `init()` already calls `_tryReconnect()` which does direct-connect → scan fallback. No change needed there.

### 2B. Ring State / HR Screen Desync
Root cause: `init()` always sets `_state = disconnected` then calls `_tryReconnect()`. If the ring IS already connected at the BLE layer, `_tryReconnect` returned immediately but left `_state = disconnected`. This made `RingManagementScreen` (which reads `ring.state`) show disconnected while `HeartRateScreen` (which reads `ring.isConnected`) showed connected.

Fix: when `_bleService.isConnected` is already true at the top of `_tryReconnect`, set `_state = paired` and notify before returning.

### 3. Activity Goal Type + ICD-10 Condition Adjustment
**Goal types**: Steps or Active Time. Default is minutes. Preference stored in `profiles.goal_settings` in MongoDB.

**Condition baselines** (mapped by ICD-10 prefix):
| Tier | Conditions | Step goal | ~Minutes |
|------|-----------|-----------|---------|
| 1 | CFS (G93.32), Fibro (M79.7), Cardiomyopathy (I42), Arrhythmia, Congenital heart | 4 000 | 30 |
| 2 | Sickle cell (D57), Cystic fibrosis (E84) | 3 000 | 23 |
| 3 | Asthma (J45), Lupus (M32), RA (M05), IBD (K50/K51) | 5 000 | 38 |
| 4 | Hypertension (I10), Mental health (F3x, F41, F90), Neurological (G40, G43) | 6 000 | 45 |
| 5 | Diabetes (E10/E11), Thyroid, Obesity, Renal, Oncology history | 7 000 | 53 |
| — | Default / no condition | 8 000 | 60 |

Conversion constant: 8 000 steps = 60 min.

**Sleep adjustment** still applied on top: poor sleep (< 50%) → −2 000 steps / −15 min; fair (50–70%) → −670 steps / −5 min.

**Manual override**: `custom_goal` in goal_settings overrides the condition default. Setting it to `null` reverts to the condition default. When the user switches goal type, the custom override is automatically converted to the new unit.

## New files created

### Backend
- (none — existing files modified)

### Frontend
- `lib/features/settings/providers/activity_goal_provider.dart` — ChangeNotifier for goal type + custom override; loads from and writes to backend
- `lib/features/settings/screens/activity_goal_screen.dart` — Settings screen: goal type selector, baseline info card, custom override toggle + text field

## Modified files

### Backend
- `lumie_backend/app/models/steps.py` — Added `GoalSettings`, `GoalSettingsResponse`, `GoalSettingsUpdate`; extended `StepGoalResponse`/`DailyStepResponse` with `goal_steps`, `goal_type`, `condition_adjusted`
- `lumie_backend/app/services/steps_service.py` — Rewrote `_compute_goal` with ICD-10 condition mapping; added `get_goal_settings`, `update_goal_settings`
- `lumie_backend/app/api/steps_routes.py` — Added `GET /steps/goal-settings`, `PUT /steps/goal-settings`
- `lumie_backend/app/services/rest_days_service.py` — Added `source == 'ring'` and `resting_heart_rate > 0` validity gates to `_get_latest_sleep`

### Frontend
- `lib/shared/models/steps_models.dart` — Added `ActivityGoalType` enum, `ActivityGoalSettings` model; extended `DailyStepData` / `StepGoal` with `goalSteps`, `goalType`, `conditionAdjusted`
- `lib/core/services/steps_service.dart` — Added `getGoalSettings`, `updateGoalSettings`
- `lib/main.dart` — Registered `ActivityGoalProvider`; added `/settings/activity-goal` route
- `lib/features/ring/providers/ring_provider.dart` — Fixed `_tryReconnect` state sync; rewrote `_autoReconnectWithRetry` (10×30s)
- `lib/features/dashboard/screens/dashboard_screen.dart` — Uses `ActivityGoalProvider` for goal display; added "Activity Goal" drawer entry

## API endpoints added
- `GET /api/v1/steps/goal-settings` — returns `GoalSettingsResponse`
- `PUT /api/v1/steps/goal-settings` — body: `{goal_type, custom_goal}`, returns updated `GoalSettingsResponse`

## New DB fields
- `profiles.goal_settings.goal_type` — `"steps"` | `"minutes"`
- `profiles.goal_settings.custom_goal` — `int | null`

## Testing checklist
- [ ] Poor sleep sheet does NOT appear when no ring sleep data exists
- [ ] Poor sleep sheet does NOT appear if `resting_heart_rate == 0` (ring on table)
- [ ] Poor sleep sheet DOES appear after a confirmed bad sleep night with HR data
- [ ] Ring auto-reconnects silently on app launch
- [ ] Ring state shows "connected" in both HR screen and Ring Settings simultaneously
- [ ] After disconnect, ring retries every 30s for up to 5 minutes
- [ ] "Ring disconnected" status appears only after 5-minute retry window
- [ ] Goal Settings screen accessible from dashboard drawer → Activity Goal
- [ ] Switching goal type updates dashboard ring immediately
- [ ] Condition-adjusted baseline shown correctly for a user with G93.32
- [ ] Custom override persists across app restarts
- [ ] Removing custom override reverts to condition default
- [ ] Steps ↔ minutes custom value converts correctly when switching goal type

## Future work / deferred
- Dashboard activity ring still uses mock `_currentMinutes = 42`; needs real step data from ring
- Steps screen / history screen not yet built (data model ready, backend ready)
- Sleep quality adjustment in `_compute_goal` currently doesn't filter by `source == 'ring'`; may return manual sessions
