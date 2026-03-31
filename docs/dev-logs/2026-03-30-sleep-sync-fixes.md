# 2026-03-30 — Sleep Sync Fixes & Sleep Validity Rules

Four interrelated fixes for sleep data reliability, notification correctness, and resting-HR computation.

---

## Bug 1: Rest Day Suggestion Firing With No Valid Sleep Data

**Root cause:** `RestDaysService._get_latest_sleep()` in `rest_days_service.py` did a raw `find_one` on the `sleep_sessions` collection with no quality or nighttime filtering. Ring-noise sessions (all-light, < 30 min, quality < 5) stored in the DB could satisfy `quality_score < 60`, triggering a rest-day suggestion even though no real sleep was detected.

**Fix (`lumie_backend/app/services/rest_days_service.py`):**
- `_get_latest_sleep()` now applies the same filters as `SleepService.get_latest()`:
  - Bedtime in nighttime window (8 PM – 6 AM)
  - Wake time before noon (12 PM)
  - At least 180 minutes of sleep (3 hours minimum)
  - Quality score ≥ 5
  - At least some deep or REM stage data (confirming ring was worn, not sitting on a table)
  - Session within the last 3 days
- Uses an async cursor with `limit=20` and breaks on first passing document — same logic as the main sleep service.

---

## Bug 2: Sleep Data Not Syncing Reliably

**Root cause:**
1. `SleepScreen._loadSleepData()` checked `ringProvider.isConnected` at `initState` time. On an `IndexedStack`, `initState` runs before the ring reconnects in the background — so the ring fetch was always skipped on cold load.
2. The `_onRingStateChanged` listener only triggered when the sleep screen was already open. If the user was on the dashboard when the ring reconnected, no sync happened.
3. No retry on BLE timeout (ring sends incomplete records, app uploaded partial data).

**Fix (`lumie_activity_app/lib/features/ring/providers/ring_provider.dart`):**
- Added `_syncSleepInBackground()` / `_runSleepSync()` — runs automatically after every successful connect or reconnect (both `_tryReconnect()` and `_autoReconnectWithRetry()`).
- If the first sleep fetch returns `isComplete=false`, retries once after 3 seconds.
- Also fetches HR history (0x55) for resting-HR computation (non-critical — failures are logged and ignored).
- Calls `SleepService().syncFromRingRecords(records, isComplete:, hrHistory:)`.

**Fix (`lumie_activity_app/lib/features/sleep/screens/sleep_screen.dart`):**
- Removed the ring fetch from `_loadSleepData()` — ring sync now happens in RingProvider, not the screen.
- Split into `_loadSleepData()` (sets loading state, delegates to `_loadFromBackend()`) and `_loadFromBackend()` (reads from backend only).
- `_onRingStateChanged()` now calls `_reloadAfterRingSync()`: waits 10 s for the background sync to upload, then calls `_loadFromBackend()`.
- All `setState` calls guarded with `mounted` checks.

---

## Fix 3: HR Collection During Sleep (Battery Optimization)

**Problem:** `resting_heart_rate` was hardcoded to `0` in every uploaded sleep session. `fetchHrHistory()` (0x55) filtered to today's date only, missing 11 PM–midnight readings from the previous calendar day that fall within the sleep session window.

**Fix — `ring_ble_service.dart`:**
- `fetchHrHistory()` changed from "today only" filter to a 24-hour rolling window: keeps all records with `time.isAfter(DateTime.now().subtract(Duration(hours: 24)))`. This captures nighttime sleep-window readings that span midnight.

**Fix — `sleep_service.dart`:**
- `syncFromRingRecords()` now accepts `List<HrDataPoint> hrHistory` (optional, defaults to empty).
- New `_computeRestingHr(hrHistory, start, end)` helper:
  1. Filters HR points to the sleep session window with plausible values (35–120 bpm).
  2. Groups into 10-minute buckets and averages each bucket.
  3. Returns the median of the bucket averages (robust against transient spikes during brief awakenings).
  4. Returns 0 if fewer than 2 readings exist (not meaningful).
- `_ringRecordToPayload()` now passes `hrHistory` to `_computeRestingHr()` and uses the result as `resting_heart_rate` in the upload payload.
- Resting HR > 0 in sleep data now feeds the `WellnessService` Fatigue/Stress calculations.

*Note: The ring's internal HR sampling frequency during sleep is controlled by firmware — we cannot change it via BLE commands. The 10-minute windowing is applied on the Flutter side when computing RHR from whatever readings the ring has stored.*

---

## Fix 4: Sleep Detection Validity Rules

**Frontend (`sleep_service.dart`) — upload-time gates:**
- Minimum raised from `> 0` to `>= 180` minutes (3 continuous hours).
- Records with `deepMinutes == 0 && remMinutes == 0` are discarded (all-light = ring not worn, no body-temperature/PPG signal variation to produce real staging).
- Each skipped record is logged with the reason.

**Backend (`sleep_service.py`) — storage/query filters:**
- `_passes_quality_filter()`: minimum raised from 30 → 180 minutes.
- `_passes_quality_filter()`: all-light sessions now always rejected regardless of duration (previously only rejected if under 60 min). Sessions with no stage data at all are also rejected.
- `_is_nighttime_session()`: wake-time cutoff tightened from before 1 PM (13:00) to before noon (12:00) per spec.

---

## Modified Files

### Backend
- `lumie_backend/app/services/rest_days_service.py` — rewritten `_get_latest_sleep()` with full validity filtering
- `lumie_backend/app/services/sleep_service.py` — `_passes_quality_filter()` and `_is_nighttime_session()` tightened

### Frontend
- `lumie_activity_app/lib/core/services/ring_ble_service.dart` — `fetchHrHistory()` now accepts last 24 h instead of today only
- `lumie_activity_app/lib/core/services/sleep_service.dart` — validity gates, `_computeRestingHr()`, `hrHistory` param
- `lumie_activity_app/lib/features/ring/providers/ring_provider.dart` — `_syncSleepInBackground()` triggered on every reconnect
- `lumie_activity_app/lib/features/sleep/screens/sleep_screen.dart` — removed duplicate ring fetch, split `_loadSleepData` / `_loadFromBackend`, added `_reloadAfterRingSync`

## Testing Checklist

- [ ] Ring not connected on app open → sleep screen shows last known backend data (no crash, no "syncing" spinner stuck)
- [ ] Ring connects in background (any screen open) → background sync triggers within 15 s
- [ ] After background sync, open sleep screen → shows fresh data from last night
- [ ] Short ring-noise session (< 3 h, all-light) is not uploaded to backend
- [ ] Session without deep/REM stages is not uploaded (ring off table test: set ring on desk overnight)
- [ ] Session with valid stages AND HR readings shows non-zero resting HR on sleep screen
- [ ] Rest-day suggestion sheet does NOT appear when there is no valid sleep session
- [ ] Rest-day suggestion sheet appears only when sleep quality < 60 AND all validity criteria pass
- [ ] BLE timeout during sleep fetch → retry triggers → still shows data
- [ ] `SleepService.lastSyncWasComplete` = false after a timed-out fetch shows "Sync incomplete" indicator

## Future Work

- Expose `_syncSleepInBackground` as a public `triggerSleepSync()` so a manual "Re-sync" button on the sleep screen can call it.
- Add `clearOnLogout()` to `SleepService` (clear `lastSyncedAt`) so stale indicators don't show after re-login.
- Backend: once resting HR is reliably populated, add `resting_heart_rate > 0` as a hard gate in `_passes_quality_filter` to confirm ring was worn.
