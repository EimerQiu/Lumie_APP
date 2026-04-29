# HR graph freeze investigation + on-device diagnostic logging

**Date:** 2026-04-28
**Author:** debug session

## Symptom

When the ring's BLE signal is unstable, the HR measurement screen's live
graph freezes after 30–45 minutes. The smart ring keeps measuring (visible
in the historical data once you stop), but the on-screen BPM and graph stop
updating.

## Investigation — three suspect areas, no smoking gun

Read through the full HR pipeline:

- BLE notify → `RingBleService.startHrStreaming` (ring_ble_service.dart)
- BLE int stream → `HeartRateProvider._onRawReading` (heart_rate_provider.dart)
- `_sessionReadings` → `HrSessionChart` (hr_session_chart.dart, fl_chart)

Three plausible causes, ranked:

1. **fl_chart rebuild bottleneck.** `HrSessionChart` uses `isCurved: true`
   over the entire `_sessionReadings` list. At 1 Hz, 30–45 min ≈ 1800–2700
   spots, each requiring a Bézier segment. Every `_onRawReading` calls
   `notifyListeners()` → full chart rebuild. As the spot count grows, frame
   time crosses the reading interval, the UI thread starves, and the chart
   "freezes" while the BLE listener (off the platform channel) keeps
   running. Matches the symptom precisely.

2. **Stream-subscription leak on unstable signal.**
   `HeartRateProvider._onRingStateChanged` calls `_hrSub?.cancel()` without
   `await`, and `RingBleService.startHrStreaming` does
   `_hrStreamController?.close()` without `await`. Across many
   disconnect/reconnect cycles, you can stack overlapping notify listeners
   on the same characteristic, multiplying reading dispatch and rebuild
   pressure.

3. **`_mergeBackfilledPoints` rebuilds the entire `_sessionReadings`** every
   backfill round (clear + addAll). After many backfill rounds it grows
   slow; compounds with #1.

Decision: don't apply a speculative fix without evidence. Add the on-device
diagnostic logging the user requested so the next 30–45 min unstable-signal
session produces a downloadable file that disambiguates the three causes.

## Decisions made

- **File-based logging, opt-in.** Off by default. User flips a toggle in
  Settings → Diagnostics, runs a session, and pulls the file off the device.
  Off-by-default keeps prod logs from filling the disk; opt-in means we get
  *exactly* the failing session, not a rolling window we hope contains it.
- **Single serial write queue.** All `dlog()` calls enqueue onto one Future
  chain so writes never overlap and never block the BLE/HR pipeline. File
  IO failures are swallowed.
- **20 MB rotation cap, 1 backup.** A 30–45 min session generates ~1–3 MB
  of logs at the chosen verbosity, so 20 MB easily covers a full session.
- **iOS file-sharing on.** Set `UIFileSharingEnabled` and
  `LSSupportsOpeningDocumentsInPlace` so the user pulls the log via the
  Files app on the iPhone (no Xcode required).
- **No new package dependency.** Used only existing `path_provider` +
  `shared_preferences`. Considered `share_plus` for an in-app share sheet
  but the Files app path keeps the dep tree unchanged.
- **Periodic diag summary every 10 s** while measuring: readings/notify
  counts, session size, pending/attempted gap counts, backfill state. This
  is what tells us *which* of the three suspects is firing — a runaway
  notify rate, runaway session size, or stuck backfill.

## What gets logged (when toggle is on)

`HR_BLE` (ring_ble_service.dart):
- Every notify packet's command byte + length (catches duplicate listeners)
- 0x18 → BPM with t-counter (catches missing/stale packets vs. UI lag)
- 0x18 dropped (warming up / 0xFF end / value out of range)
- 0x28 / 0x09 / 0x19 start/stop ack or error
- Stream controller lifecycle (`startHrStreaming` begin / wiring done,
  `stopHrStreaming` begin / end, prev controller+sub state)
- Notify error events
- "DROPPED (controller closed) — leaked listener?" if a packet arrives on
  a closed controller (this is the smoking gun for hypothesis #2)

`HR_PROV` (heart_rate_provider.dart):
- `startMeasurement` / `pauseMeasurement` / `resumeMeasurement` / `stopMeasurement`
- Out-of-range reading rejections
- Gap detected → range size enqueued for backfill
- Backfill begin / fetch ms + counts / merge ms + before/after sizes / end
- Backfill error
- Ring DISCONNECTED / RECONNECTED transitions including session size
- Reconnect re-subscribe with previous _hrSub state (to detect leaks)
- 10 s diag summary: readings, notify count, session size, pending/attempted
  gaps, backfill state, connection state — all in one line

`RING` (ring_provider.dart):
- BLE connectionState transitions
- Unexpected disconnect → onDisconnected callback
- handleDisconnected → auto-reconnect scheduled
- reconnect attempt with cached name/id
- Preferred reconnect failure → scan fallback
- reconnect success / reconnect failure

## How to interpret the logs

After the user reproduces the freeze, look for one of these signatures in
the diag summary:

- **Hypothesis #1 (chart bottleneck):** `notify` and `readings` stay in the
  expected ratio (~1:1) until shortly before the freeze, then `notify` keeps
  climbing while UI frames stop landing. Will also see the read intervals
  in `0x18 → N BPM` lines stay regular while the user reports the screen
  frozen.
- **Hypothesis #2 (listener leak):** `notify` count diverges *upward* from
  `readings` over time (multiple listeners → multiple notifyListeners per
  packet). Or `0x18 → N BPM DROPPED (controller closed)` lines appear.
- **Hypothesis #3 (backfill blowup):** `pendingGaps` keeps growing or
  `merge backfill: X → Y in Zms` shows `Z` climbing into hundreds of ms.

## New files

**Backend:** none.

**Frontend:**
- `lumie_activity_app/lib/core/services/debug_log_service.dart` —
  singleton; persists toggle in SharedPreferences (`debug_log_enabled`);
  writes to `${ApplicationDocumentsDirectory}/lumie_diag.log`; rotates to
  `lumie_diag.log.1` at 20 MB; `dlog(tag, msg)` top-level shorthand.
- `lumie_activity_app/lib/features/settings/screens/diagnostics_screen.dart`
  — toggle, file size, file path with copy button, clear button, and an
  inline help card for downloading via Files app or Xcode.

## Modified files

**Backend:** none.

**Frontend:**
- `lumie_activity_app/lib/main.dart`
  - `import 'core/services/debug_log_service.dart';`
  - `import 'features/settings/screens/diagnostics_screen.dart';`
  - `DebugLogService().init();` in `main()` (loads persisted toggle early)
  - Added `'/settings/diagnostics': (context) => const DiagnosticsScreen()`
    route
  - Added "Diagnostics" entry under General in the settings list
- `lumie_activity_app/lib/core/services/ring_ble_service.dart`
  - `import 'debug_log_service.dart';`
  - `dlog('HR_BLE', ...)` in `startHrStreaming` (begin/wiring/per-packet/error),
    `stopHrStreaming` (begin/per-cmd/end), connectionState listener
  - Logged `0x28` / `0x09` / `0x19` start+stop acks/errors
- `lumie_activity_app/lib/features/heart_rate/providers/heart_rate_provider.dart`
  - `import '../../../core/services/debug_log_service.dart';`
  - Added counters `_readingsSinceLastSummary`,
    `_notifyListenersSinceLastSummary`, timer `_diagSummaryTimer`
  - Added `_startDiagSummaryTimer()` / `_stopDiagSummaryTimer()` — emits a
    one-line diag summary every 10 s while measuring
  - `dlog('HR_PROV', ...)` for: start/pause/resume/stop, gap detection,
    backfill begin/fetch/merge/end/error, ring DISCONNECTED/RECONNECTED,
    reconnect re-subscribe, out-of-range readings, stream errors
  - `dispose()` cancels `_diagSummaryTimer`
- `lumie_activity_app/lib/features/ring/providers/ring_provider.dart`
  - `import '../../../core/services/debug_log_service.dart';`
  - `dlog('RING', ...)` for: handleDisconnected, reconnect attempt,
    preferred-reconnect failure, reconnect success/failure
- `lumie_activity_app/ios/Runner/Info.plist`
  - Added `UIFileSharingEnabled` = true
  - Added `LSSupportsOpeningDocumentsInPlace` = true

## API endpoints added

None.

## New DB collections / indexes

None.

## Testing checklist

- [ ] Cold-start the app — Diagnostics toggle defaults to OFF
- [ ] Flip toggle ON → start an HR session → log file appears with size > 0
- [ ] Flip toggle OFF mid-session → no further lines after toggle
- [ ] Flip ON, start session, kill app, reopen, start session — second
  session appends (no overwrite) and `Logging enabled` line is preserved
- [ ] Force >20 MB file → rotation creates `.1` backup
- [ ] Tap Clear → both files removed, sizes show 0 B
- [ ] iOS Files app shows `Lumie` folder containing `lumie_diag.log` after
  enabling logging (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace
  active after a fresh install / Xcode rebuild)
- [ ] Run a 30–45 min session with intentional unstable signal (cover the
  ring intermittently or move out of BLE range), reproduce the freeze, then
  pull the log and look at the diag summary lines for the signature

## Future work / what's deferred

- **Apply a fix once the log narrows it down.** Likely candidates:
  - If hypothesis #1: downsample chart input (cap at ~300 visible spots,
    binning by time) and/or set `isCurved: false`
  - If hypothesis #2: make `_hrSub?.cancel()` and
    `_hrStreamController?.close()` `await`ed; add a generation counter on
    the controller so stale listeners are ignored
  - If hypothesis #3: append-only merge instead of clear + rebuild
- **Add `share_plus`** for one-tap sharing if Files-app discovery proves
  awkward in practice.
- **Crash/foreground-switch logging** — currently we log only inside the
  HR/BLE pipeline. Adding `WidgetsBindingObserver.didChangeAppLifecycleState`
  logging would help if the freeze coincides with backgrounding.
