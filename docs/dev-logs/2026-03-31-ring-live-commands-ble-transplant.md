# 2026-03-31 — Ring Live Commands, Full BLE Transplant & Dashboard Sync Indicator

## What Was Built

### 1. Dashboard sync indicator
The "Here's your day at a glance" subtitle in the app bar now switches to **"Ring data syncing…"** while `RingSyncService` is in the `syncing` phase, then reverts automatically. `RingSyncService` was added to the provider tree in `main.dart` so widgets can watch it.

### 2. New ring models (`ring_models.dart`)
Seven new model classes added:
- `RingLiveTemperature` — on-demand temperature (0x14)
- `RingTimeInfo` — ring clock + MTU (0x41)
- `RingUserInfo` — user profile stored on ring (0x42)
- `RingDetailedStepRecord` — per-minute step breakdown (0x52)
- `RingExerciseRecord` — exercise session (0x5C)
- `RingMeasurementInterval` — auto-measurement schedule (0x2A/0x2B)
- `RingHrMeasurementResult` — live HR measurement result (0x28)

### 3. Full BLE transplant (`ring_ble_service.dart`)
All remaining commands from `smart_ring_ble_lib` transplanted:
| Command | Method | Description |
|---------|--------|-------------|
| 0x14 | `fetchRingTemperatureLive()` | On-demand temperature reading |
| 0x41 | `fetchRingTime()` | Ring clock + max MTU |
| 0x42 | `fetchUserInfo()` | User profile from ring |
| 0x52 | `fetchDetailedSteps()` | Per-minute step records |
| 0x19 (0x01/0x05/0x06) | `startExercise()` / `getExerciseStatus()` / `stopExercise()` | Exercise session control |
| 0x5C (0x00/0x02/0x99) | `fetchExerciseData()` / `continueExerciseData()` / `deleteExerciseData()` | Exercise history |
| 0x2B | `getMeasurementInterval(type)` | Read auto-measurement schedule |
| 0x2A | `setMeasurementInterval(...)` | Set auto-measurement schedule |
| 0x28 + 0x09 | `measureHeartRate(durationSeconds)` | Live HR measurement (returns `RingHrMeasurementResult`) |

Added `_parseFloat32Le()` helper (IEEE 754 LE32) for exercise calorie/distance fields.

### 4. Ring live command round-trip (advisor → ring → advisor)
Full pipeline for the advisor to request on-demand ring measurements:

**Backend:**
- `models/ring_command.py` — request/response Pydantic models
- `services/ring_command_service.py` — create command, get pending, store result, get result
- `api/ring_command_routes.py` — `GET /ring/command/pending`, `POST /ring/command/{id}/result`
- Registered in `main.py`
- `ring_command_requests` MongoDB collection created on first use (no index migration needed)

**Flutter:**
- `core/services/ring_command_service.dart` — polls pending commands, executes BLE (`measureHeartRate` or `fetchRingTemperatureLive`), posts results back
- Called from `ring_provider.dart` `_syncSleepInBackground()` — runs after every connect and on every foreground resume

**Advisor skill:**
- `skills/system/lumie_internal/ring_live_measure.md` — keywords match "measure my heart rate", "check my temperature", etc.
- Inserts into `ring_command_requests` and `notification_queue` directly via `db`
- Polls for result every 2 s for up to 35 s
- Handles timeout, failed, and success cases with user-friendly responses

## Decisions Made

- **Skill inserts directly into `ring_command_requests`** rather than calling a route, because the `lumie_db` runtime runs Python directly against MongoDB — no HTTP round-trip needed.
- **Push notification wakes the app** before Flutter polls `GET /ring/command/pending` — this avoids the app needing a persistent background timer.
- **`RingCommandService` is fire-and-forget** — it never blocks the sync flow and never throws. All errors are logged only.
- **`measureHeartRate` blocks for `durationSeconds`** — this is intentional; BLE streaming must stay live for the full duration.

## New Files Created

### Backend
- `lumie_backend/app/models/ring_command.py`
- `lumie_backend/app/services/ring_command_service.py`
- `lumie_backend/app/api/ring_command_routes.py`
- `lumie_backend/app/skills/system/lumie_internal/ring_live_measure.md`

### Flutter
- `lumie_activity_app/lib/core/services/ring_command_service.dart`

## Modified Files

### Flutter
- `lumie_activity_app/lib/shared/models/ring_models.dart` — new model classes
- `lumie_activity_app/lib/core/services/ring_ble_service.dart` — new BLE commands
- `lumie_activity_app/lib/features/ring/providers/ring_provider.dart` — wired RingCommandService
- `lumie_activity_app/lib/features/dashboard/screens/dashboard_screen.dart` — sync subtitle
- `lumie_activity_app/lib/main.dart` — added RingSyncService to provider tree

### Backend
- `lumie_backend/app/main.py` — registered ring_command_router

## API Endpoints Added
- `GET /api/v1/ring/command/pending` — Flutter polls (returns pending command or null)
- `POST /api/v1/ring/command/{request_id}/result` — Flutter posts BLE measurement result

## New DB Collections
- `ring_command_requests` — `{request_id, user_id, command_type, duration_seconds, status, created_at, result, completed_at, error}`
  - No explicit indexes yet; volume is very low (one doc per advisor request)

## Testing Checklist
- [ ] Ask advisor "measure my heart rate" — confirm push notification sent, app wakes, ring measures, result returned in advisor chat
- [ ] Ask advisor "check my temperature" — same flow
- [ ] Ask when ring is out of range — confirm timeout message after ~35 s
- [ ] Dashboard shows "Ring data syncing…" during sync, reverts to "Here's your day at a glance" after
- [ ] Verify all new BLE commands don't crash when called on a connected ring (smoke test via test app first)
- [ ] Exercise fetch (0x5C) returns records and parses correctly
- [ ] Detailed steps (0x52) returns per-minute buckets

## Future Work / Deferred
- Exercise data is fetched but not yet synced to the backend (no `exercise_sessions` collection or route exists yet)
- Detailed steps (0x52) are fetched but currently only used locally — backend only stores `daily_steps` (0x51 level)
- `setMeasurementInterval` / `getMeasurementInterval` are ready but no UI exists to configure them
- `ring_command_requests` collection should get a TTL index (e.g. 24 h) to auto-expire old requests
- Live HR measurement blocks the BLE service for `durationSeconds` — if another sync starts concurrently, it may conflict; a mutex should be added in a future refactor
