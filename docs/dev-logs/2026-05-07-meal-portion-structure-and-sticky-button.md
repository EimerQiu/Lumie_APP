# Meal feature — portion structure, meal-time rule, sticky save button

Date: 2026-05-07

## Summary

Three UX/data updates to the Meal Log/Analyze flow:

1. **Portion slider granularity** is now decided per meal by an LLM-classified
   `structure` field: `multi_item` (one drag bar per food) or
   `single_item_with_ingredients` (one drag bar per ingredient inside a
   composite dish). Ambiguous cases default to `multi_item`.
2. **Meal time** is anchored to the user's actual upload/log/confirm moment,
   never to the Nutrition task's scheduled start time.
3. The **Re-analyze / Save action button** is now pinned to the bottom of the
   screen via `Scaffold.bottomNavigationBar` and stops scrolling with the
   content.

No calorie language, gram values, or "good/bad food" labels were introduced.
Slider labels are simple "Less" and "More" anchors.

## Decisions

- **Structure is set by the LLM, validated server-side.** The structuring
  prompt now classifies each meal as `multi_item` or
  `single_item_with_ingredients` and emits an `ingredients` array on the one
  composite food when applicable. The server falls back to `multi_item` when
  the LLM is silent or self-contradicts (e.g. claims `single_item_…` but
  emits >1 food). Rationale: per CLAUDE.md, semantic categorisation belongs
  in the LLM, not in client-side heuristics.
- **Re-analyze on save, not as a separate button state.** The bottom button
  has 4 states only: `Analyze Meal`, `Save Meal`, `Save Changes`, and a
  disabled spinner. When the user has edits, tapping `Save Changes`
  internally triggers a `restructureFoodList` call followed by
  `confirmDraft` so the saved meal reflects the corrected food list without
  requiring two taps.
- **Meal time at confirm is `DateTime.now()` unless the user picked a
  different time.** A new `_userEditedMealTime` flag tracks whether the user
  used the time pill; until then, the saved `mealTime` is recomputed at
  confirm time so the meal carries the actual log moment.
- **Bridge fix.** `_parse_task_local_dt` previously fell back to the task's
  `open_datetime` (scheduled start). Replaced with
  `_parse_task_completed_at` which only reads `completed_at`, otherwise
  defers to `now` in the bridge. The bridge will never stamp a meal with
  the scheduled task start time again.

## New / modified files

### Backend

- Modified `lumie_backend/app/models/meal.py`
  - Added `MealStructure` enum (`MULTI_ITEM`, `SINGLE_ITEM_WITH_INGREDIENTS`)
  - Added `Ingredient` model (`name`, `portion_weight`)
  - Added optional `ingredients: List[Ingredient]` to `FoodItem`
  - Threaded `structure` through `MealAnalyzeResponse`, `MealCreate`,
    `MealUpdate`, `MealResponse`, and `MealRestructureResponse`
- Modified `lumie_backend/app/services/meal_service.py`
  - Imported `MealStructure` and `Ingredient`
  - Updated `_structure_text_to_meal` system prompt with structure
    classification rules + the new JSON schema
  - Updated `_parse_analysis_json` to coerce `structure` and ingredient
    arrays, with a self-consistency check (single_item_with_ingredients
    must have exactly one food_item)
  - Added `_build_restructure_text` and `_infer_structure_from_items`
    helpers, used by `restructure_food_list` and update/create paths so
    user-edited ingredient changes round-trip cleanly through the LLM
  - `analyze_uploads` and `_meal_doc_to_response` now return `structure`
  - `create_meal` and `update_meal` persist `structure`, strip ingredients
    on multi_item, and re-analyse on any ingredient-level edit
  - `_food_lists_equal_with_portions` now compares ingredients too, so
    `update_meal` detects ingredient-only edits
  - **Bridge fix:** `_parse_task_local_dt` → `_parse_task_completed_at`,
    and `create_meal_from_nutrition_task` no longer falls back to
    `open_datetime`

### Frontend

- Modified `lumie_activity_app/lib/shared/models/meal_models.dart`
  - Added `MealStructure` enum
  - Added `Ingredient` class with JSON round-trip
  - Added optional `ingredients` to `FoodItem` (with a `clearIngredients`
    flag in `copyWith`)
  - Threaded `structure` through `MealAnalyzeResult` and `Meal`
- Modified `lumie_activity_app/lib/features/meals/widgets/portion_ratio_bar.dart`
  - Added `Less` / `More` anchor labels under the segmented bar
- Modified `lumie_activity_app/lib/features/meals/screens/meal_log_screen.dart`
  - Tracks `_structure` from the analysis result
  - `_buildPortionSection` renders ingredient-level bar when
    `structure == singleItemWithIngredients`, item-level bar otherwise
  - Added ingredient editing UI: chip list, add/remove/rename dialogs,
    and a dedicated portion handler `_onIngredientPortionsChanged`
  - `_hasFoodEdits` now detects ingredient edits
  - Action button moved to `Scaffold.bottomNavigationBar` with `SafeArea`
  - New `_buildStickyActionBar` covers the 4 button states from the spec
  - `_saveWithReanalyze` runs re-structure → confirm in one tap when
    foods/ingredients changed
  - `_userEditedMealTime` flag; `_confirm` uses `DateTime.now()` (and a
    fresh meal type derivation) if the user didn't touch the time pill

## API contract changes

- `MealAnalyzeResponse` and `MealResponse` gained `structure: MealStructure`
  (always present; defaults to `multi_item`).
- `FoodItem` may now carry an optional `ingredients: List[Ingredient]`.
  Clients that ignore the field still work (multi-item rendering is the
  default).
- `MealCreate.structure` and `MealUpdate.structure` are optional inputs;
  when omitted, the server infers from the food list (single food item with
  ingredients ⇒ `single_item_with_ingredients`, else `multi_item`).

## DB

- Existing meals that pre-date this change get `structure` filled at
  read-time via `_infer_structure_from_items` (defaults to `multi_item`).
  No migration required.
- New writes persist `structure` as a top-level string field on `meals`.
- `meals.food_items[*].ingredients` may now contain
  `[{name, portion_weight}]` objects (only when structure is
  `single_item_with_ingredients`).

## Testing checklist

- [ ] Photo of bread + almond butter + milk → MULTI_ITEM, 3 portion bars at
      the food level.
- [ ] Photo of yogurt bowl with granola + berries →
      SINGLE_ITEM_WITH_INGREDIENTS, single food chip with 3 ingredient pills
      and a 3-segment portion bar at the ingredient level.
- [ ] Drag ingredient bar; tap `Save Changes`; meal saves with adjusted
      ingredient portion weights and a refreshed nutrition_level.
- [ ] Time pill auto-fills with current time but not user-edited; tap save
      after waiting; saved `meal_time` ≈ confirm timestamp, not screen-open
      timestamp.
- [ ] Edit time pill manually; saved `meal_time` matches the picked value.
- [ ] Nutrition task with `open_datetime = 12:00`; user logs at 19:00; the
      bridged meal's `meal_time` is 19:00, not 12:00.
- [ ] Bottom action button stays visible while scrolling foods, macros,
      note, and visibility sections.
- [ ] Slider shows "Less" on the left and "More" on the right; no numbers
      anywhere.

## Future work / deferred

- The Meal Detail screen still uses the old food-level `PortionRatioBar`
  unconditionally. Once the structure field is stable in production data,
  swap it to the same item-vs-ingredient logic as the log screen.
- A handful of legacy meals will read as `multi_item` even when their
  free-text contents would have been classified `single_item_with_ingredients`
  by today's prompt. Acceptable: any user edit will reclassify on save via
  `update_meal`.
