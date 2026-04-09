# Workout Plan Builder & Active Session Logging System

**Date:** 2026-04-09
**Feature:** Custom workout plan builder, exercise library, active session logging, free weight pose detection

## Decisions Made

- **Kept legacy `WorkoutPlan`/`Exercise` classes** for backward compat with the existing `WorkoutSessionScreen`. The old screen continues to work for the free "Full Body Starter" plan.
- **New templates use a block-based structure** (`WorkoutTemplate` → `WorkoutBlock` → `TemplateExercise`) to support named sections, supersets, and circuits.
- **Set type grouping** uses a `group_id` field — exercises sharing the same group_id form a superset (2 exercises) or circuit (3+). Visually indicated with a colored vertical bar.
- **Camera routing by equipment type**: bodyweight/dumbbell/barbell → camera + pose detection, machine → manual logging only. Users can skip detection at any time.
- **PR detection happens server-side** when saving a session — the backend compares against the `personal_records` collection and returns new PRs in the response.
- **Seed exercises** are upserted on startup via `exercise_id` slugs (e.g., `bw_squat`, `db_bicep_curl`) to survive re-seeding without duplicates.
- **ICD-10 filtering** uses a prefix-matching approach in `seed_exercises.py` — exercise IDs flagged per ICD-10 prefix (e.g., `I42` → high-intensity exercises get caution flag).

## New Files Created

### Backend
| File | Purpose |
|------|---------|
| `lumie_backend/app/models/workout.py` | All Pydantic models: ExerciseDefinition, WorkoutTemplate, WorkoutSession, PersonalRecord, etc. |
| `lumie_backend/app/services/workout_service.py` | CRUD + business logic: exercises, templates, sessions, PR detection, overload advice |
| `lumie_backend/app/api/workout_routes.py` | API endpoints for the workout system |
| `lumie_backend/app/data/__init__.py` | Package init |
| `lumie_backend/app/data/seed_exercises.py` | 40+ system exercises + ICD-10 caution mappings |

### Frontend — Models & Services
| File | Purpose |
|------|---------|
| `lib/core/services/workout_service.dart` | HTTP client for all workout API endpoints |

### Frontend — Providers
| File | Purpose |
|------|---------|
| `lib/features/workout/providers/exercise_library_provider.dart` | Exercise list state + filtering |
| `lib/features/workout/providers/workout_template_provider.dart` | Template CRUD + split grouping |
| `lib/features/workout/providers/active_session_provider.dart` | Active session state machine, timers, set completion |

### Frontend — Screens
| File | Purpose |
|------|---------|
| `lib/features/workout/screens/exercise_library_screen.dart` | Searchable exercise library with muscle/equipment filters |
| `lib/features/workout/screens/split_builder_screen.dart` | Split type picker (Full Body, Upper/Lower, PPL, etc.) |
| `lib/features/workout/screens/template_builder_screen.dart` | Workout template editor with blocks, drag-reorder, set types |
| `lib/features/workout/screens/active_workout_screen.dart` | Active session: routes to camera or manual view per exercise |
| `lib/features/workout/screens/post_workout_summary_screen.dart` | Post-workout stats, PRs, body map, editable sets |

### Frontend — Widgets
| File | Purpose |
|------|---------|
| `lib/features/workout/widgets/session_header.dart` | Top bar: workout name, block name, duration + rest timers |
| `lib/features/workout/widgets/rest_timer_widget.dart` | Full-screen rest countdown with +/-10s and skip |
| `lib/features/workout/widgets/camera_exercise_view.dart` | Camera-based exercise view with rep counter + orientation banner |
| `lib/features/workout/widgets/manual_exercise_view.dart` | Machine/manual logging: weight, reps, notes, complete button |
| `lib/features/workout/widgets/body_map_widget.dart` | Front/back body silhouette with muscle group highlighting |
| `lib/features/workout/widgets/create_exercise_sheet.dart` | Bottom sheet for custom exercise creation (Pro only) |

### Frontend — Data
| File | Purpose |
|------|---------|
| `lib/features/workout/data/exercise_keyframes.dart` | Stick figure keyframes for all exercises including 8 free weight demos |

## Modified Files

| File | Changes |
|------|---------|
| `lumie_backend/app/main.py` | Registered workout router, added seed calls on startup |
| `lumie_backend/app/core/database.py` | Added indexes for exercises, workout_templates, workout_sessions, personal_records |
| `lumie_activity_app/lib/shared/models/workout_plan_models.dart` | Major rewrite: added all new model classes, expanded PoseType enum, kept legacy classes |
| `lumie_activity_app/lib/core/constants/api_constants.dart` | Added workout endpoint constants |
| `lumie_activity_app/lib/main.dart` | Registered 3 new providers, added routes, token passing |
| `lumie_activity_app/lib/features/activity/widgets/activity_picker_sheet.dart` | Rewrote to use API-fetched templates, wire "New Workout" to SplitBuilderScreen |
| `lumie_activity_app/lib/features/activity/screens/workout_session_screen.dart` | Added thresholds, landmarks, angle calculations for 8 new free weight exercises |

## API Endpoints Added

| Method | Path | Description |
|--------|------|-------------|
| GET | `/exercises` | List exercises (filterable by muscle_group, equipment_type, search) |
| GET | `/exercises/{id}` | Get single exercise |
| POST | `/exercises` | Create custom exercise (Pro only) |
| PUT | `/exercises/{id}` | Update custom exercise |
| DELETE | `/exercises/{id}` | Soft-delete custom exercise |
| GET | `/exercises/{id}/history` | Get logged sets for an exercise across sessions |
| GET | `/workout-templates` | List user's templates + system defaults |
| GET | `/workout-templates/{id}` | Get single template |
| POST | `/workout-templates` | Create template (Pro only) |
| PUT | `/workout-templates/{id}` | Update template |
| DELETE | `/workout-templates/{id}` | Soft-delete template |
| POST | `/workout-templates/{id}/duplicate` | Duplicate template (Pro only) |
| GET | `/workout-templates/{id}/overload-advice` | Progressive overload suggestions |
| POST | `/workout-sessions` | Save completed session |
| GET | `/workout-sessions` | List sessions (paginated) |
| GET | `/workout-sessions/{id}` | Get session detail |
| PUT | `/workout-sessions/{id}` | Edit session (post-workout corrections) |
| GET | `/personal-records` | List all PRs |
| GET | `/personal-records/{exercise_id}` | PRs for specific exercise |

## New DB Collections / Indexes

| Collection | Key Indexes |
|------------|-------------|
| `exercises` | `exercise_id` (unique), `(is_system, is_active)`, `(created_by, is_active)` |
| `workout_templates` | `template_id` (unique), `(user_id, is_active)`, `is_system_default` |
| `workout_sessions` | `session_id` (unique), `(user_id, started_at desc)`, `(user_id, template_id)` |
| `personal_records` | `pr_id` (unique), `(user_id, exercise_id, pr_type)` (unique compound) |

## Free Weight Pose Detection

| Exercise | Angle Measurement | View | Down/Up Thresholds |
|----------|-------------------|------|--------------------|
| Bicep Curl | shoulder→elbow→wrist | side | 50° / 150° |
| Shoulder Press | shoulder→elbow→wrist | front | 90° / 160° |
| Lateral Raise | hip→shoulder→wrist | front | 100° / 155° |
| Romanian Deadlift | shoulder→hip→knee | side | 70° / 160° |
| Back Squat | hip→knee→ankle | side | 100° / 155° |
| Bench Press | shoulder→elbow→wrist | side | 90° / 155° |
| Deadlift | shoulder→hip→knee | side | 80° / 160° |
| Barbell Row | shoulder→elbow→wrist | side | 90° / 155° |

## Testing Checklist

- [ ] Exercise library loads and displays system exercises
- [ ] Search and filter by muscle group / equipment work
- [ ] Custom exercise creation works (Pro only, 403 for free)
- [ ] Split builder creates templates for each day type
- [ ] Template builder: add exercises, reorder, set defaults, group supersets
- [ ] Active session: camera exercises show rep counter + orientation banner
- [ ] Active session: machine exercises show manual logging UI
- [ ] Active session: skip detection switches to manual mode
- [ ] Rest timer works with +/-10s and skip
- [ ] Superset flow alternates exercises without rest
- [ ] Post-workout summary shows stats, body map, editable sets
- [ ] Session saves to backend with computed totals and PR detection
- [ ] Free user sees only "Full Body Starter", locked "Create" button
- [ ] Pro user sees all templates and can create new ones
- [ ] Overload advice returns suggestions after 3+ sessions
- [ ] ICD-10 caution flags display on exercises
- [ ] All 8 new free weight exercises detect reps via angle thresholds

## Fixes Applied (Follow-up Pass)

- **Backend filter bug**: `list_exercises` had a `$or` conflict when `muscle_group` filter was combined with user ownership filter. Fixed by restructuring query to use `$and` with separate `$or` for ownership and field-level filters.
- **Template builder reorder**: `_onReorder` was a no-op. Implemented proper drag-to-reorder that moves exercises within and across blocks with order renumbering.
- **Movement type filter**: Added `movementTypeFilter` to `ExerciseLibraryProvider` and a third filter chip (Push/Pull/Hinge/Squat/Carry/Isolation/Compound) to the exercise library screen.
- **Exercise detail sheet**: Added `_ExerciseDetailSheet` bottom sheet that shows full exercise info (muscles, form description, movement type, ICD-10 caution) when tapping an exercise in browse mode.
- **Split builder preview**: Added a preview section showing the exact day names that will be created before the user taps "Create Split".
- **Template deletion**: Added "Delete Template" menu in template builder app bar with confirmation dialog. Also added confirmation when deleting a block that has exercises.
- **Split day labels in picker**: Template cards now show `splitDayLabel` when different from the template name.
- **Long-press to edit**: Long-pressing a non-system template card in the activity picker navigates to the template builder.

## Active Session & Summary Fixes (Second Pass)

- **Superset/circuit set tracking rewrite**: Replaced single `_currentSetIndex` with per-exercise `_setsCompletedPerExercise` list. Each exercise in a group independently tracks its own completed set count, fixing the state corruption bug where Ex2 would inherit Ex1's set index.
- **Superset flow**: After completing all exercises in one round of a superset, the provider checks if more rounds remain and routes back to the group start with a rest period. When all rounds are done, it advances past the entire group.
- **Rest timer progress**: Changed from hardcoded `120.0` denominator to `totalRestDuration` parameter passed from the provider's `currentRestDuration`, so the circular progress indicator correctly scales for any rest duration.
- **Camera pose detection**: Rewrote `CameraExerciseView` with real ML Kit integration — front camera stream, `PoseDetector`, `_processFrame` pipeline, angle-based rep counting for all PoseTypes (squat, curl, shoulder press, lateral raise, RDL, back squat, bench press, deadlift, barbell row), and real-time form feedback.
- **Weight pre-fill from history**: `startSession` now calls `_prefillWeightsFromHistory()` which fetches the last-session weight for each exercise via `getExerciseHistory` API and updates `CompletedSet.actualWeight` before the user starts. Falls back to template defaults.
- **PR detection display**: After `saveSession()`, backend-detected PRs are synced back to `CompletedSet.isPr` and displayed as golden PR badges in the exercise breakdown. A celebration banner with trophy icons shows all PRs achieved.
- **Overload advice UI**: After save, the provider loads overload suggestions via `getOverloadAdvice` API. Summary screen shows suggestion cards with current→suggested values and reasoning.
- **Session notes**: Added notes text field to summary screen, wired to `ActiveSessionProvider.sessionNotes`, included in session save payload.
- **Edit dialog improvements**: Set edit dialog now includes status selector (Completed/Failed/PR chips), not just weight/reps.
- **Finish early**: Added `finishEarly()` method that marks remaining sets as skipped before transitioning to summary. Discard now requires double-confirmation.

## Stick Figure Demo System (Third Pass)

### New Files
| File | Purpose |
|------|---------|
| `lib/features/workout/widgets/stick_figure_painter.dart` | CustomPainter drawing joints (yellow circles), bones (white lines), dumbbell rectangles at wrists, barbell bar+plates across wrists. Front-view and side-view bone connections auto-detected from pose key names. |
| `lib/features/workout/widgets/stick_figure_demo.dart` | `FullScreenDemoWidget` (3-loop pre-set animation with exercise name, loop counter "Demo 1/3", muscle highlights, form cue, skip button, swipeable primary/secondary view tabs), `MiniPipDemo` (88x118 PiP in top-right corner during active set, tap to expand overlay), `MachineDemo` (empty stub widget) |
| `lib/features/workout/widgets/muscle_highlight_widget.dart` | Color-coded muscle group labels: primary in bright yellow, secondary in lighter shade. Compact mode for PiP overlay. Shows "Primary: Biceps", "Secondary: Forearms" format. |

### CameraExerciseView Integration
- Added `_showingDemo` state: starts true when exercise has a demo, set to false after 3-loop completion or "Skip Demo" tap
- Camera initialization deferred until demo completes (saves battery/resources during demo phase)
- Demo resets on set change or exercise change (`didUpdateWidget`)
- `MiniPipDemo` overlay rendered in Stack during active set, positioned top-right, doesn't overlap rep counter or set info
- Multi-angle swipe: horizontal drag on full-screen demo swaps between primary/secondary view tabs

### Equipment Props
- **Dumbbell**: Small filled rectangles drawn at each wrist landmark (front view: both lWrist/rWrist, side view: single wrist)
- **Barbell**: Horizontal bar connecting both wrist landmarks with plate rectangles extending beyond each end (front view), or centered bar with plates (side view)
- **Bodyweight**: No props drawn (existing squat/push-up/lunge demos)

## Future Work / What's Deferred

- **Form feedback for free weight exercises**: Per-exercise form checks (e.g., "Keep your elbow still" for curls). Currently all new exercises use the generic angle-threshold rep detection without exercise-specific form cues.
- **Advisor integration**: The overload advice endpoint exists but the Advisor chat doesn't yet proactively suggest it after 3+ sessions.
- **Secondary view keyframes**: The `ExerciseDemo` model supports `secondaryView` and the UI has swipe tabs, but the secondary-view keyframes currently mirror the primary. To fully support multi-angle, each exercise would need a second set of keyframes from the alternate perspective.
