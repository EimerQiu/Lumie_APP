# 2026-03-28 — Ring Auto-Sync on Connection

## Decisions Made

- **Centralized sync, not screen-local** — Previously `SleepScreen` triggered its own ring sync when it detected a ring connect. That meant sleep only synced when the user was on the sleep tab. Now `RingProvider` triggers a full sync immediately after every successful BLE connection (initial pair, manual reconnect, auto-reconnect), so all data types sync regardless of which screen is visible.

- **Callback pattern to break circular import** — `RingProvider` would create a circular import if it imported `RingSyncService` while `RingSyncService` imported `RingProvider` back. Solution: `triggerSync()` accepts typed callbacks (`fetchSleep`, `fetchHr`) so `RingSyncService` never needs to import `RingProvider`.

- **`RingSyncService` as singleton ChangeNotifier in MultiProvider** — The factory always returns the same instance, so both non-widget code (`RingProvider`) and widget code (`Consumer<RingSyncService>`) see the same state.

- **Incremental sync with 24 h buffer** — `lastSyncAt` is persisted in SharedPreferences. On each sync, records older than `(lastSyncAt − 24 h)` are skipped before uploading to the backend. The 24 h buffer catches sessions that spanned midnight during the previous sync. The backend uses upsert semantics so re-sending old records is harmless.

- **HR history goes to new `/hr/sync` endpoint** — The ring's 0x55 command returns today's HR readings. These are now batch-uploaded to the backend on every connection. The backend deduplicates by `{user_id, timestamp}`.

- **Sleep screen no longer does its own ring sync** — `SleepScreen._loadSleepData()` now only fetches from the backend. It listens to `RingSyncService` and reloads after a sync completes, showing whatever was in the backend while the background sync runs.

- **`RingSyncIndicator` widget** — Reusable widget that reads `Consumer<RingSyncService>` and shows spinning "Syncing…", "Synced Xm ago", or "Sync incomplete · Xm ago". Placed in the sleep screen header and the ring management status card.

## New Files

### Backend
- `lumie_backend/app/models/hr.py` — `HrDataPoint`, `HrSyncRequest`, `HrSyncResponse`
- `lumie_backend/app/services/hr_service.py` — `HrService.sync_readings()` with upsert-per-point logic
- `lumie_backend/app/api/hr_routes.py` — `POST /api/v1/hr/sync`

### Frontend
- `lib/core/services/ring_sync_service.dart` — `RingSyncService` singleton; `triggerSync()`, `_runSync()`, `_uploadHrReadings()`; persists `lastSyncAt` via SharedPreferences
- `lib/shared/widgets/ring_sync_indicator.dart` — `RingSyncIndicator` widget

## Modified Files

### Backend
- `lumie_backend/app/main.py` — imported and registered `hr_router` at `/api/v1`

### Frontend
- `lib/features/ring/providers/ring_provider.dart`
  - Import `ring_sync_service.dart`
  - Added `_triggerBackgroundSync()` helper
  - Called after successful `_state = paired` in `connectAndPair()`, `_tryReconnect()`, and `_autoReconnectWithRetry()`
- `lib/features/sleep/screens/sleep_screen.dart`
  - Removed: ring provider listener, `_onRingStateChanged`, `didChangeDependencies`, ring-sync code in `_loadSleepData`, `_syncMessage`/`_syncWasIncomplete`/`_lastSyncedAt` fields, `_syncStatusLabel()`
  - Added: `RingSyncService().addListener(_onSyncStatusChanged)` in `initState`; `RingSyncIndicator` in header
- `lib/features/ring/screens/ring_management_screen.dart` — Added `RingSyncIndicator` below the status badge in `_StatusCard`
- `lib/main.dart`
  - `main()` is now `async`; calls `await RingSyncService().init()` before `runApp`
  - Added `ChangeNotifierProvider(create: (_) => RingSyncService())` to `MultiProvider`

## API Endpoints Added

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/hr/sync` | Batch-upload HR readings from ring (upsert by timestamp) |

## New DB Collections

- `hr_readings` — fields: `user_id`, `timestamp` (UTC), `bpm`
  - Implicit upsert index on `{user_id, timestamp}` — add explicit unique index before production

## Sync Trigger Points (Flutter)

| Event | Method | Sync triggered |
|-------|--------|----------------|
| First BLE pair | `connectAndPair()` | ✅ |
| Manual reconnect | `_tryReconnect()` | ✅ |
| Auto-reconnect on drop | `_autoReconnectWithRetry()` | ✅ |

## Testing Checklist

- [ ] App launch with ring previously paired → ring auto-reconnects → sync starts (indicator shows "Syncing…")
- [ ] Sync completes → indicator shows "Synced just now"
- [ ] Sleep screen opens during sync → shows cached backend data; refreshes when sync finishes
- [ ] Sleep screen opens after sync → shows freshly synced data immediately
- [ ] Ring disconnects and reconnects → sync fires again
- [ ] `POST /api/v1/hr/sync` with today's readings → 200, returns `{inserted: N}`
- [ ] Duplicate readings re-sent → `inserted: 0` (upsert, no duplicate docs)
- [ ] Network failure during sync → status shows `failed`; previous `lastSyncAt` preserved
- [ ] App restart → `lastSyncAt` restored from SharedPreferences; indicator shows correct elapsed time
- [ ] Ring management screen shows sync indicator in status card

## Future Work / Deferred

- Add `{user_id: 1, timestamp: 1}` unique index on `hr_readings`
- Expose `GET /api/v1/hr/history` for advisor context and trend views
- Activity step-count batch sync (currently only via the 0x2A keep-alive ping, no historical bulk fetch)
- Retry queue: if sync fails mid-flight, retry specific failed data types on next connection rather than the full sync
