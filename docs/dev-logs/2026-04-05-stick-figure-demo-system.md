# Stick-Figure Demo Animation System

**Date:** 2026-04-05  
**File:** `lumie_activity_app/lib/features/activity/screens/workout_session_screen.dart`

## Summary
Added an animated stick-figure demonstration system that plays the correct movement before each set and continues as a mini picture-in-picture window during the set.

## Session Flow Change
```
Before: preview → activeSet → rest → activeSet → ...
After:  preview → demo (3 loops) → activeSet (PiP) → rest → demo (3 loops) → activeSet → ...
```

## Decisions Made

### Single-file approach
All new code is in `workout_session_screen.dart`, consistent with existing architecture. No new files.

### `AnimationController` + `TickerProviderStateMixin`
Added `with TickerProviderStateMixin` to `_WorkoutSessionScreenState`. One `AnimationController` (`_demoController`, 2800 ms/loop) drives both the full-screen demo and the PiP. It:
- Runs `forward(from: 0.0)` for each demo loop (counts 1/3, 2/3, 3/3)
- Switches to `repeat()` when transitioning to `activeSet` (PiP infinite loop)
- Stops/restarts via `forward(from: 0.0)` at each rest→demo transition

### Two loop counters
- `_demoLoopCount` — written via `setState`, drives the "Demo N/3" counter display
- `_pipLoopCount` — incremented WITHOUT `setState` (no rebuild needed), only used for lunge leg alternation in `_getDemoPose`

This avoids unnecessary full-tree rebuilds on every PiP loop completion.

### `AnimatedBuilder` (not `setState`) for animation
`_buildDemo` and the PiP widget use `AnimatedBuilder`, which rebuilds only their own subtree on each vsync tick. `_StickFigurePainter.shouldRepaint` returns `true` unconditionally since the map identity changes every frame.

### Camera skip during demo
`_onCameraFrame` returns early when `_state == demo`. This prevents ML Kit pose detection from running during the 8.4 s demo phase (3 × 2800 ms), saving significant CPU/battery.

### Push-up uses side view
Regardless of the user's detected orientation, push-up demo is always rendered in side view (`_StickFigureView.side`) — clearer for the chest-lower movement.

### Lunge leg alternation
Each demo loop alternates between left lunge and right lunge:
- `loopIdx.isEven` → left foot forward (`_lungeLeftBottom`)
- `loopIdx.isOdd` → right foot forward (`_lungeRightBottom`)
Works in both full-screen demo (`_demoLoopCount`) and PiP (`_pipLoopCount`).

## New Code

### Types
```dart
typedef _PoseMap = Map<String, Offset>;
enum _StickFigureView { front, side }
enum _SessionState { preview, demo, activeSet, rest, complete }  // demo added
```

### State Variables
```dart
late final AnimationController _demoController;
int _demoLoopCount = 0;
int _pipLoopCount = 0;
bool _demoPipExpanded = false;
```

### Keyframe Constants (static, in state class)
- `_squatStand`, `_squatBottom` — 14 joints each (front view)
- `_pushUpTop`, `_pushUpBottom` — 8 joints each (side view)
- `_lungeLeftBottom`, `_lungeRightBottom` — 14 joints each (front view)
- Lunge standing reuses `_squatStand`

### New Methods
| Method | Description |
|--------|-------------|
| `_onDemoAnimationStatus` | AnimationController status listener: advances loop count, transitions to activeSet after 3 loops, keeps PiP looping |
| `_skipDemo` | Stops demo, enters activeSet immediately with PiP running |
| `_getDemoPose(t, loopIdx)` | Converts controller value → interpolated `_PoseMap` with easeInOut |
| `_lerpPose(a, b, t)` | Pure linear interpolation between two pose maps |
| `_beginnerCue(PoseType)` | Returns exercise-specific coaching cue string |
| `_buildDemo()` | Full-screen dark demo view (stick figure + counter + cue + skip button) |

### PiP in `_buildActiveSet`
New `AnimatedBuilder` as last Stack child:
- Compact: 88×118 px, `top:80 right:16` (below exercise info bar)
- Expanded: full-screen semi-transparent overlay (tap to collapse)
- Tap toggles `_demoPipExpanded` via `setState`

### `_StickFigurePainter`
```dart
class _StickFigurePainter extends CustomPainter {
  final _PoseMap pose;
  final _StickFigureView view;
  // front: 15 bone connections; side: 7 bone connections
  // white bones, yellow (#FFD700) joint circles, white hollow head ring
}
```

## Modified Files
- `lumie_activity_app/lib/features/activity/screens/workout_session_screen.dart`

## Testing Checklist
- [ ] Preview "Start" → dark demo screen appears, "Demo 1/3" shown
- [ ] Stick figure animates through the movement (easeInOut, ~2.8 s/loop)
- [ ] Counter advances: 1/3 → 2/3 → 3/3 → auto-transitions to camera
- [ ] "Skip Demo" immediately shows camera with PiP in top-right
- [ ] PiP loops indefinitely during the set
- [ ] Tap PiP → expands to full-screen overlay; tap again → collapses
- [ ] PiP doesn't overlap rep counter or exercise info bar
- [ ] After set complete → rest → next set → full demo plays again (counter resets to 1/3)
- [ ] Push-up shows side-view figure (person lying horizontal)
- [ ] Lunge alternates left/right per loop (even=left, odd=right)
- [ ] Battery: camera pose detection paused during demo (verify via profiler)
- [ ] Dispose: no `_demoController` leaks on pop

## Future Work
- [ ] Add foot marker (small ground line) under ankles for spatial reference
- [ ] Subtle pulse/glow on joints at the bottom of each rep for emphasis
- [ ] User preference to permanently hide demo (stored in SharedPreferences)
- [ ] Wider variety of exercises beyond the three beginner keyframes
