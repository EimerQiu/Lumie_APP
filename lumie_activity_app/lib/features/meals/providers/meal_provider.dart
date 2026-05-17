// MealProvider — state management for the Meal Feature.
// Mirrors TasksProvider style: ChangeNotifier + service singleton + state enum.

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/meal_service.dart';
import '../../../shared/models/meal_models.dart';

enum MealsState { initial, loading, loaded, error }

/// Canonical identity for a Meal — must match the backend scheme.
///
///   - Nutrition-task meal (source-linked) → `nutrition_task:user:task`
///   - Manual meal                          → `meal:meal_id`
///
/// Used by [_mergeMealsDeduped] to keep only one card per real-world meal
/// even when stale list-state, race-conditions, or legacy DB rows would
/// otherwise produce duplicates on the Meals page.
String _mealCanonicalIdentity(Meal meal) {
  final taskId = meal.linkedTaskId;
  if (taskId != null && taskId.isNotEmpty) {
    return 'nutrition_task:${meal.userId}:$taskId';
  }
  return 'meal:${meal.mealId}';
}

/// Merge `incoming` into `existing` (in arrival order), discarding any
/// entry whose canonical identity is already represented. Preserves the
/// first occurrence's order. The "first occurrence" rule — combined with
/// the backend ordering by `created_at` desc — means the canonical
/// (oldest) row wins when stale state and a fresh fetch overlap.
List<Meal> _mergeMealsDeduped(
  Iterable<Meal> existing,
  Iterable<Meal> incoming,
) {
  final seen = <String>{};
  final out = <Meal>[];
  for (final m in [...existing, ...incoming]) {
    final id = _mealCanonicalIdentity(m);
    if (seen.add(id)) out.add(m);
  }
  return out;
}

class MealProvider extends ChangeNotifier {
  final MealService _service = MealService();

  MealsState _state = MealsState.initial;
  String? _errorMessage;

  // Personal history
  final List<Meal> _myMeals = [];
  String? _myCursor;
  bool _hasMoreMyMeals = true;

  // Team feed (single-team scope at a time)
  String? _activeTeamId;
  final List<Meal> _teamMeals = [];
  String? _teamCursor;
  bool _hasMoreTeamMeals = true;

  // Draft from /meals/analyze (not yet confirmed)
  MealAnalyzeResult? _draft;

  // Weekly nutrition trend cache for the home-screen chart.
  MealTrendResponse? _trend;
  bool _isTrendLoading = false;

  // ─── Getters ────────────────────────────────────────────────────────

  MealsState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == MealsState.loading;
  bool get hasError => _state == MealsState.error;

  List<Meal> get myMeals => List.unmodifiable(_myMeals);
  bool get hasMoreMyMeals => _hasMoreMyMeals;

  String? get activeTeamId => _activeTeamId;
  List<Meal> get teamMeals => List.unmodifiable(_teamMeals);
  bool get hasMoreTeamMeals => _hasMoreTeamMeals;

  MealAnalyzeResult? get draft => _draft;

  MealTrendResponse? get trend => _trend;
  bool get isTrendLoading => _isTrendLoading;

  // ─── Draft / analyze flow ───────────────────────────────────────────

  /// Structured analysis from typed food items — no photo required.
  ///
  /// Calls [POST /meals/analyze-text], gets a new meal_id, and stores the
  /// result as the current draft so [reanalyzeDraft] and [confirmDraft] work
  /// identically to the photo path.
  Future<MealAnalyzeResult> analyzeText({
    required List<FoodItem> foodItems,
  }) async {
    _state = MealsState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _service.analyzeText(foodItems: foodItems);
      _draft = result;
      _state = MealsState.loaded;
      notifyListeners();
      return result;
    } catch (e) {
      _state = MealsState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  /// Run analysis on selected images. Persists images on the backend and
  /// returns a draft (food items + macro ratio) the user can edit before
  /// confirming via [confirmDraft].
  Future<MealAnalyzeResult> analyzeImages(List<File> files) async {
    _state = MealsState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _service.analyzeMealImages(files: files);
      _draft = result;
      _state = MealsState.loaded;
      notifyListeners();
      return result;
    } catch (e) {
      _state = MealsState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  void clearDraft() {
    _draft = null;
    notifyListeners();
  }

  /// Re-run the structuring layer against the user's edited foods + portion
  /// weights for the current draft, without uploading the photo again. The
  /// existing draft's meal_id and images are preserved.
  Future<MealAnalyzeResult> reanalyzeDraft({
    required List<FoodItem> foodItems,
  }) async {
    final draft = _draft;
    if (draft == null) {
      throw Exception('No draft to re-analyze. Call analyzeImages first.');
    }
    final updated = await _service.restructureFoodList(
      draftMealId: draft.mealId,
      draftImages: draft.images,
      foodItems: foodItems,
    );
    _draft = updated;
    notifyListeners();
    return updated;
  }

  /// Confirm the current draft (or arbitrary edits to it) by creating a meal.
  /// Returns the persisted Meal and prepends it to [myMeals].
  ///
  /// V2 fields ([mealName] / [mealType] / [mealTime] / [nutritionLevel] /
  /// [advisorInsight]) default to whatever the analyze step produced. Pass
  /// non-null values to override (e.g. user picked a different meal type
  /// in the log screen). When unset on both sides, the backend derives them.
  Future<Meal> confirmDraft({
    required List<FoodItem> foodItems,
    required MacroRatio macroRatio,
    String? note,
    MealVisibility visibility = MealVisibility.private,
    String? teamId,
    String? linkedTaskId,
    String? mealName,
    MealType? mealType,
    DateTime? mealTime,
    NutritionLevel? nutritionLevel,
    String? advisorInsight,
    MacroLevel? processingLevel,
    MacroLevel? addedSugar,
    String? timezone,
    bool textOnly = false,
  }) async {
    final draft = _draft;
    if (draft == null) {
      throw Exception('No draft to confirm. Call analyzeImages first.');
    }
    final meal = await _service.createMeal(
      mealId: draft.mealId,
      foodItems: foodItems,
      macroRatio: macroRatio,
      note: note,
      visibility: visibility,
      teamId: teamId,
      linkedTaskId: linkedTaskId,
      mealName: mealName ?? draft.mealName,
      mealType: mealType,
      mealTime: mealTime,
      nutritionLevel: nutritionLevel ?? draft.nutritionLevel,
      advisorInsight: advisorInsight ?? draft.advisorInsight,
      processingLevel: processingLevel ?? draft.processingLevel,
      addedSugar: addedSugar ?? draft.addedSugar,
      timezone: timezone,
      textOnly: textOnly,
      isPackaged: draft.isPackaged,
      detectedBrand: draft.detectedBrand,
      detectedProduct: draft.detectedProduct,
    );
    // Prepend the new meal, then dedupe by canonical identity. If a stale
    // server row for the same nutrition task is already in `_myMeals` (the
    // user happened to log via the task flow earlier), the prepended fresh
    // copy wins because it appears first in the merge.
    final merged = _mergeMealsDeduped([meal], _myMeals);
    _myMeals
      ..clear()
      ..addAll(merged);
    if (meal.isTeamMeal && meal.teamId == _activeTeamId) {
      final mergedTeam = _mergeMealsDeduped([meal], _teamMeals);
      _teamMeals
        ..clear()
        ..addAll(mergedTeam);
    }
    _draft = null;
    // The new meal moved today's average — invalidate the cached trend so the
    // home screen re-fetches on next visit.
    _trend = null;
    notifyListeners();
    return meal;
  }

  // ─── Personal history ────────────────────────────────────────────────

  Future<void> loadMyMeals({bool refresh = false}) async {
    if (refresh) {
      _myMeals.clear();
      _myCursor = null;
      _hasMoreMyMeals = true;
    }
    if (!_hasMoreMyMeals && !refresh) return;

    _state = MealsState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _service.listMyMeals(before: _myCursor);
      // Defensive dedupe: even after the storage migration, a race between
      // a fresh-fetch and a previously-loaded page can put two copies of
      // the same canonical meal in the list. Existing entries win (page
      // order) so pagination remains stable.
      final merged = _mergeMealsDeduped(_myMeals, response.meals);
      _myMeals
        ..clear()
        ..addAll(merged);
      _myCursor = response.nextCursor;
      _hasMoreMyMeals = response.nextCursor != null;
      _state = MealsState.loaded;
    } catch (e) {
      _state = MealsState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  // ─── Team feed ───────────────────────────────────────────────────────

  Future<void> loadTeamFeed(String teamId, {bool refresh = false}) async {
    if (_activeTeamId != teamId || refresh) {
      _activeTeamId = teamId;
      _teamMeals.clear();
      _teamCursor = null;
      _hasMoreTeamMeals = true;
    }
    if (!_hasMoreTeamMeals && !refresh) return;

    _state = MealsState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final response =
          await _service.getTeamMealFeed(teamId: teamId, before: _teamCursor);
      final merged = _mergeMealsDeduped(_teamMeals, response.meals);
      _teamMeals
        ..clear()
        ..addAll(merged);
      _teamCursor = response.nextCursor;
      _hasMoreTeamMeals = response.nextCursor != null;
      _state = MealsState.loaded;
    } catch (e) {
      _state = MealsState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  // ─── Edit / delete ──────────────────────────────────────────────────

  Future<Meal> updateMeal({
    required String mealId,
    List<FoodItem>? foodItems,
    MacroRatio? macroRatio,
    String? note,
    MealVisibility? visibility,
    bool sendTeamId = false,
    String? teamId,
    String? mealName,
    MealType? mealType,
    DateTime? mealTime,
    NutritionLevel? nutritionLevel,
    String? advisorInsight,
    MacroLevel? processingLevel,
    MacroLevel? addedSugar,
  }) async {
    final updated = await _service.updateMeal(
      mealId: mealId,
      foodItems: foodItems,
      macroRatio: macroRatio,
      note: note,
      visibility: visibility,
      sendTeamId: sendTeamId,
      teamId: teamId,
      mealName: mealName,
      mealType: mealType,
      mealTime: mealTime,
      nutritionLevel: nutritionLevel,
      advisorInsight: advisorInsight,
      processingLevel: processingLevel,
      addedSugar: addedSugar,
    );
    _replaceLocal(updated);
    // ANY edit can shift a daily trend point: food edits trigger backend
    // re-analysis (which re-derives nutrition_level), meal_time changes move
    // a meal to a different day, and direct level/macro tweaks obviously
    // matter. Invalidate unconditionally so the home chart never shows a
    // stale daily average. The cost is one cheap GET on next visit.
    _trend = null;
    notifyListeners();
    return updated;
  }

  /// Load (or refresh) the weekly nutrition trend.
  Future<MealTrendResponse?> loadTrend({int days = 7, bool refresh = false}) async {
    if (_trend != null && !refresh) return _trend;
    _isTrendLoading = true;
    notifyListeners();
    try {
      _trend = await _service.getTrend(days: days);
      return _trend;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      _isTrendLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteMeal(String mealId) async {
    await _service.deleteMeal(mealId);
    _myMeals.removeWhere((m) => m.mealId == mealId);
    _teamMeals.removeWhere((m) => m.mealId == mealId);
    // Removing a meal changes the affected day's average — invalidate trend.
    _trend = null;
    notifyListeners();
  }

  Future<Meal> reloadMeal(String mealId) async {
    final fresh = await _service.getMeal(mealId);
    _replaceLocal(fresh);
    notifyListeners();
    return fresh;
  }

  // ─── Corrections ────────────────────────────────────────────────────

  Future<MealCorrectionResponse> submitCorrection({
    required String mealId,
    required List<FoodItem> originalFoodItems,
    required List<FoodItem> correctedFoodItems,
    MacroRatio? originalMacroRatio,
    MacroRatio? correctedMacroRatio,
  }) {
    return _service.submitCorrection(
      mealId: mealId,
      originalFoodItems: originalFoodItems,
      correctedFoodItems: correctedFoodItems,
      originalMacroRatio: originalMacroRatio,
      correctedMacroRatio: correctedMacroRatio,
    );
  }

  // ─── Lifecycle hooks (called by AuthProvider) ───────────────────────

  void clearOnLogout() {
    _myMeals.clear();
    _teamMeals.clear();
    _myCursor = null;
    _teamCursor = null;
    _hasMoreMyMeals = true;
    _hasMoreTeamMeals = true;
    _activeTeamId = null;
    _draft = null;
    _trend = null;
    _isTrendLoading = false;
    _state = MealsState.initial;
    _errorMessage = null;
    notifyListeners();
  }

  // ─── Internals ──────────────────────────────────────────────────────

  void _replaceLocal(Meal meal) {
    // Personal history: meals always belong to their owner, so a simple replace
    // is sufficient (visibility/team transitions don't affect membership here).
    final myIdx = _myMeals.indexWhere((m) => m.mealId == meal.mealId);
    if (myIdx >= 0) _myMeals[myIdx] = meal;

    // Team feed: a Team→Private transition (or a switch to a *different* team)
    // means the meal no longer belongs in the active team feed cache. Evict
    // proactively so the UI reflects the change without waiting for a refresh.
    // Conversely, a Private→Team transition into the active team is inserted
    // at the head — the user just touched it, so newest-first is correct.
    final teamIdx = _teamMeals.indexWhere((m) => m.mealId == meal.mealId);
    final eligibleForActiveTeamFeed =
        meal.isTeamMeal && meal.teamId == _activeTeamId;
    if (teamIdx >= 0) {
      if (eligibleForActiveTeamFeed) {
        _teamMeals[teamIdx] = meal;
      } else {
        _teamMeals.removeAt(teamIdx);
      }
    } else if (eligibleForActiveTeamFeed) {
      _teamMeals.insert(0, meal);
    }
  }
}
