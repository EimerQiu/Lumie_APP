# Workout Recording Feature — Dev Log
**Date:** 2026-03-05

## Decisions Made

- **Dark "Apple Watch" UI** for the recording screen — full dark background (`#1A1816`) to feel immersive and focused during a workout. Matches the mental model users have from wearables.
- **State machine** (`acquiring → ready → recording → paused → finished`) keeps the UI predictable; each state maps to a clear button layout.
- **Real BLE + simulation fallback** — the screen tries `RingProvider.startHrStreaming()` (BLE command 0x09) on entry. If the ring isn't actively BLE-connected, a 5-second timer fires and uses simulated HR instead. This way the screen works in dev/testing without a real ring.
- **Ring status gate** — if the ring isn't paired or Bluetooth is off, a dialog blocks entry and explains the issue. "Connect Ring" navigates to `/ring/manage`. The charger case is handled by the generic "not connected" message (we cannot detect charging without an active BLE session).
- **Activity picker** — shown as a `showModalBottomSheet` (3-column grid of all 13 `ActivityType` predefined types). No separate file — small enough to inline in `activity_history_screen.dart`.
- **HR recorded only during `recording` state** — `_updateHr()` only appends to `_hrHistory` / updates `_maxHeartRate` when state is `recording`. HR is still displayed live during `acquiring` and `ready` but not tracked.

## New Files Created

### Frontend
- `lumie_activity_app/lib/features/activity/screens/workout_recording_screen.dart`
  - States: `_RecordingState` enum (acquiring, ready, recording, paused, finished)
  - BLE HR: starts `RingProvider.startHrStreaming()` on init, falls back to simulation
  - UI: large timer, pulsing heart icon, HR in BPM, state-driven bottom buttons
  - Finish view: duration / avg HR / max HR summary with Save / Discard

## Modified Files

### Frontend
- `lumie_activity_app/lib/features/activity/screens/activity_history_screen.dart`
  - Added `provider` + `ring_provider` + `workout_recording_screen` imports
  - Added `_onRecordWorkout()` — checks `ringProvider.isPaired && ringProvider.isBluetoothOn`
  - Added `_showRingRequiredDialog()` — shows dialog with context-appropriate message
  - Added `_showActivityPicker()` — bottom sheet → navigates to `WorkoutRecordingScreen`
  - Added `FloatingActionButton.extended` ("Record Workout") to Scaffold
  - Added `_ActivityPickerSheet` widget (3-col grid of activity types)
  - Increased `SingleChildScrollView` bottom padding to 100 to avoid FAB overlap

### (Auto-modified by linter)
- `lumie_activity_app/lib/core/services/ring_ble_service.dart`
  - Added `fetchHrHistory()` (command 0x55 — stored HR records)
  - Added `startHrStreaming()` / `stopHrStreaming()` (command 0x09 — real-time stream)
- `lumie_activity_app/lib/features/ring/providers/ring_provider.dart`
  - Delegated `fetchHrHistory()`, `startHrStreaming()`, `stopHrStreaming()` to BLE service

## API Endpoints Added
None — Save Workout is a TODO; no backend endpoint created yet.

## New DB Collections / Indexes
None.

## Testing Checklist
- [ ] Ring not paired → "Ring not connected" dialog appears
- [ ] Bluetooth off (ring paired) → "Turn on Bluetooth" dialog appears
- [ ] Activity picker shows all 13 types in 3-column grid
- [ ] Tapping activity → opens `WorkoutRecordingScreen` fullscreen
- [ ] Acquiring state: START button greyed, spinner visible
- [ ] After 5s (no real ring): HR shows 72, button turns green
- [ ] START → timer counts up, HR updates each second
- [ ] PAUSE → timer stops, RESUME/END buttons appear
- [ ] RESUME → timer resumes from where it stopped
- [ ] FINISH (confirm dialog) → finished view shows duration/avg HR/max HR
- [ ] Save → pops back to activity history
- [ ] Discard → pops without saving
- [ ] Back while recording → confirm dialog (don't just pop)
- [ ] Status bar turns white on dark screen, restores on pop

## Future Work / Deferred
- **Save to backend**: `WorkoutRecordingScreen` has a `// TODO: Save ActivityRecord to backend` comment. Needs `POST /api/v1/activities` endpoint + service call.
- **Real BLE reconnect for workouts**: Currently `startHrStreaming()` only works if the ring is still BLE-connected from the pairing session. A proper workout flow needs: scan → reconnect → start exercise mode (0x19) → stream HR → end exercise (0x19 stop) → disconnect.
- **Ring charging detection**: Battery charging status (0x13 response byte 2) is not yet parsed. Would allow a distinct "Ring charging" dialog vs "Ring not connected".
- **Calories / steps display**: `RingStreamData` has calories and steps from 0x09 stream — could be added to the recording screen.
