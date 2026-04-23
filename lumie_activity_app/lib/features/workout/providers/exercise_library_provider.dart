import 'package:flutter/foundation.dart';
import '../../../core/services/workout_service.dart';
import '../../../shared/models/workout_plan_models.dart';

class ExerciseLibraryProvider extends ChangeNotifier {
  final WorkoutApiService _api = WorkoutApiService();

  List<ExerciseDefinition> _exercises = [];
  List<ExerciseDefinition> get exercises => _exercises;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  // Filters
  String? _muscleGroupFilter;
  String? get muscleGroupFilter => _muscleGroupFilter;

  String? _equipmentFilter;
  String? get equipmentFilter => _equipmentFilter;

  String? _movementTypeFilter;
  String? get movementTypeFilter => _movementTypeFilter;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  void setToken(String token) => _api.setToken(token);
  void clearToken() => _api.clearToken();

  Future<void> loadExercises() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _exercises = await _api.listExercises(
        muscleGroup: _muscleGroupFilter,
        equipmentType: _equipmentFilter,
        movementType: _movementTypeFilter,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  void setMuscleGroupFilter(String? value) {
    _muscleGroupFilter = value;
    loadExercises();
  }

  void setEquipmentFilter(String? value) {
    _equipmentFilter = value;
    loadExercises();
  }

  void setMovementTypeFilter(String? value) {
    _movementTypeFilter = value;
    loadExercises();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    loadExercises();
  }

  void clearFilters() {
    _muscleGroupFilter = null;
    _equipmentFilter = null;
    _movementTypeFilter = null;
    _searchQuery = '';
    loadExercises();
  }

  /// Whether any filter is active.
  bool get hasActiveFilters =>
      _muscleGroupFilter != null ||
      _equipmentFilter != null ||
      _movementTypeFilter != null;

  Future<ExerciseDefinition?> createCustomExercise({
    required String name,
    String description = '',
    List<String> primaryMuscles = const [],
    List<String> secondaryMuscles = const [],
    required String equipmentType,
    String movementType = 'isolation',
    String formDescription = '',
  }) async {
    try {
      final exercise = await _api.createExercise(
        name: name,
        description: description,
        primaryMuscles: primaryMuscles,
        secondaryMuscles: secondaryMuscles,
        equipmentType: equipmentType,
        movementType: movementType,
        formDescription: formDescription,
      );
      _exercises.insert(0, exercise);
      notifyListeners();
      return exercise;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> deleteExercise(String exerciseId) async {
    try {
      final ok = await _api.deleteExercise(exerciseId);
      if (ok) {
        _exercises.removeWhere((e) => e.exerciseId == exerciseId);
        notifyListeners();
      }
      return ok;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Available muscle group filter options.
  static const muscleGroups = [
    'chest',
    'back',
    'shoulders',
    'biceps',
    'triceps',
    'legs',
    'quadriceps',
    'hamstrings',
    'glutes',
    'core',
    'calves',
    'forearms',
    'full_body',
  ];

  /// Available equipment filter options.
  static const equipmentTypes = [
    'bodyweight',
    'dumbbell',
    'barbell',
    'machine',
    'cable',
    'band',
  ];

  /// Human-readable label for a muscle group key.
  static String muscleLabel(String key) {
    const labels = {
      'chest': 'Chest',
      'back': 'Back',
      'shoulders': 'Shoulders',
      'biceps': 'Biceps',
      'triceps': 'Triceps',
      'legs': 'Legs',
      'quadriceps': 'Quads',
      'hamstrings': 'Hamstrings',
      'glutes': 'Glutes',
      'core': 'Core',
      'calves': 'Calves',
      'forearms': 'Forearms',
      'full_body': 'Full Body',
      'lats': 'Lats',
      'rhomboids': 'Rhomboids',
      'traps': 'Traps',
      'lower_back': 'Lower Back',
    };
    return labels[key] ?? key[0].toUpperCase() + key.substring(1);
  }

  /// Available movement type filter options.
  static const movementTypes = [
    'push',
    'pull',
    'hinge',
    'squat',
    'carry',
    'isolation',
    'compound',
  ];

  static String movementTypeLabel(String key) {
    const labels = {
      'push': 'Push',
      'pull': 'Pull',
      'hinge': 'Hinge',
      'squat': 'Squat',
      'carry': 'Carry',
      'isolation': 'Isolation',
      'compound': 'Compound',
    };
    return labels[key] ?? key[0].toUpperCase() + key.substring(1);
  }

  static String equipmentLabel(String key) {
    const labels = {
      'bodyweight': 'Bodyweight',
      'dumbbell': 'Dumbbell',
      'barbell': 'Barbell',
      'machine': 'Machine',
      'cable': 'Cable',
      'band': 'Band',
    };
    return labels[key] ?? key;
  }
}
