# 2026-03-30 — Wellness Scores (Fatigue & Stress)

Replaced all hardcoded Fatigue (72) and Stress (78) placeholder values with real calculations derived from ring sleep data.

## Decisions Made

- **Text labels, no numbers** for Fatigue and Stress: "Low / Med / High" in the star ring centre; "Low / Moderate / Elevated" and "Lower than usual / Typical / Higher than usual" in tooltips and advisor.
- **5-night minimum** before any score is shown. Below threshold → "calibrating" state displayed as `···` with a grey ring.
- **Baseline = median** of last 14 valid nights (ring-sourced, RHR > 0). Median is robust against outlier nights.
- **Recent = mean of last 3 nights** (3-day rolling window).
- **No HRV** — the Lumie X6B ring has no RMSSD command. `sleepQualityScore` is used as an HRV proxy for stress estimation.
- **Fatigue scoring** (0–6 points):
  - RHR delta > 5 bpm → +2; > 2 bpm → +1
  - Quality ratio < 75% of baseline → +2; < 90% → +1
  - Sleep < 6h → +2; < 7h → +1
  - 0–1 = Low, 2–3 = Moderate, 4+ = Elevated
- **Stress scoring** (signed integer):
  - RHR delta > 5 → +2; > 2 → +1; < −3 → −1
  - Quality drop > 25% → +2; > 10% → +1; improved > 15% → −1
  - ≤ −1 = Lower, 0–1 = Typical, 2+ = Higher
- Star ring `progress` for label-based cards is set to a fixed value per level (not score/100) so the visual still conveys severity.
- `WellnessProvider.load()` is called from `DashboardScreen.initState` post-frame callback, same pattern as `TasksProvider.loadTasks()`.

## New Files

### Frontend
- `lib/shared/models/wellness_models.dart` — `FatigueLevel`, `FatigueState`, `StressLevel`, `StressState`, `WellnessState`
- `lib/core/services/wellness_service.dart` — `WellnessService.compute(List<SleepSession>)` pure calculation
- `lib/features/wellness/providers/wellness_provider.dart` — `WellnessProvider` (ChangeNotifier), calls `SleepService.getSleepHistory` for last 14 days

## Modified Files

### Frontend
- `lib/main.dart` — added `WellnessProvider` to `MultiProvider`
- `lib/features/dashboard/screens/dashboard_screen.dart`:
  - `_buildScoreRow()` wrapped in `Consumer<WellnessProvider>`
  - Fatigue and Stress `_ScoreData` now take `centerLabel` + `progress` + `color` from wellness state
  - `_ScoreData` + `_buildScoreCard` updated to render text label when `centerLabel` is set
  - `AdaptiveGoalCard` factors: hardcoded `'No fatigue reported'` → dynamic fatigue label
  - Triggers `WellnessProvider.load()` in `initState`
- `lib/features/advisor/screens/advisor_screen.dart` — Today check-in "Fatigue" metric replaced with `wellness.fatigue.fullLabel`

## API Endpoints Used

- `GET /api/v1/sleep/history?start=&end=` — existing endpoint, fetches up to 14 nights

## New DB Collections / Indexes

None — uses existing `sleep_sessions` collection.

## Testing Checklist

- [ ] With 0–4 nights of sleep data: Fatigue and Stress show `···` (calibrating) in grey
- [ ] With 5+ nights, ring-sourced, good RHR: Fatigue shows "Low" in green
- [ ] With 5+ nights, RHR elevated +6 bpm and quality drops: Fatigue shows "High" in red
- [ ] Stress card shows "Norm" under typical conditions
- [ ] Dashboard `AdaptiveGoalCard` factors reflect real fatigue label
- [ ] Advisor check-in "Today → Fatigue" row shows real label (not "72 / 100")
- [ ] No crash when `getSleepHistory` throws (error is caught, state unchanged)

## Future Work / Deferred

- Passive 60 s HR collection timer in `RingProvider` (needed for richer stress signal once ring protocol supports it)
- Daytime light-activity HR delta as additional stress input
- Surface calibration progress ("3 of 5 nights recorded") on dashboard or sleep screen
- `clearOnLogout()` should be wired to auth logout flow
