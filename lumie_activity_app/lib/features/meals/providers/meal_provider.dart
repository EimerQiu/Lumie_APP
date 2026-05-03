// MealProvider — state management for the Meal Feature.
// Mirrors TasksProvider style: ChangeNotifier + service singleton + state enum.

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/meal_service.dart';
import '../../../shared/models/meal_models.dart';

enum MealsState { initial, loading, loaded, error }

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
    String? mealName,
    MealType? mealType,
    DateTime? mealTime,
    NutritionLevel? nutritionLevel,
    String? advisorInsight,
    String? timezone,
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
      mealName: mealName ?? draft.mealName,
      mealType: mealType,
      mealTime: mealTime,
      nutritionLevel: nutritionLevel ?? draft.nutritionLevel,
      advisorInsight: advisorInsight ?? draft.advisorInsight,
      timezone: timezone,
    );
    _myMeals.insert(0, meal);
    if (meal.isTeamMeal && meal.teamId == _activeTeamId) {
      _teamMeals.insert(0, meal);
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
      _myMeals.addAll(response.meals);
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
      _teamMeals.addAll(response.meals);
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
    );
    _replaceLocal(updated);
    // If macros / nutrition level changed, the trend may shift — invalidate.
    if (macroRatio != null || nutritionLevel != null) {
      _trend = null;
    }
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
