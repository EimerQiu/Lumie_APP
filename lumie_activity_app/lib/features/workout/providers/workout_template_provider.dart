import 'package:flutter/foundation.dart';
import '../../../core/services/workout_service.dart';
import '../../../shared/models/workout_plan_models.dart';

class WorkoutTemplateProvider extends ChangeNotifier {
  final WorkoutApiService _api = WorkoutApiService();

  List<WorkoutTemplate> _templates = [];
  List<WorkoutTemplate> get templates => _templates;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  void setToken(String token) => _api.setToken(token);
  void clearToken() => _api.clearToken();

  Future<void> loadTemplates() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _templates = await _api.listTemplates();
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  WorkoutTemplate? getTemplateById(String id) {
    try {
      return _templates.firstWhere((t) => t.templateId == id);
    } catch (_) {
      return null;
    }
  }

  Future<WorkoutTemplate?> createTemplate({
    required String name,
    String emoji = '💪',
    String splitType = 'full_body',
    String? splitDayLabel,
    String? splitGroupId,
    List<WorkoutBlock> blocks = const [],
    int restDurationSeconds = 60,
  }) async {
    try {
      final template = await _api.createTemplate(
        name: name,
        emoji: emoji,
        splitType: splitType,
        splitDayLabel: splitDayLabel,
        splitGroupId: splitGroupId,
        blocks: blocks.map((b) => b.toJson()).toList(),
        restDurationSeconds: restDurationSeconds,
      );
      _templates.insert(0, template);
      notifyListeners();
      return template;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<WorkoutTemplate?> updateTemplate(
    String templateId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final updated = await _api.updateTemplate(templateId, updates);
      final idx = _templates.indexWhere((t) => t.templateId == templateId);
      if (idx >= 0) _templates[idx] = updated;
      notifyListeners();
      return updated;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteTemplate(String templateId) async {
    try {
      final ok = await _api.deleteTemplate(templateId);
      if (ok) {
        _templates.removeWhere((t) => t.templateId == templateId);
        notifyListeners();
      }
      return ok;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<WorkoutTemplate?> duplicateTemplate(String templateId) async {
    try {
      final copy = await _api.duplicateTemplate(templateId);
      _templates.insert(0, copy);
      notifyListeners();
      return copy;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Templates grouped by split_group_id (for multi-day splits).
  Map<String?, List<WorkoutTemplate>> get templatesBySplit {
    final map = <String?, List<WorkoutTemplate>>{};
    for (final t in _templates) {
      map.putIfAbsent(t.splitGroupId, () => []).add(t);
    }
    return map;
  }

  /// Overload advice for a template.
  Future<List<OverloadSuggestion>> getOverloadAdvice(
      String templateId) async {
    try {
      return await _api.getOverloadAdvice(templateId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }
}
