# Activity History Refinements + Dynamic Sky Background on Today

**Date:** 2026-04-29

---

## Decisions Made

### Activity History — never abbreviate step counts
Previously `_fmtSteps` returned `"9.0k"` for any value ≥ 1,000. Users couldn't see the exact count and screenshots looked imprecise. Replaced with a thousands-separator formatter (`"9,043"`). The unit ("steps") is rendered as a separate label, so the format string is purely numeric. This is a screen-wide rule per the spec — every number on the Activity History screen now shows the exact value.

### Activity History — pair active time with its goal inline
Before: the card showed `"81 min"` as the primary number and `"Goal: 45 min"` as a smaller line on the right column. The pairing was unclear and once "Goal Met!" was awarded the user lost track of the actual target.

After: active time is always rendered as `"81 min / 45 min goal"` — the goal travels with the metric so the target stays visible even after it's met. The "Goal Met!" badge is preserved next to the date.

The card now uses two helper widgets, `_PrimaryMetric` and `_SecondaryMetric`. Behaviour:
- When **steps** is the goal type: primary tile shows `9,043 steps` + `Goal: 8,000 steps`, secondary tile shows `81 min` + `/ 45 min goal`.
- When **active time** is the goal type: primary tile shows `81 min / 45 min goal`, secondary tile shows `9,043 steps`.

### Today page — dynamic sky background driven by wellness scores
The lemon-bokeh image background was static and ignored how the user was actually doing. Replaced with a `SkyBackground` widget that computes a `SkyMood` from today's signals and renders a matching animated gradient + celestial elements. The full mood matrix (per spec):

| Signal pattern                                   | Mood            | Visual                                          |
|--------------------------------------------------|-----------------|-------------------------------------------------|
| `now.hour >= 22 \|\| now.hour < 5`               | `starryNight`   | Navy gradient, twinkling stars, crescent moon, faint Milky Way |
| Sleep ≥ 85, Activity ≥ 85, Stress ≥ 80           | `aurora`        | Deep navy + 3 drifting aurora bands + stars     |
| Stress < 40                                      | `stormy`        | Dark gradient, dense dark clouds, occasional lightning bolt |
| Activity ≥ 70, Sleep < 50                        | `warmTwilight`  | Violet→pink→orange→amber vertical gradient + dusk sun |
| Activity < 30 (non-rest-day)                     | `overcast`      | Slate gradient, dense grey clouds               |
| Sleep ≥ 70, Activity ≥ 70, Stress ≥ 60 (or none) | `brightSky`     | Blue gradient, golden sun + soft white clouds   |
| Otherwise                                         | `pastelSunrise` | Pink→cream→sky pastel gradient + soft sun + light clouds |

Late-night always wins — even on a perfect day, after 10 PM the screen reads as `starryNight`. Stress is the only "negative" override during daytime hours.

Stress score in the project follows the existing convention (higher = more restored); the classifier inverts it when checking for "high stress" (`stressScore < 40`).

### Today page — glassmorphism on every card
With a dynamic sky behind the cards, opaque white cards would block what makes the background interesting. Every card on the Today page is now glassmorphic: backdrop-blurred + faint white tint (≈22% alpha) + 1px white border at 45% alpha. Implemented as a `glass: true` flag on the existing `GradientCard` so each call site flips one parameter; no parallel widget hierarchy.

The Heart Rate and Stress cards, which previously rendered as raw `Container`s with `backgroundWhite.withValues(alpha: 0.70)`, were converted to `GradientCard(glass: true)` so they share the same blur/border treatment as everything else. Recent Activity items inside the parent glass card use semi-transparent white (`alpha: 0.35`) so they read as nested cards without breaking the sky's visibility.

### Background animation — `CustomPainter` over Lottie
The spec allowed Lottie OR animated shader gradients. We don't ship Lottie assets, and shipping new ones for 7 moods would be heavy. A single `CustomPainter` driven by an `AnimationController` (60 s loop) renders all moods cheaply: clouds drift, stars twinkle on individual sine phases, aurora bands shimmer, lightning fires on a randomised 4–12 s schedule. Mood transitions crossfade through `AnimatedSwitcher` (~900 ms) so changes between refreshes don't pop.

---

## New Files Created

### Frontend
- `lumie_activity_app/lib/features/dashboard/widgets/sky_background.dart` —
  `SkyMood` enum (with `fromScores` classifier) + `SkyBackground` widget +
  internal `_SkyPainter` for clouds, sun, moon, stars, Milky Way, aurora bands,
  and lightning.

### Backend
_(none — frontend-only change)_

---

## Modified Files

### Frontend
- `lumie_activity_app/lib/features/activity/screens/activity_history_screen.dart`
  — `_fmtSteps` switched to thousands-separator format; selected day summary
  card replaced with `_PrimaryMetric` / `_SecondaryMetric` helpers that pair
  active time with its goal.
- `lumie_activity_app/lib/features/dashboard/screens/dashboard_screen.dart` —
  bokeh background swapped for `SkyBackground` driven by a `Consumer4` of
  sleep/stress/goal/steps providers; every dashboard card now passes
  `glass: true`. HR and Stress cards rewritten to use `GradientCard` instead of
  raw `Container`. Recent Activity tile background switched to translucent
  white.
- `lumie_activity_app/lib/shared/widgets/gradient_card.dart` — added optional
  `glass` flag. When set, the gradient is dropped and the card renders as a
  backdrop-blurred frosted-glass surface.
- `lumie_activity_app/lib/features/dashboard/widgets/active_tasks_card.dart`,
  `activity_summary_card.dart`, `adaptive_goal_card.dart` — `gradient` +
  `opacity` removed, `glass: true` set instead.

### Backend
_(none)_

---

## API Endpoints Added
_(none — UI/visual only)_

## New DB Collections / Indexes
_(none)_

---

## Testing Checklist

- [ ] Activity History — step values across the entire screen render with
  commas and never with a `k` suffix (verify: 999, 1,000, 9,043, 12,500, 100,000).
- [ ] Activity History — when Goal Type = active time, the primary number reads
  `"X min / Y min goal"`. The "Goal Met!" badge still appears once X ≥ Y.
- [ ] Activity History — when Goal Type = steps, the secondary tile reads
  `"X min" + "/ Y min goal"`. Step goal still shown under the primary tile.
- [ ] Today page — all cards (scores, Active Tasks, Today's Activity ring, HR,
  Stress, Activity Summary, Adaptive Goal, Recent Activities) are translucent
  with backdrop blur; the sky is visible through every one.
- [ ] Today page — manually set sleep + stress + activity to peak values and
  confirm `aurora` renders (3 drifting coloured bands).
- [ ] Today page — set the device clock past 22:00 → background flips to
  `starryNight` regardless of scores.
- [ ] Today page — set stress score < 40 → `stormy` background renders with
  clouds and intermittent lightning bolts.
- [ ] Today page — set activity < 30 (non-rest-day) → `overcast` grey clouds.
- [ ] Performance — sustained ~60 fps on a mid-tier device while the dashboard
  is open (the painter is cheap, but worth confirming on real hardware).

---

## Follow-up — Activity History redesign (same day)

Same screen, second pass after the first round of fixes — full Oura-style
contributor card layout requested. Net effect on the screen below the week
strip: **Today card → Meet Daily Goals → Training Frequency → Training
Volume → Recovery Time → Workouts**.

### Decisions

- **Single-column dual-stat Today card.** The previous primary/secondary tile
  layout exposed only one metric prominently. The redesign always shows both
  the active-time/goal pairing and the exact step count — `_MetricLine` rows
  driven off `selected.activeMinutes` and `selected.steps`. Avoids the
  cognitive cost of mapping the goal type to which tile to read.
- **Gold theme for the Today card.** Switched from `cardGradient` (white) to
  `warmGradient` (amber-100 → amber-200) so the day summary feels like the
  hero card. Inside text uses `textOnYellow` for legibility on the warm fill.
  All other contributor cards stay on white so the gold-on-white pattern keeps
  the Today card as the visual anchor.
- **Drop the teal "This Week" stats card.** Replaced entirely by four
  contributor cards. Net code: `_buildWeeklyOverview`, `_WeekStatItem`,
  `_PrimaryMetric`, `_SecondaryMetric` all deleted.
- **Day-level "session" approximation.** We don't yet pipe per-session
  intensity to this screen, so a "session" = a day with ≥30 active minutes
  (`_kSessionMinutesThreshold`). Best honest mapping from current ring data;
  documented in code so the threshold is easy to lift once HR-zone tagging
  lands. Weekly soft target: `_kWeeklyFrequencyTarget = 3`,
  `_kWeeklyVolumeTarget = 150` (WHO moderate-activity baseline).
- **Recovery framing.** Recovery days = explicit rest days (per
  `RestDaySettings.isRestDay`) **or** days with active minutes below the
  session threshold. The Recovery Time card only shows positive copy:
  "Plenty of recovery", "A solid balance", "Recovery is part of progress".
  Multiple rest days never produce a warning. The 7-day icon row uses a flame
  icon for active days and a leaf for recovery — both styled in the gold/mint
  palette so neither reads as a "miss".
- **Tone audit.** Replaced "Rest Day — light movement only. Your full data is
  shown below." with "Recovery day — your full data is shown below." to align
  with the "always frame recovery as positive" rule, and audited every new
  string to ensure none of "warning / inactive / sedentary / failed / missed /
  not enough" appears anywhere on the screen.

### Modified files

- `lumie_activity_app/lib/features/activity/screens/activity_history_screen.dart`
  — major rewrite below the week strip. Added `_restDays` state +
  `RestDaysService.getRestDays()` load. Today card gold-themed and
  restructured around `_MetricLine`. New widgets: `_ContributorCard`,
  `_MeetDailyGoalsCard`, `_TrainingFrequencyCard`, `_TrainingVolumeCard`,
  `_RecoveryTimeCard`, `_DayDotsRow`. Deleted: `_buildWeeklyOverview`,
  `_WeekStatItem`, `_PrimaryMetric`, `_SecondaryMetric`.

### Things to verify

- [ ] Today card renders with gold/amber background, dual `_MetricLine` rows,
  Goal Met! pill in the corner.
- [ ] When the active goal type is steps, the progress bar reflects step
  progress; when it's active time, it reflects minutes — verify both modes.
- [ ] On a recovery day, the Today card shows the recovery banner instead of
  the rest-day banner (copy: "Recovery day — your full data is shown below.")
- [ ] Meet Daily Goals shows the active-time / goal pairing **and** the
  secondary "X steps today" / "X min active today" line, switching with goal
  type.
- [ ] Training Frequency counts only days with ≥30 active min over the past 7
  days. Soft target 3 — past 3 it should *not* keep growing the bar (clamp).
- [ ] Training Volume — verify total minutes across the week matches the
  selector dots (sanity check). Past 1.5× the 150 min target the message
  should switch to "make time for recovery too" (gentle, not a warning).
- [ ] Recovery Time — confirm at least one explicit rest day (configure under
  Settings → Rest Day Schedule) shows up as a leaf icon in the 7-day row.
  Multiple rest days must keep producing positive copy.
- [ ] Floating "Record Workout" button still launches the activity picker.

## Follow-up — Photographic sky + independently floating cards (same day)

User feedback after the painted-sky / glass-card rollout: cards looked
*grouped together* (visually welded into one panel) and the painted sky
didn't have the realism the spec called for. Two structural changes:

### Decisions

- **Real photographs, not painted skies.** Replaced the `CustomPainter`-based
  sky with `Image.network` calls to fixed Unsplash CDN URLs — one per mood.
  The painter is gone entirely. Each mood maps to a hand-picked Unsplash
  photo ID; URLs are kept in a `Map<SkyMood, List<String>>` so swapping a
  photo (or rotating between several) is one-line. While the photo is
  downloading or if the network fails, a `_FallbackSky` gradient (roughly the
  photo's dominant tone) renders so the screen never goes blank.
  - We did **not** add `cached_network_image` — Flutter's built-in
    `Image.network` LRU cache is more than enough for 7 ~1 MB images.
  - HTTPS-only URLs, so no `NSAppTransportSecurity` exceptions are needed in
    `Info.plist`.
- **Warm gold tint overlay.** Layered on top of the photo via a `DecoratedBox`
  with a vertical `LinearGradient` (amber-400 @ 20% → amber-100 @ 10%). Low
  enough that the photo dominates, but enough to keep the screen on-brand.
- **Cards float independently.** The previous glass treatment used a near-
  uniform 22% white tint with very soft edges, which is what made the stack
  read as one shared panel. Strengthened all three cues:
  - **Shadow:** two-layer (tight 6 px contact + 28 px lift @ 10 px offset) so
    each card has clear elevation against the sky photo.
  - **Tint:** pale-gold gradient (40% white → 30% amber-100) — slightly
    warmer than pure white, breaks up the uniform stack, stays in the
    yellow theme.
  - **Border:** 50% amber-100 instead of white — the warm hairline reads as
    gold-on-sky and matches the activity ring.
  - **Gaps:** vertical card margin reduced from 8 → 6 each side to keep the
    SizedBox-driven 12 px spacing visible; the lift shadow now falls into
    the gap rather than getting clipped.
  - The `Today's Scores` card was unwrapped from its outer `Padding` so
    spacing between it and the next card matches the rest of the column
    (was inconsistent at 18 px vs. 24 px).
- **Ring interior transparent.** `ActivityRing` previously filled its centre
  with a translucent gold radial gradient — that fill blocked the sky. The
  outer container is now a plain `SizedBox`; only the gradient arc + a 30%
  white track remain so the photo shows through the ring's centre and
  underneath the unfilled portion.

### Modified files

- `lumie_activity_app/lib/features/dashboard/widgets/sky_background.dart` —
  full rewrite. `Image.network` per mood + `_FallbackSky` gradient + warm
  tint. Painter / `AnimationController` / lightning ticker all removed.
- `lumie_activity_app/lib/shared/widgets/gradient_card.dart` — `_buildGlass`
  reworked: pale-gold gradient fill, amber-100 border, two-layer shadow,
  vertical margin 6.
- `lumie_activity_app/lib/shared/widgets/circular_progress_indicator.dart`
  — `ActivityRing` swapped its `Container` (with radial gold fill) for a
  plain `SizedBox`. Track is now translucent white instead of opaque
  `surfaceLight`.
- `lumie_activity_app/lib/features/dashboard/screens/dashboard_screen.dart`
  — dropped the manual `Padding(horizontal: 16)` around the Scores card so
  it uses the same default card margin as everything else; the score row
  card no longer carries a `margin: EdgeInsets.zero` override.

### Things to verify

- [ ] Each Today-page card visibly floats — the sky photo is clearly visible
  in the gap between every pair of cards.
- [ ] First load on a slow network: each card renders against the
  `_FallbackSky` gradient first, then the photo fades in — no blank screen
  or layout shift.
- [ ] All seven moods load a real photo (test with manual mood overrides if
  needed). If any URL 404s, swap it for another sky shot of the same mood.
- [ ] Activity ring centre shows the sky through it; the goal/value text
  stays readable against any of the seven photos (the warm tint helps here).
- [ ] No ATS errors in Xcode console — all sky URLs are HTTPS so this should
  Just Work, but worth confirming on a real device before TestFlight.

## Future Work / Deferred

- **Lottie polish.** The `CustomPainter` versions of clouds/aurora/etc. are
  intentionally simple. If we ever ship a higher-fidelity sky look, the right
  upgrade path is per-mood Lottie files — `SkyBackground` is structured so the
  rendering layer can be swapped without touching the mood classifier or its
  callers.
- **Per-quadrant scores in mood classification.** Today the classifier only
  reads sleep, activity, and stress. Once readiness/HRV scoring lands, the
  `aurora` branch in the spec ("perfect readiness + sleep + activity") should
  also gate on readiness, not just on a high stress score acting as a proxy.
- **Animated glass tint.** Right now the glass cards use a static white tint.
  We could subtly shift the tint per mood (warmer at sunrise, cooler at night)
  for extra polish. Skipped for now — the current treatment already keeps text
  legible against every mood.
