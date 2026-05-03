# Meal Feature — Slice 1 (Backend)

**Date:** 2026-05-03
**Author:** eimerqiu
**Scope:** Backend foundation (PRD §14). Frontend is deferred to Slices 2–4.

## Summary

Adds a first-class **Meal** entity that supersedes the text-only Nutrition Task
summary. Meals carry structured food items, categorical macro ratios
(low/moderate/high), a personal history endpoint, a team-scoped feed, and a
correction-learning capture path. Existing Nutrition Task flow is preserved;
completing a Nutrition Task now bridges to a Meal record in parallel
(PRD Phase-1 backward compatibility, §9).

## Decisions made

1. **Macro categorization is LLM-driven, not threshold-based.**
   Per `CLAUDE.md` "Use LLM API for Semantic Judgments, Not Enums". Calibration
   anchors live in `_MACRO_CALIBRATION` inside `meal_service.py` and are
   referenced by both vision-analysis and bridge prompts. No hardcoded gram
   thresholds in code.

2. **Two-step analyze → confirm flow.**
   `POST /meals/analyze` saves images and returns a draft (`meal_id`, images,
   food_items, macro_ratio) **without persisting a meal document**.
   `POST /meals` finalizes by re-scanning the on-disk directory under
   `uploads/meals/{meal_id}/` to attach images. Reasoning: the user must be able
   to edit foods before confirm; persisting a draft would leak a half-formed
   record into the personal history. Trade-off: orphaned images if the user
   abandons before confirming. A future cleanup job can sweep dirs older than 24h.

3. **Image storage = filesystem under `uploads/meals/{meal_id}/`.**
   Mirrors the existing task pattern (no S3 in this slice). Reuses the same
   `/api/v1/uploads/...` mount in `main.py`.

4. **Bridge from Nutrition Task uses text → structured (no second vision call).**
   When a Nutrition Task is completed, the existing text note is parsed by
   PaleBlueDot/Claude into a structured Meal. Image bytes are not duplicated;
   the meal copies attachment metadata referencing `tasks/{task_id}/...`. Saves
   a vision call per completion. Trade-off: deleting the source task leaves
   meal images as dangling URLs — acceptable for v1; revisit if it becomes a
   problem.

5. **Bridge is fire-and-forget in the route handler**, mirroring `log_task_completed`.
   Completion success is never blocked by bridge failures. Idempotent via
   `linked_task_id` lookup before insert.

6. **Visibility is per-meal, not per-team-member.**
   `visibility ∈ {private, team}` plus a single optional `team_id`. Switching
   to `private` auto-clears `team_id`. Switching to `team` requires active
   membership.

7. **Meal note has no character cap** (PRD §11 explicitly removes the 500-char
   limit from the task path). Validated via Pydantic — no `max_length`.

## New files (backend only)

- `lumie_backend/app/models/meal.py`
- `lumie_backend/app/services/meal_service.py`
- `lumie_backend/app/api/meal_routes.py`

## Modified files

- `lumie_backend/app/resources/schema/lumie_schema.json` — added `meals` and
  `meal_corrections` collections (authoritative source per CLAUDE.md).
- `lumie_backend/app/main.py` — registered `meal_router` under `/api/v1`.
- `lumie_backend/app/api/task_routes.py` — added
  `_bridge_nutrition_task_to_meal` fire-and-forget on Nutrition completion.

## API endpoints added

| Method | Path                                | Purpose |
|--------|-------------------------------------|---------|
| POST   | `/api/v1/meals/analyze`             | Multipart upload → structured analysis (saves images, no meal doc yet) |
| POST   | `/api/v1/meals`                     | Confirm a previously-analyzed meal |
| GET    | `/api/v1/meals/me`                  | Personal meal history (cursor-paginated) |
| GET    | `/api/v1/meals/feed?team_id=`       | Team-scoped meals feed |
| GET    | `/api/v1/meals/{meal_id}`           | Detail (owner or team member if team-visible) |
| PUT    | `/api/v1/meals/{meal_id}`           | Edit foods/macros/note/visibility |
| DELETE | `/api/v1/meals/{meal_id}`           | Delete meal + on-disk images |
| POST   | `/api/v1/meals/{meal_id}/correction`| Capture user correction for personal-bias learning |

All routes require Bearer JWT.

## New DB collections

- `meals` — see schema entry for full field list.
- `meal_corrections` — see schema entry. v1 surfaces these as few-shot hints in
  the analyze prompt (`_load_correction_hints`); v2 will switch to image
  embedding lookup.

**Indexes (recommended, not yet created):**
- `meals`: `{user_id: 1, created_at: -1}`, `{team_id: 1, visibility: 1, created_at: -1}`, `{linked_task_id: 1}` (for bridge idempotency).
- `meal_corrections`: `{user_id: 1, created_at: -1}`, `{meal_id: 1}`.

Add these once the feature has real traffic — production deployment script.

## Testing checklist

Manual end-to-end (run against staging after deploy):

- [ ] `POST /meals/analyze` with one JPEG → returns `meal_id`, images list, food_items, macro_ratio
- [ ] `POST /meals/analyze` with 5 JPEGs → all images saved under `uploads/meals/{meal_id}/`
- [ ] `POST /meals/analyze` with non-image upload → 400
- [ ] `POST /meals` after analyze → 201, meal appears in `GET /meals/me`
- [ ] `POST /meals` with `visibility=team` and a team the user belongs to → 201
- [ ] `POST /meals` with `visibility=team` and a team the user doesn't belong to → 403
- [ ] `POST /meals` without prior analyze (random meal_id) → 400 ("No images found")
- [ ] `PUT /meals/{id}` editing food_items → updated; `updated_at` advances
- [ ] `PUT /meals/{id}` switching visibility private↔team → team_id cleared/required correctly
- [ ] `GET /meals/{id}` as owner → 200; as non-member of private meal → 403; as team member of team meal → 200
- [ ] `DELETE /meals/{id}` → 200; on-disk dir under `uploads/meals/{id}/` removed
- [ ] `POST /meals/{id}/correction` → 201; subsequent `POST /meals/analyze` for same user surfaces hint in prompt (verify in logs)
- [ ] Complete a Nutrition Task with image attachments → meal appears in `GET /meals/me` with `linked_task_id` set
- [ ] Complete same Nutrition Task twice (e.g. retry) → still only one meal exists (idempotency)
- [ ] Macro ratio response **never** contains numeric grams or kcal (regression-test the AI output sanitization)

## Future work / what's deferred

**Slice 2 (Flutter foundation):** `MealService`, `MealProvider`, Dart models.

**Slice 3 (Flutter UX):** `MealLogScreen`, `MealDetailScreen`, macro ratio dot/bar widget.

**Slice 4 (Frontend nav + feed):**
- Add **"Meals" tab** to the **left-side menu bar** (deferred per user request — not in the bottom nav).
- Personal history grid + Log Meal CTA.
- Integrate into the existing team feed (`/teams/{id}/feed`) by emitting a
  `meal` feed item type, in addition to the dedicated `/meals/feed` endpoint
  added here.

**Slice 5 (learning v2):**
- Image embeddings (CLIP or similar) on meal images → similarity-based
  correction lookup, replacing the v1 last-N few-shot.
- Aggregate per-user correction frequency to spot persistent
  "predicted X → user has Y" patterns and seed them as durable bias.

**Phase 2 (PRD §9):** Deprecate Nutrition Task type once Meal is the default
entry point in the UI; redirect existing nutrition-task tap targets to the
Meal log flow.

**Indexes:** create the recommended indexes during the first production deploy
that takes meaningful meal traffic.

---

## Addendum (2026-05-03 PM): Auto-sync from Med-Reminder

### Behavior change

Original Slice 1 fired the Nutrition-task → Meal bridge **only on completion**.
Per user request, the bridge now fires on **every Med-Reminder lifecycle
event** so a meal task is reflected in the Meals feature without the user
entering anything twice:

| Sync point | Route |
|---|---|
| Task created | `POST /api/v1/tasks` |
| Task edited (note, type, team) | `PATCH /api/v1/tasks/{id}` |
| Attachments uploaded | `POST /api/v1/tasks/{id}/attachments` |
| Note edited | `PATCH /api/v1/tasks/{id}/note` |
| Task completed | `POST /api/v1/tasks/{id}/complete` |

All five fire `_bridge_nutrition_task_to_meal` as fire-and-forget; the helper
re-fetches the task and skips silently when `task_type != Nutrition`.

### Bridge is now idempotent upsert

`MealService.create_meal_from_nutrition_task` was rewritten as upsert:

- Look up existing meal by `linked_task_id`.
- **If `user_edited == True`**: return existing meal_id, do nothing.
- Else: refresh `food_items` / `macro_ratio` / `images` / `note` / `team_id`
  / `visibility` from the latest task state.
- LLM `text → structured` call is **skipped** when `bridge_note_hash` already
  matches the source note's hash (common case for attachments-only updates
  and team reassignments).
- Tasks with no note AND no attachments yet are not bridged (no empty stubs).

### User-edit lock

Two new meal fields:

- `user_edited: bool` — flips to `true` on `PUT /meals/{id}` or
  `POST /meals/{id}/correction`. One-way lock. Once set, the bridge never
  overwrites this meal again.
- `bridge_note_hash: str` — short sha256 of the source note at last bridge
  run, used to skip redundant LLM calls.

Schema entry updated to document both.

### What this protects against

| Scenario | Result |
|---|---|
| User adds note to task, later uploads attachments | Meal created on note add, images refreshed on attachment upload — same meal, no duplicates |
| User opens Meals, edits foods | `user_edited` flips; subsequent task edits do not overwrite |
| User changes task team | Meal's `team_id` / `visibility` update; Flutter `MealProvider._replaceLocal` evicts/inserts in cached team feeds correctly (fix from earlier this session) |
| Task type changes from Nutrition → other | Meal stays as-is (no auto-delete; user data is preserved) |
| Task deleted | Meal stays as-is (orphaned but accessible via `/meals/me`) |
| Same task completed twice | Idempotent — second call hits the existing meal |

### Files changed in addendum

- `lumie_backend/app/services/meal_service.py` — bridge rewritten to upsert,
  `update_meal` and `save_correction` flip `user_edited=True`, `hashlib` import added.
- `lumie_backend/app/api/task_routes.py` — bridge fired from create / update /
  attachments / note (in addition to existing complete handler).
- `lumie_backend/app/resources/schema/lumie_schema.json` — `user_edited` and
  `bridge_note_hash` documented on `meals`.

### Migration

No backfill needed. Existing meals lacking `user_edited` are treated as
`False` (they pre-date the lock and are still bridge-syncable, which is the
correct behavior).
