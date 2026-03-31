# 2026-03-30 — Activity Goal Type Sync Across App

## Decisions made

### Single source of truth
`ActivityGoalProvider` is the sole authority for goal type and value.
Every widget that shows activity progress reads from it via `Consumer` / `context.watch` and rebuilds instantly when the user changes their goal type or custom override in Activity Goal settings.

### Goal type drives all displays
`ActivityGoalType.steps` → steps is the primary number everywhere; minutes appears as secondary info only on the Activity History detail card.
`ActivityGoalType.minutes` → minutes is primary everywhere; steps appears as secondary.

### Unit-agnostic widget params
`ActivityRing` and `AdaptiveGoalCard` no longer hard-code minutes. Both now accept generic `currentValue`/`goalValue`/`unitLabel` params so the same widget renders correctly for either unit.

### `_DayData` stores both units
`ActivityHistoryScreen._DayData` now carries both `goalMinutes` and `goalSteps`. `goalMet(type)` and `goalProgress(type)` are methods, not getters, so the correct unit is used at render time based on the watched provider.

### Mock step count on dashboard
Dashboard still uses mock data. Added `_currentSteps = 5600` (42 min × 8 000 / 60 ≈ 5 600) to accompany `_currentMinutes = 42`. Both `ActivityRing` and `AdaptiveGoalCard` on the dashboard receive the correct mock value for the active goal type.

## Modified files

### Frontend
- `lib/shared/widgets/circular_progress_indicator.dart` — `ActivityRing` params renamed: `currentMinutes`/`goalMinutes` → `currentValue`/`goalValue`/`unitLabel`
- `lib/features/dashboard/widgets/adaptive_goal_card.dart` — `AdaptiveGoalCard` params renamed: `recommendedMinutes`/`currentMinutes` → `goalValue`/`currentValue`/`unitLabel`
- `lib/features/activity/screens/activity_history_screen.dart` — Added `ActivityGoalProvider` import; added `goalSteps` to `_DayData`; changed `goalMet`/`goalProgress` to type-parameterised methods; `build()` watches provider; `_buildWeekSelector`, `_buildSelectedDaySummary`, `_buildWeeklyOverview` accept `ActivityGoalType goalType`; hero display swaps between steps and minutes based on goal type
- `lib/features/dashboard/screens/dashboard_screen.dart` — Added `_currentSteps` mock; added `_restDayGoalSteps`; `_activityScore` now accepts `ActivityGoalProvider` and respects goal type; `_buildMainActivityRing` and `AdaptiveGoalCard` call site both compute `currentValue`/`goalValue`/`unitLabel` from provider

## Testing checklist
- [ ] Switching to Steps mode: dashboard ring shows "5600 of X steps"
- [ ] Switching to Minutes mode: dashboard ring shows "42 of X min"
- [ ] AdaptiveGoalCard header updates immediately on type switch
- [ ] Activity score card rebuilds immediately on type switch
- [ ] Activity History hero shows steps when in steps mode
- [ ] Activity History hero shows minutes when in minutes mode
- [ ] Week selector dots use the correct goal type for "goal met" colouring
- [ ] Weekly overview "Goals Met" count uses the correct goal type
- [ ] Custom override persists across type switches (with unit conversion)
- [ ] No restart required for any of the above

## Future work / deferred
- Dashboard activity ring and AdaptiveGoalCard still use mock data (`_currentMinutes = 42`, `_currentSteps = 5600`); needs real step data synced from ring
- `ActivitySummaryCard` always shows minutes breakdown (ring-tracked vs manual); acceptable since it is a source-breakdown card, not a goal-progress card
