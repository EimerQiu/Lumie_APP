/// Admin Tasks Provider - State management for admin dashboard
///
/// Manages global task view, member filtering, pagination,
/// and admin actions (complete/delete any member's task).

import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/services/task_service.dart';
import '../../../core/services/team_service.dart';
import '../../../shared/models/task_models.dart';
import '../../../shared/models/team_models.dart';

enum AdminTasksState { initial, loading, loaded, error }

/// Represents a team member for quick-filter chips
class TeamMemberChip {
  final String userId;
  final String name;
  final String email;
  final String teamId;
  final String teamName;

  const TeamMemberChip({
    required this.userId,
    required this.name,
    required this.email,
    required this.teamId,
    required this.teamName,
  });
}

class AdminTasksProvider extends ChangeNotifier {
  final TaskService _taskService = TaskService();
  final TeamService _teamService = TeamService();

  AdminTasksState _state = AdminTasksState.initial;
  List<AdminTaskData> _previousTasks = [];
  List<AdminTaskData> _upcomingTasks = [];
  List<TeamMemberChip> _memberChips = [];
  String? _filterEmail;
  String? _errorMessage;
  int _previousOffset = 0;
  int _upcomingOffset = 0;
  bool _isLoadingMorePrevious = false;
  bool _isLoadingMoreUpcoming = false;
  bool _hasMorePrevious = true;
  bool _hasMoreUpcoming = true;
  bool _isAdmin = false;

  // Getters
  AdminTasksState get state => _state;
  List<AdminTaskData> get previousTasks => _previousTasks;
  List<AdminTaskData> get upcomingTasks => _upcomingTasks;
  List<TeamMemberChip> get memberChips => _memberChips;
  String? get filterEmail => _filterEmail;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == AdminTasksState.loading;
  bool get hasError => _state == AdminTasksState.error;
  bool get isLoadingMorePrevious => _isLoadingMorePrevious;
  bool get isLoadingMoreUpcoming => _isLoadingMoreUpcoming;
  bool get hasMorePrevious => _hasMorePrevious;
  bool get hasMoreUpcoming => _hasMoreUpcoming;
  bool get isAdmin => _isAdmin;

  String _getDeviceTimezone() {
    try {
      String tzName = tz.local.name;
      if (tzName == 'UTC' || tzName.isEmpty) {
        final now = DateTime.now();
        final offsetHours = now.timeZoneOffset.inHours;
        final Map<int, String> offsetMap = {
          -8: 'America/Los_Angeles',
          -7: 'America/Denver',
          -6: 'America/Chicago',
          -5: 'America/New_York',
          0: 'UTC',
          1: 'Europe/London',
          8: 'Asia/Shanghai',
          9: 'Asia/Tokyo',
        };
        return offsetMap[offsetHours] ?? 'UTC';
      }
      return tzName;
    } catch (e) {
      return 'UTC';
    }
  }

  /// Load team member chips for quick-filter
  /// For admins: shows all team members from teams they admin
  /// For members: shows only their own info
  Future<void> loadMemberChips() async {
    try {
      final teamsResponse = await _teamService.getTeams();
      final allTeams = teamsResponse.teams
          .where((t) => t.status == MemberStatus.member)
          .toList();

      final adminTeams = allTeams
          .where((t) => t.role == TeamRole.admin)
          .toList();

      _isAdmin = adminTeams.isNotEmpty;

      final seenEmails = <String>{};
      final chips = <TeamMemberChip>[];

      if (_isAdmin) {
        // Admin: Fetch members for each admin team
        for (final team in adminTeams) {
          final membersResponse = await _teamService.getTeamMembers(
            team.teamId,
          );
          for (final member in membersResponse.members) {
            if (member.status == MemberStatus.member &&
                !seenEmails.contains(member.email)) {
              seenEmails.add(member.email);
              chips.add(
                TeamMemberChip(
                  userId: member.userId,
                  name: member.name,
                  email: member.email,
                  teamId: team.teamId,
                  teamName: team.name,
                ),
              );
            }
          }
        }
      }
      // Non-admin members: chips will be empty - they view their own tasks by default
      // Admin members can use chips to filter other team members' tasks

      _memberChips = chips;
      notifyListeners();
    } catch (e) {
      // Non-fatal: chips just won't load
    }
  }

  /// Load admin task list (initial or refresh)
  Future<void> loadTasks({String? email}) async {
    _state = AdminTasksState.loading;
    _errorMessage = null;
    _filterEmail = email;
    _previousOffset = 0;
    _upcomingOffset = 0;
    _hasMorePrevious = true;
    _hasMoreUpcoming = true;
    notifyListeners();

    try {
      final response = await _taskService.getAdminTaskList(
        email: email,
        timeZone: _getDeviceTimezone(),
        previousOffset: 0,
        upcomingOffset: 0,
      );
      // Sort previous tasks ascending (oldest first)
      final sortedPrevious = response.previousTasks.toList();
      sortedPrevious.sort((a, b) => a.openDatetime.compareTo(b.openDatetime));
      _previousTasks = sortedPrevious;

      // Sort upcoming tasks ascending (earliest first)
      final sortedUpcoming = response.upcomingTasks.toList();
      sortedUpcoming.sort((a, b) => a.openDatetime.compareTo(b.openDatetime));
      _upcomingTasks = sortedUpcoming;

      _hasMorePrevious = response.previousTasks.length >= 10;
      _hasMoreUpcoming = response.upcomingTasks.length >= 10;
      _state = AdminTasksState.loaded;
    } catch (e) {
      _state = AdminTasksState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    }

    notifyListeners();
  }

  /// Load more previous tasks (pagination)
  Future<void> loadMorePrevious() async {
    if (_isLoadingMorePrevious || !_hasMorePrevious) return;
    _isLoadingMorePrevious = true;
    notifyListeners();

    try {
      _previousOffset += 10;
      final response = await _taskService.getAdminTaskList(
        email: _filterEmail,
        timeZone: _getDeviceTimezone(),
        previousOffset: _previousOffset,
        upcomingOffset: _upcomingOffset,
      );

      // Deduplicate by task_id
      final existingIds = _previousTasks.map((t) => t.taskId).toSet();
      final newTasks = response.previousTasks
          .where((t) => !existingIds.contains(t.taskId))
          .toList();

      // Merge and sort ascending (oldest first)
      final merged = [..._previousTasks, ...newTasks];
      merged.sort((a, b) => a.openDatetime.compareTo(b.openDatetime));
      _previousTasks = merged;

      _hasMorePrevious = response.previousTasks.length >= 10;
    } catch (e) {
      _previousOffset -= 10;
    }

    _isLoadingMorePrevious = false;
    notifyListeners();
  }

  /// Load more upcoming tasks (pagination)
  Future<void> loadMoreUpcoming() async {
    if (_isLoadingMoreUpcoming || !_hasMoreUpcoming) return;
    _isLoadingMoreUpcoming = true;
    notifyListeners();

    try {
      _upcomingOffset += 10;
      final response = await _taskService.getAdminTaskList(
        email: _filterEmail,
        timeZone: _getDeviceTimezone(),
        previousOffset: _previousOffset,
        upcomingOffset: _upcomingOffset,
      );

      final existingIds = _upcomingTasks.map((t) => t.taskId).toSet();
      final newTasks = response.upcomingTasks
          .where((t) => !existingIds.contains(t.taskId))
          .toList();

      // Merge and sort ascending (earliest first)
      final merged = [..._upcomingTasks, ...newTasks];
      merged.sort((a, b) => a.openDatetime.compareTo(b.openDatetime));
      _upcomingTasks = merged;

      _hasMoreUpcoming = response.upcomingTasks.length >= 10;
    } catch (e) {
      _upcomingOffset -= 10;
    }

    _isLoadingMoreUpcoming = false;
    notifyListeners();
  }

  /// Admin complete a task.
  ///
  /// For expired tasks, the completion timestamp is set to the task's close
  /// time (not "now") so reward windows and history reflect when the task was
  /// actually due.
  Future<void> completeTask(String taskId) async {
    final task = _findTask(taskId);
    final overrideCompletedAt = (task != null && task.isExpired)
        ? _parseCloseDatetimeUtc(task.closeDatetime)
        : null;

    await _taskService.adminCompleteTask(
      taskId: taskId,
      timeZone: _getDeviceTimezone(),
      completedAt: overrideCompletedAt,
    );

    // Mirror the same timestamp locally so the UI matches what the server
    // stored.
    final localCompletedAt =
        (overrideCompletedAt ?? DateTime.now().toUtc()).toIso8601String();

    AdminTaskData markCompleted(AdminTaskData t) => AdminTaskData(
      taskId: t.taskId,
      userId: t.userId,
      username: t.username,
      taskType: t.taskType,
      openDatetime: t.openDatetime,
      closeDatetime: t.closeDatetime,
      rpttaskId: t.rpttaskId,
      rpttaskName: t.rpttaskName,
      rpttaskInfo: t.rpttaskInfo,
      note: t.note,
      attachments: t.attachments,
      completedAt: localCompletedAt,
      rpttaskType: t.rpttaskType,
      rpttaskList: t.rpttaskList,
      smallTaskId: t.smallTaskId,
      minInterval: t.minInterval,
      familyId: t.familyId,
      familyName: t.familyName,
    );

    _previousTasks = _previousTasks
        .map((t) => t.taskId == taskId ? markCompleted(t) : t)
        .toList();
    _upcomingTasks = _upcomingTasks
        .map((t) => t.taskId == taskId ? markCompleted(t) : t)
        .toList();
    notifyListeners();
  }

  AdminTaskData? _findTask(String taskId) {
    for (final t in _previousTasks) {
      if (t.taskId == taskId) return t;
    }
    for (final t in _upcomingTasks) {
      if (t.taskId == taskId) return t;
    }
    return null;
  }

  /// Backend stores close_datetime as `YYYY-MM-DD HH:MM:SS` in UTC with no
  /// timezone suffix. Append `Z` before parsing so it isn't interpreted as
  /// device-local.
  DateTime? _parseCloseDatetimeUtc(String raw) {
    try {
      var s = raw.replaceAll(' ', 'T');
      if (!s.endsWith('Z') && !s.contains('+')) s += 'Z';
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> uploadTaskAttachments({
    required String taskId,
    required List<File> files,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    await _taskService.uploadTaskAttachments(
      taskId: taskId,
      files: files,
      onSendProgress: onSendProgress,
    );
    await loadTasks(email: _filterEmail);
  }

  /// Admin delete a task
  Future<void> deleteTask(String taskId) async {
    await _taskService.adminDeleteTask(taskId);
    _previousTasks.removeWhere((t) => t.taskId == taskId);
    _upcomingTasks.removeWhere((t) => t.taskId == taskId);
    notifyListeners();
  }

  /// Set filter by email
  void setFilterEmail(String? email) {
    loadTasks(email: email);
  }

  /// Reset provider state
  void reset() {
    _state = AdminTasksState.initial;
    _previousTasks = [];
    _upcomingTasks = [];
    _memberChips = [];
    _filterEmail = null;
    _errorMessage = null;
    _previousOffset = 0;
    _upcomingOffset = 0;
    _isAdmin = false;
    notifyListeners();
  }
}
