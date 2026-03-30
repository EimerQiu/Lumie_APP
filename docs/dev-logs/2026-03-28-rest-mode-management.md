# 2026-03-28 — Rest Mode Management

## Decisions Made

- **RestModeService is purely client-side** — The existing backend `RestDaysService` tracks a weekly schedule (days of the week). Rest Mode is a separate, ephemeral "I need rest today" state that lives only in SharedPreferences. No new backend endpoint was needed. The two sources are OR-ed together: `_isRestDay = scheduledRestDay || restModeActive`.

- **24 h expiry via timestamp, not a live timer** — A live Dart `Timer` would be cancelled on app close. Instead, the activation `DateTime` is stored as an ISO-8601 string in SharedPreferences. On app launch and on every app resume (`didChangeAppLifecycleState`), `checkAndExpire()` compares `now - activatedAt` against 24 h and removes the key if elapsed. This is simpler and more reliable than a background timer.

- **Activation wired to the existing suggestion sheet** — `RestDaySuggestionSheet.show()` already calls `RestDaysService().setTodayAsRestDay()` on accept. Added `RestModeService().activate()` immediately after, so the 24 h timer starts from the moment the user says yes. No new activation UI was required.

- **Manual turn-off only available for manual Rest Mode** — The "Turn Off" tap handler (`onTap`) is passed to `AdaptiveGoalCard` only when `_restModeActive` is true. When `_isRestDay` is true solely because of a backend-scheduled rest day, the card is not tappable (users adjust the schedule via Settings → Rest Day Schedule instead).

- **AdaptiveGoalCard badge changes when tappable** — When `onTap != null` the "Rest Day" badge in the card header changes its icon from ↓ to ✕ and its label from "Rest Day" to "Turn Off", giving a clear affordance without extra text or buttons.

- **Reason text differentiates manual vs scheduled** — Dashboard passes a different `reason` string depending on which mode is active, so the card always explains why the goal is reduced.

## New Files

### Frontend
- `lib/core/services/rest_mode_service.dart` — Singleton; `activate()`, `deactivate()`, `checkAndExpire()`, `isActive` getter, `timeRemaining` getter; persists activation timestamp via SharedPreferences

## Modified Files

### Frontend
- `lib/features/dashboard/widgets/rest_day_suggestion_sheet.dart`
  - Added import: `rest_mode_service.dart`
  - Added `await RestModeService().activate()` in `onAccept` callback, after `setTodayAsRestDay()`
- `lib/features/dashboard/widgets/adaptive_goal_card.dart`
  - Added `VoidCallback? onTap` parameter
  - Wrapped `GradientCard` with `GestureDetector`
  - "Rest Day" badge shows ✕ icon + "Turn Off" label when `onTap != null`
- `lib/features/dashboard/screens/dashboard_screen.dart`
  - Added import: `rest_mode_service.dart`
  - Added `_restModeActive` bool field
  - `_loadRestDayStatus()`: calls `RestModeService().checkAndExpire()` first, then computes `_isRestDay = scheduledRestDay || restModeActive`
  - `didChangeAppLifecycleState(resumed)`: now also calls `_loadRestDayStatus()` so expiry is caught when user returns to app
  - Added `_onTapRestDayGoal()`: shows confirmation dialog, calls `RestModeService().deactivate()` on confirm, then reloads
  - `AdaptiveGoalCard` receives `onTap: _restModeActive ? _onTapRestDayGoal : null` and updated `reason` text
- `lib/main.dart`
  - Added import: `rest_mode_service.dart`
  - Added `await RestModeService().init()` in `main()` (alongside `RingSyncService().init()`)

## API Endpoints Added

None — Rest Mode is client-side only.

## New DB Collections

None.

## Testing Checklist

- [ ] Accept rest day suggestion → Rest Mode activates → Today page shows Rest Day Goal block, activity ring hidden
- [ ] "Turn Off" badge visible on Rest Day Goal card
- [ ] Tap card → dialog shows "Turn Off Rest Mode?" with [Keep Rest Mode] / [Turn Off Rest Mode]
- [ ] Tap "Keep Rest Mode" → dialog dismisses, Rest Mode still active
- [ ] Tap "Turn Off Rest Mode" → Rest Mode deactivates → regular Activity Goal restored
- [ ] Close and reopen app within 24 h → Rest Mode still active
- [ ] Close app, advance device clock past 24 h, reopen → Rest Mode expired, regular goal shown
- [ ] App backgrounded for 24+ h → come to foreground → Rest Mode expired immediately (via `didChangeAppLifecycleState`)
- [ ] Scheduled rest day (no manual activation) → card shown, but NOT tappable (no "Turn Off" badge)
- [ ] Scheduled rest day + manual Rest Mode both active → card is tappable; turning off only clears manual mode (scheduled still shown until midnight)

## Future Work / Deferred

- Add a "Start Rest Mode" button directly on the Today page (e.g., long-press or dedicated button) so users can activate it without waiting for a sleep-quality suggestion
- Extend `AdaptiveGoalCard` to show remaining hours ("Rest Mode ends in 3 h") using `RestModeService().timeRemaining`
- Consider persisting a "user dismissed scheduled rest day" flag so the card can be hidden for scheduled days too
