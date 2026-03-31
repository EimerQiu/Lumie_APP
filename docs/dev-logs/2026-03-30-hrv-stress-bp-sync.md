# HRV / Stress / Blood Pressure Sync

**Date:** 2026-03-30

## What was built

Full end-to-end sync pipeline for HRV, stress (fatigue), and blood pressure data from ring command 0x56.

## Decisions made

- **Upsert by (user_id, timestamp):** Re-syncing the same readings is idempotent — safe to re-run on reconnect.
- **Cutoff filter in RingSyncService:** Reuses the existing 24-hour-before-last-sync cutoff so stale records aren't repeatedly uploaded.
- **`RingSyncService.triggerSync()` wired up:** The provider had its own `_runSleepSync()` that bypassed `RingSyncService` entirely. Replaced it with `triggerSync()` passing all four callbacks (sleep, HR, steps, HRV). This unifies all ring sync through one service and persists the sync timestamp properly.
- **0x56 packet layout (15 bytes):** BCD timestamp at bytes [3–8], hrv at [9], hr at [11], fatigue at [12], systolic at [13], diastolic at [14]. Records with hrv==0 && hr==0 && systolic==0 are skipped (ring pads empty slots).

## New files

### Backend
- `lumie_backend/app/models/hrv.py` — Pydantic models: `HrvDataPoint`, `HrvSyncRequest`, `HrvSyncResponse`, `HrvReadingResponse`, `HrvHistoryResponse`
- `lumie_backend/app/services/hrv_service.py` — `sync_readings()` (bulk upsert), `get_history(user_id, days)` (returns last N days)
- `lumie_backend/app/api/hrv_routes.py` — `POST /hrv/sync` and `GET /hrv`

## Modified files

### Backend
- `lumie_backend/app/main.py` — Added `hrv_router` import and `app.include_router(hrv_router, prefix="/api/v1")`

### Flutter
- `lumie_activity_app/lib/shared/models/ring_models.dart` — Added `RingRawHrvRecord` model
- `lumie_activity_app/lib/core/services/ring_ble_service.dart` — Added `fetchHrvHistory()` (0x56 BLE fetch + parse)
- `lumie_activity_app/lib/core/services/ring_sync_service.dart` — Added `fetchHrv` optional callback to `triggerSync()` / `_runSync()`, HRV cutoff filter, `_uploadHrvReadings()` method
- `lumie_activity_app/lib/features/ring/providers/ring_provider.dart` — Replaced `_syncSleepInBackground()` / `_runSleepSync()` with `RingSyncService().triggerSync(fetchSleep, fetchHr, fetchSteps, fetchHrv)`. Removed `sleep_service.dart` import (sync now handled entirely by `RingSyncService`).

## API endpoints added

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/hrv/sync` | Batch upload HRV readings from ring |
| GET | `/api/v1/hrv?days=7` | Fetch HRV history for last N days (1–90) |

## New DB collections / indexes

- Collection: `hrv_readings`
- Index: `(user_id, timestamp)` unique — enforced via upsert filter; add explicit index on server if query volume grows

## Testing checklist

- [ ] Ring connects → `triggerSync` fires → 0x56 command sent → records parsed
- [ ] `POST /api/v1/hrv/sync` stores readings in `hrv_readings`
- [ ] Re-sending same records doesn't duplicate
- [ ] `GET /api/v1/hrv?days=7` returns correct date-filtered readings
- [ ] Ring with no HRV data (all-zero records) → nothing uploaded

## Future work / deferred

- Expose HRV / stress / BP data in the app UI (no screen built yet)
- Add explicit MongoDB compound index `{user_id: 1, timestamp: -1}` via migration script
- Consider surfacing HRV trend in the advisor context window
