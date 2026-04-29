# HR session fixes — REVERTED 2026-04-28

**Status: REVERTED.** The fixes proposed in this dev-log were merged
earlier in the day and immediately produced *worse* behaviour in the
field — only 225 readings committed in a 79-minute session that should
have produced thousands, plus phantom auto-pauses every 10 s. All five
behaviour changes have been backed out. The diagnostic-logging
infrastructure (DebugLogService, dlog() call sites, Diagnostics screen,
iOS file-sharing flags) is preserved.

## Why the fixes failed

The watchdog was designed for the wrong failure mode.

**What it was built for:** the 18:40:43 case from the original
investigation, where `RingBleService.scanAndReconnectByName` failed in
`setNotifyValue` after `_connectedDevice` / `_writeChar` were already
populated. In that case `isConnected` returned a lie, and the BLE link
really was dead.

**What actually happens far more often:** the ring exits its own
exercise mode. From `logs/lumie_diag 2.log`:

```
02:03:13.469 [HR_BLE] 0x18 → 72 BPM (t=179s)
02:03:13.521 [HR_BLE] 0x18 dropped — byte[1]=0xff       ← ring sends end-of-exercise
02:03:13.552 [HR_BLE] notify cmd=0x28 len=16             ← ring confirms exercise mode off
02:04:14.938 [HR_PROV] stall detected: no readings for 61s (totalStall=31s, connected=true)
02:04:14.938 [HR_PROV] recovery: cancelling stale _hrSub + forcing reconnect
02:04:14.938 [HR_PROV] recovery: tryReconnect returned (connected=true)   ← short-circuits, no-op
```

Here BLE is healthy. The fix's `_recoverHrStream` calls
`ring.tryReconnect()` which short-circuits at
[ring_provider.dart:128-135](../../lumie_activity_app/lib/features/ring/providers/ring_provider.dart#L128-L135)
because `_bleService.isConnected==true`. The recovery does nothing
useful — it just keeps tearing down `_hrSub` every 10 s, racing with
incoming packets. The right action would have been to **re-issue 0x28 /
0x09 / 0x19** (restart the ring's exercise mode), not to reconnect.

Other concrete failures in the same log:
- **Recovery double-fires within 200 ms**
  (02:04:14.938 + 02:04:15.152, both `no readings for 61s`). The forced
  `_lastRingConnected=false` → tryReconnect notify → synchronous
  `_onRingStateChanged` re-entry path triggers a second pass within the
  same 10 s tick.
- **Auto-pause at 832 s stall**  (02:00:06) — the anchor calculation
  `_stallStartedAt = lastReading + 30s` doesn't reset when the ring
  exits exercise mode, so the user gets a confusing pause/resume loop
  with stalls that grow across the loop.
- **Final session: 225 readings.** The earlier broken-state run produced
  938. The fix made the data worse.

## What is reverted (this commit)

All behaviour changes from the previous round:
- Fix #1 (partial-reconnect cleanup in `RingProvider._tryReconnectInternal`)
- Fix #2 + #5 (stall watchdog + auto-pause-on-stall in `HeartRateProvider`)
- Fix #3 (extend-cap API + UI: remaining label, extend button, snackbars,
  stalled banner)
- Fix #6 (1-min heartbeat timer in `DebugLogService`)

Files restored to their pre-fix state (the diagnostic-only version):
- `lumie_activity_app/lib/features/ring/providers/ring_provider.dart`
- `lumie_activity_app/lib/features/heart_rate/providers/heart_rate_provider.dart`
- `lumie_activity_app/lib/features/heart_rate/screens/heart_rate_screen.dart`
- `lumie_activity_app/lib/core/services/debug_log_service.dart`

## What is preserved

- `DebugLogService` (file logging + Diagnostics toggle UI)
- All `dlog()` call sites in BLE/HR code
- iOS `Info.plist` flags (`UIFileSharingEnabled`,
  `LSSupportsOpeningDocumentsInPlace`)
- The original `2026-04-28-advisor-multi-turn-skill-retrieval.md`
  and other unrelated dev-logs

## What we now know about the failure modes

From the second log we can distinguish two genuinely different cases
that both look like "no more readings":

1. **Ring exits exercise mode** (sends `0x18 byte[1]=0xff` then a
   confirming `0x28` notify). BLE link healthy. The right fix is to
   detect the 0xFF/0x28 pair and re-issue 0x28 + 0x09 + 0x19. Probably
   the ring has its own ~30-min cap and we're hitting it.
2. **Partial reconnect leaves stale BLE state** (the original
   2026-04-28-graph-freeze case, line 18:40:43 of `lumie_diag.log`).
   `setNotifyValue` failed but `_writeChar` stayed set. Far rarer than
   case #1.

## Next steps (deferred)

- **Detect 0xFF + 0x28 in `ring_ble_service.dart` notify handler.**
  When seen during measurement, send 0x28 / 0x09 / 0x19 again to
  restart the ring's exercise mode, *without* touching the BLE link
  or the HR stream subscription. This is the actual fix for case #1
  and was completely missed in the first attempt.
- **Surface the cap with a non-disruptive UI element only.** Show
  remaining time, but no extend button until we're sure we won't
  trigger ChangeNotifier rebuild storms (the extend button rebuilt
  the whole measure card every second to recompute "<5 min" — a
  contributing source of the rebuild pressure suspected from the
  original investigation).
- **Treat case #2 with `isConnected` honesty separately** from any
  active recovery. The right fix is in `RingBleService` itself —
  null `_writeChar` when `setNotifyValue` throws.
- Continue collecting diag logs. They told us exactly why the fix
  failed; that infrastructure stays.
