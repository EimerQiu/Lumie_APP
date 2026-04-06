# Front-View Exercise Detection Improvements

**Date:** 2026-04-05  
**File:** `lumie_activity_app/lib/features/activity/screens/workout_session_screen.dart`

## Summary
Improved front-view detection for Squat, Push-Up, and Lunge exercises. The main improvements include:
1. **Fixed baseline sampling bug for push-up** — push-up front-view detection was failing to capture baseline in plank position because knees were required but may have low confidence in that position
2. **Added two-tier baseline sampling** — shoulder+hip baseline (needed for push-up) separate from full shoulder+hip+knee baseline (needed for squat/lunge)
3. **Added supporting signals** — knee angle (squat/lunge) and elbow angle (push-up) as optional supporting signals to enhance form feedback
4. **Added shoulder compression tracking** — tracks shoulder width changes for push-up feedback

## Decisions Made

### Two-Tier Baseline System
Rather than a single all-or-nothing baseline flag, implemented:
- `_frontBaselineCaptured` = true when shoulder+hip baseline captured (minimum for push-up)
- `_frontFullBaselineCaptured` = true when shoulder+hip+knee baseline captured (required for squat/lunge)

This allows push-up to work even when knees aren't visible in plank position, while maintaining strict requirements for squat/lunge which rely on knee data.

### Separate Sample Counters
- `_baselineSampleCount` — incremented only when all 6 landmarks (shoulder, hip, knee) are available
- `_baselineShoulderHipSampleCount` — incremented whenever shoulder+hip are available, regardless of knees
- This enables graceful degradation: push-up can work with partial baseline, while squat/lunge wait for full data

### Supporting Signals (Non-Required)
All supporting signals are optional and used for feedback only, not rep counting:
- **Squat:** Knee angle (≤100°) reinforces depth when Y-drop signals are partial
- **Push-Up:** Elbow angle (≤90°) and shoulder compression (≥3%) support depth assessment
- **Lunge:** Knee angle (≤100° on either leg) reinforces depth confirmation

## New Code

### State Variables Added
```dart
double _baselineShoulderSepAcc = 0;      // shoulder separation accumulator
double _baselineShoulderSep = 0;          // finalized baseline shoulder width
int _baselineShoulderHipSampleCount = 0;  // samples with shoulder+hip only
bool _frontFullBaselineCaptured = false;  // knee baseline captured
```

### Updated Methods

#### `_sampleFrontBaseline(Pose pose, PoseType type)`
- **Before:** Required all 6 landmarks (shoulder, hip, knee × 2)
- **After:** Two-tier sampling
  - Always samples shoulder+hip when available (increments `_baselineShoulderHipSampleCount`)
  - Also samples knees if available (increments `_baselineSampleCount`)
  - Captures shoulder separation for all exercises

#### `_finalizeFrontBaseline()`
- **Before:** Single finalization using full sample count
- **After:** Two independent finalization paths
  - If `_baselineShoulderHipSampleCount > 0`: finalize shoulder+hip baseline
  - If `_baselineSampleCount > 0`: finalize full baseline + knee data

#### Exercise Front-View Methods
- **Squat:** Changed to check `_frontFullBaselineCaptured`, added knee angle supporting signal
- **Push-Up:** Kept checking `_frontBaselineCaptured` (works with shoulder+hip only), added elbow angle and shoulder compression supporting signals
- **Lunge:** Changed to check `_frontFullBaselineCaptured`, added knee angle supporting signal

## Rep Counting Conditions (Unchanged)
All rep count conditions remain as specified:

**Squat Front:**
1. Shoulder Y drop ≥ 15%
2. Hip Y drop ≥ 10%
3. Knee separation increase ≥ 5%
4. Return to within 5% of standing Y
5. Minimum 1000ms elapsed

**Push-Up Front:**
1. Shoulder Y drop ≥ 10%
2. Return to within 5% of up-position Y
3. Nose/shoulder/hip alignment within 10% horizontal drift
4. Minimum 1000ms elapsed

**Lunge Front:**
1. Hip Y drop ≥ 12%
2. Knee Y drop ≥ 10%
3. Return to within 5% of standing Y (hip + both knees)
4. Minimum 1000ms elapsed

## Testing Checklist
- [x] No compile errors
- [x] Flutter analyze passes
- [ ] Push-up front view: calibration completes in plank position with knees low-confidence
- [ ] Squat front view: requires full baseline (knee data) before rep counting
- [ ] Lunge front view: requires full baseline (knee data) before rep counting
- [ ] Side-view exercises: no behavior change (angle-based detection unchanged)
- [ ] Frame re-entry: baseline resets and re-captures
- [ ] Set transitions: baseline resets between sets

## Implementation Notes
1. The push-up calibration message "Get in plank position to calibrate" now succeeds even when knees aren't visible, since only shoulder+hip data is required
2. Supporting signals enhance feedback without changing rep counts — they provide coaching hints and reinforcement but don't prevent reps from being counted
3. The two-tier system is backward compatible: any code checking `_frontBaselineCaptured` still works for push-up; code checking `_frontFullBaselineCaptured` correctly requires full data for squat/lunge
4. The `shoulderCompressing` signal is calculated but not currently used in feedback — it's available for future enhancement to show "shoulders collapsing" feedback

## Future Work
- [ ] Implement shoulder compression feedback messaging for push-up ("Don't let your shoulders collapse")
- [ ] Add visual debugging overlay showing which baseline signals are being tracked
- [ ] Integrate elbow angle feedback more prominently in push-up ("elbows tracking correctly")
