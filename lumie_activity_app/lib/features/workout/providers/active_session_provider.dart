import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/workout_service.dart';
import '../../../shared/models/workout_plan_models.dart';

/// Manages the state of an in-progress workout session.
///
/// Handles the exercise queue (including superset/circuit groups),
/// set completion flow, rest timers, weight pre-filling from history,
/// and saving the session to the backend with PR detection.
class ActiveSessionProvider extends ChangeNotifier {
  final WorkoutApiService _api = WorkoutApiService();

  void setToken(String token) => _api.setToken(token);
  void clearToken() => _api.clearToken();

  // ── Session state ─────────────────────────────────────────────────────────

  WorkoutTemplate? _template;
  WorkoutTemplate? get template => _template;

  List<CompletedExercise> _completedExercises = [];
  List<CompletedExercise> get completedExercises => _completedExercises;

  /// Flat ordered list of all exercises from the template blocks.
  List<SessionExerciseEntry> _exerciseQueue = [];
  List<SessionExerciseEntry> get exerciseQueue => _exerciseQueue;

  int _currentExerciseIndex = 0;
  int get currentExerciseIndex => _currentExerciseIndex;

  int _currentSetIndex = 0;
  int get currentSetIndex => _currentSetIndex;

  bool _isActive = false;
  bool get isActive => _isActive;

  bool _isResting = false;
  bool get isResting => _isResting;

  bool _isComplete = false;
  bool get isComplete => _isComplete;

  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;

  // Duration timer
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  int get elapsedSeconds => _elapsedSeconds;

  // Rest timer
  Timer? _restTimer;
  int _restSecondsRemaining = 0;
  int get restSecondsRemaining => _restSecondsRemaining;
  int _currentRestDuration = 60; // tracks the initial rest for progress calc
  int get currentRestDuration => _currentRestDuration;
  int _defaultRestSeconds = 60;

  // Skip detection tracking (per session, resets next session)
  final Set<int> _skipDetectionExercises = {};
  bool isDetectionSkipped(int exerciseIndex) =>
      _skipDetectionExercises.contains(exerciseIndex);
  void toggleDetectionSkip(int exerciseIndex) {
    if (_skipDetectionExercises.contains(exerciseIndex)) {
      _skipDetectionExercises.remove(exerciseIndex);
    } else {
      _skipDetectionExercises.add(exerciseIndex);
    }
    notifyListeners();
  }

  // Heart rate (optional, from ring)
  int? _heartRateAvg;
  int? _heartRateMax;
  final List<int> _heartRates = [];

  void recordHeartRate(int bpm) {
    _heartRates.add(bpm);
    if (_heartRateMax == null || bpm > _heartRateMax!) _heartRateMax = bpm;
    _heartRateAvg =
        (_heartRates.reduce((a, b) => a + b) / _heartRates.length).round();
  }

  // Per-exercise set tracking for supersets — each exercise in the queue
  // maintains its own "how many sets have been completed" counter.
  late List<int> _setsCompletedPerExercise;

  // Weight history cache: exerciseId → last used weight
  final Map<String, double> _lastSessionWeights = {};

  // PRs detected after save
  List<Map<String, dynamic>> _sessionPRs = [];
  List<Map<String, dynamic>> get sessionPRs => _sessionPRs;

  // Overload suggestions (loaded after save)
  List<OverloadSuggestion> _overloadSuggestions = [];
  List<OverloadSuggestion> get overloadSuggestions => _overloadSuggestions;

  // Session notes
  String _sessionNotes = '';
  String get sessionNotes => _sessionNotes;
  void setSessionNotes(String notes) {
    _sessionNotes = notes;
    notifyListeners();
  }

  // ── Current exercise helpers ──────────────────────────────────────────────

  SessionExerciseEntry? get currentEntry =>
      _currentExerciseIndex < _exerciseQueue.length
          ? _exerciseQueue[_currentExerciseIndex]
          : null;

  TemplateExercise? get currentTemplateExercise => currentEntry?.exercise;

  String get currentBlockName => currentEntry?.blockName ?? '';

  int get currentTotalSets => currentTemplateExercise?.defaultSets ?? 0;

  bool get currentUseCamera {
    final entry = currentEntry;
    if (entry == null) return false;
    if (isDetectionSkipped(_currentExerciseIndex)) return false;
    final ex = entry.exercise;
    return ex.poseType != null &&
        ex.poseType != PoseType.machine &&
        ex.equipmentType != 'machine';
  }

  /// The last weight the user used for the current exercise (from history).
  double? get currentLastSessionWeight {
    final ex = currentTemplateExercise;
    if (ex == null) return null;
    return _lastSessionWeights[ex.exerciseId];
  }

  /// Effective pre-fill weight: last session > template default > null
  double? get currentPrefilledWeight {
    return currentLastSessionWeight ??
        currentTemplateExercise?.defaultWeight;
  }

  // ── Session lifecycle ─────────────────────────────────────────────────────

  Future<void> startSession(WorkoutTemplate template) async {
    _template = template;
    _defaultRestSeconds = template.restDurationSeconds;
    _isActive = true;
    _isComplete = false;
    _isResting = false;
    _currentExerciseIndex = 0;
    _currentSetIndex = 0;
    _elapsedSeconds = 0;
    _startedAt = DateTime.now().toUtc();
    _heartRates.clear();
    _heartRateAvg = null;
    _heartRateMax = null;
    _skipDetectionExercises.clear();
    _sessionPRs = [];
    _overloadSuggestions = [];
    _sessionNotes = '';
    _lastSessionWeights.clear();

    // Build exercise queue from blocks
    _exerciseQueue = [];
    for (final block in template.blocks) {
      for (final ex in block.exercises) {
        _exerciseQueue.add(SessionExerciseEntry(
          exercise: ex,
          blockName: block.name,
        ));
      }
    }

    // Initialize per-exercise set counters
    _setsCompletedPerExercise = List.filled(_exerciseQueue.length, 0);

    // Initialize completed exercises
    _completedExercises = _exerciseQueue.map((entry) {
      final ex = entry.exercise;
      return CompletedExercise(
        exerciseId: ex.exerciseId,
        exerciseName: ex.exerciseName,
        equipmentType: ex.equipmentType,
        poseType: ex.poseType,
        setType: ex.setType,
        groupId: ex.groupId,
        blockName: entry.blockName,
        sets: List.generate(
          ex.defaultSets,
          (i) => CompletedSet(
            setIndex: i,
            targetReps: ex.defaultReps,
            targetWeight: ex.defaultWeight,
            actualReps: ex.defaultReps,
            actualWeight: ex.defaultWeight,
          ),
        ),
      );
    }).toList();

    // Start duration timer
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });

    notifyListeners();

    // Fetch last-session weights for all exercises in background
    await _prefillWeightsFromHistory();
  }

  /// Fetch the most recent weight used for each exercise in this template.
  Future<void> _prefillWeightsFromHistory() async {
    final seen = <String>{};
    for (int i = 0; i < _exerciseQueue.length; i++) {
      final eid = _exerciseQueue[i].exercise.exerciseId;
      if (seen.contains(eid)) continue;
      seen.add(eid);
      try {
        final history = await _api.getExerciseHistory(eid, limit: 1);
        if (history.isNotEmpty) {
          final lastSets = history.first['sets'] as List<dynamic>?;
          if (lastSets != null && lastSets.isNotEmpty) {
            // Find the heaviest weight from last session's sets
            double maxW = 0;
            for (final s in lastSets) {
              final w = (s['actual_weight'] as num?)?.toDouble() ?? 0;
              if (w > maxW) maxW = w;
            }
            if (maxW > 0) {
              _lastSessionWeights[eid] = maxW;
              // Update the pre-filled weight in completed sets if user
              // hasn't started the exercise yet
              for (int j = 0; j < _exerciseQueue.length; j++) {
                if (_exerciseQueue[j].exercise.exerciseId == eid &&
                    _setsCompletedPerExercise[j] == 0) {
                  for (final s in _completedExercises[j].sets) {
                    if (s.actualWeight == null ||
                        s.actualWeight == _exerciseQueue[j].exercise.defaultWeight) {
                      s.actualWeight = maxW;
                      s.targetWeight = maxW;
                    }
                  }
                }
              }
            }
          }
        }
      } catch (_) {
        // Non-critical; continue with template defaults
      }
    }
    notifyListeners();
  }

  // ── Set completion ────────────────────────────────────────────────────────

  /// Complete the current set and advance.
  void completeSet({
    int? actualReps,
    double? actualWeight,
    SetCompletionStatus status = SetCompletionStatus.completed,
    String? notes,
    bool wasCameraTracked = false,
  }) {
    if (!_isActive || _isComplete) return;

    // Determine which set index this exercise is actually on
    final exSetIdx = _setsCompletedPerExercise[_currentExerciseIndex];

    // Update the completed set data
    final compEx = _completedExercises[_currentExerciseIndex];
    if (exSetIdx < compEx.sets.length) {
      final s = compEx.sets[exSetIdx];
      s.actualReps = actualReps ?? s.targetReps;
      s.actualWeight = actualWeight ?? s.targetWeight;
      s.status = status;
      s.notes = notes;
      s.wasCameraTracked = wasCameraTracked;
    }
    _setsCompletedPerExercise[_currentExerciseIndex]++;

    // Check if this exercise is in a superset/circuit group
    final currentEx = currentTemplateExercise;
    if (currentEx != null && currentEx.groupId != null) {
      final nextInGroup = _findNextInGroup(
        _currentExerciseIndex,
        currentEx.groupId!,
      );
      if (nextInGroup != null) {
        // Move to next exercise in superset without rest
        _currentExerciseIndex = nextInGroup;
        _currentSetIndex = _setsCompletedPerExercise[nextInGroup];
        notifyListeners();
        return;
      }
      // All exercises in group completed one round — check if more rounds
      final groupStart = _findGroupStart(currentEx.groupId!);
      if (groupStart != null &&
          _setsCompletedPerExercise[groupStart] <
              _exerciseQueue[groupStart].exercise.defaultSets) {
        // More rounds to go — rest then start next round at group start
        _currentExerciseIndex = groupStart;
        _currentSetIndex = _setsCompletedPerExercise[groupStart];
        _startRest();
        notifyListeners();
        return;
      }
      // Group fully complete — advance past entire group
      _advancePastGroup(currentEx.groupId!);
      notifyListeners();
      return;
    }

    // Standard (non-grouped) exercise
    final setsLeft = currentTotalSets - _setsCompletedPerExercise[_currentExerciseIndex];
    if (setsLeft > 0) {
      _currentSetIndex = _setsCompletedPerExercise[_currentExerciseIndex];
      _startRest();
    } else {
      _advanceToNextExercise();
    }

    notifyListeners();
  }

  /// Find the next exercise in the same superset/circuit group that still
  /// has sets remaining on this round.
  int? _findNextInGroup(int currentIdx, String groupId) {
    // Look forward in the queue for the next exercise in the group
    for (int i = currentIdx + 1; i < _exerciseQueue.length; i++) {
      final ex = _exerciseQueue[i].exercise;
      if (ex.groupId != groupId) break;
      // This exercise still has sets for the current round
      if (_setsCompletedPerExercise[i] < ex.defaultSets &&
          _setsCompletedPerExercise[i] == _setsCompletedPerExercise[currentIdx]) {
        return i;
      }
    }
    // Also check exercises before current (for circuits that wrap around)
    final groupStartIdx = _findGroupStart(groupId);
    if (groupStartIdx != null && groupStartIdx < currentIdx) {
      for (int i = groupStartIdx; i < currentIdx; i++) {
        final ex = _exerciseQueue[i].exercise;
        if (ex.groupId != groupId) continue;
        if (_setsCompletedPerExercise[i] < ex.defaultSets &&
            _setsCompletedPerExercise[i] < _setsCompletedPerExercise[currentIdx]) {
          return i;
        }
      }
    }
    return null;
  }

  int? _findGroupStart(String groupId) {
    for (int i = 0; i < _exerciseQueue.length; i++) {
      if (_exerciseQueue[i].exercise.groupId == groupId) return i;
    }
    return null;
  }

  /// Advance _currentExerciseIndex past the entire superset/circuit group.
  void _advancePastGroup(String groupId) {
    _currentSetIndex = 0;
    int i = _currentExerciseIndex;
    // Move forward until we leave the group
    while (i < _exerciseQueue.length &&
        _exerciseQueue[i].exercise.groupId == groupId) {
      i++;
    }
    _currentExerciseIndex = i;
    if (_currentExerciseIndex >= _exerciseQueue.length) {
      _finishSession();
    } else {
      _startRest();
    }
  }

  void _advanceToNextExercise() {
    _currentSetIndex = 0;
    _currentExerciseIndex++;
    if (_currentExerciseIndex >= _exerciseQueue.length) {
      _finishSession();
    } else {
      _startRest();
    }
  }

  void _startRest() {
    _isResting = true;
    _currentRestDuration =
        currentTemplateExercise?.defaultRestSeconds ?? _defaultRestSeconds;
    _restSecondsRemaining = _currentRestDuration;
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _restSecondsRemaining--;
      if (_restSecondsRemaining <= 0) {
        skipRest();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void skipRest() {
    _isResting = false;
    _restTimer?.cancel();
    notifyListeners();
  }

  void adjustRestTime(int deltaSeconds) {
    _restSecondsRemaining =
        (_restSecondsRemaining + deltaSeconds).clamp(0, 600);
    notifyListeners();
  }

  void _finishSession() {
    _isActive = false;
    _isComplete = true;
    _durationTimer?.cancel();
    _restTimer?.cancel();
    notifyListeners();
  }

  void cancelSession() {
    _isActive = false;
    _isComplete = false;
    _durationTimer?.cancel();
    _restTimer?.cancel();
    notifyListeners();
  }

  /// Force-finish: mark remaining sets as skipped and go to summary.
  void finishEarly() {
    for (int i = 0; i < _completedExercises.length; i++) {
      final completed = _setsCompletedPerExercise[i];
      for (int s = completed; s < _completedExercises[i].sets.length; s++) {
        _completedExercises[i].sets[s].status = SetCompletionStatus.skipped;
      }
    }
    _finishSession();
  }

  // ── Post-workout editing ──────────────────────────────────────────────────

  /// Update a specific set's data (for post-workout corrections).
  void updateSet(
    int exerciseIndex,
    int setIndex, {
    int? actualReps,
    double? actualWeight,
    SetCompletionStatus? status,
    String? notes,
  }) {
    if (exerciseIndex >= _completedExercises.length) return;
    final ex = _completedExercises[exerciseIndex];
    if (setIndex >= ex.sets.length) return;
    final s = ex.sets[setIndex];
    if (actualReps != null) s.actualReps = actualReps;
    if (actualWeight != null) s.actualWeight = actualWeight;
    if (status != null) s.status = status;
    if (notes != null) s.notes = notes;
    notifyListeners();
  }

  // ── Save & PR detection ───────────────────────────────────────────────────

  /// Save the completed session to the backend.
  /// Returns the saved session with PR data, or null on failure.
  Future<WorkoutSession?> saveSession() async {
    if (_template == null || _startedAt == null) return null;

    final endedAt = DateTime.now().toUtc();
    try {
      final session = await _api.createSession(sessionData: {
        'template_id': _template!.templateId,
        'template_name': _template!.name,
        'started_at': _startedAt!.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_seconds': _elapsedSeconds,
        'exercises': _completedExercises.map((e) => e.toJson()).toList(),
        'heart_rate_avg': _heartRateAvg,
        'heart_rate_max': _heartRateMax,
        'notes': _sessionNotes.isNotEmpty ? _sessionNotes : null,
      });

      // Sync PRs from backend response into local state
      _sessionPRs = session.prs;
      _syncPRsToSets(session.prs);

      // Fetch overload advice if we have enough history
      _loadOverloadAdvice();

      notifyListeners();
      return session;
    } catch (e) {
      debugPrint('Failed to save session: $e');
      return null;
    }
  }

  /// Mark sets as PR based on backend response.
  void _syncPRsToSets(List<Map<String, dynamic>> prs) {
    for (final pr in prs) {
      final exerciseId = pr['exercise_id'] as String?;
      if (exerciseId == null) continue;
      for (final ex in _completedExercises) {
        if (ex.exerciseId == exerciseId) {
          // Mark the best set for this exercise as PR
          CompletedSet? bestSet;
          for (final s in ex.sets) {
            if (s.status == SetCompletionStatus.skipped) continue;
            if (bestSet == null || s.volume > bestSet.volume) {
              bestSet = s;
            }
          }
          if (bestSet != null) {
            bestSet.isPr = true;
            bestSet.status = SetCompletionStatus.pr;
          }
          break;
        }
      }
    }
  }

  Future<void> _loadOverloadAdvice() async {
    if (_template == null) return;
    try {
      _overloadSuggestions =
          await _api.getOverloadAdvice(_template!.templateId);
      notifyListeners();
    } catch (_) {
      // Non-critical
    }
  }

  // ── Computed stats for summary ────────────────────────────────────────────

  int get totalSetsCompleted => _completedExercises.fold(
      0,
      (sum, ex) =>
          sum +
          ex.sets
              .where((s) => s.status != SetCompletionStatus.skipped)
              .length);

  int get totalRepsCompleted => _completedExercises.fold(
      0,
      (sum, ex) =>
          sum +
          ex.sets
              .where((s) => s.status != SetCompletionStatus.skipped)
              .fold(0, (s, set) => s + set.actualReps));

  double get totalVolume =>
      _completedExercises.fold(0.0, (sum, ex) => sum + ex.totalVolume);

  String get formattedDuration {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _restTimer?.cancel();
    super.dispose();
  }
}

/// Pairs a TemplateExercise with its parent block name.
class SessionExerciseEntry {
  final TemplateExercise exercise;
  final String blockName;

  const SessionExerciseEntry({
    required this.exercise,
    required this.blockName,
  });
}
