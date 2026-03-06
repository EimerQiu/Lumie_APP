/// Admin Tasks Provider - State management for admin dashboard
///
/// Manages global task view, member filtering, pagination,
/// and admin actions (complete/delete any member's task).

import 'package:flutter/foundation.dart';
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
  Future<void> loadMemberChips() async {
    try {
      final teamsResponse = await _teamService.getTeams();
      final adminTeams = teamsResponse.teams
          .where((t) => t.role == TeamRole.admin && t.status == MemberStatus.member)
          .toList();

      _isAdmin = adminTeams.isNotEmpty;

      if (!_isAdmin) {
        _memberChips = [];
        notifyListeners();
        return;
      }

      // Fetch members for each admin team
      final seenEmails = <String>{};
      final chips = <TeamMemberChip>[];

      for (final team in adminTeams) {
        final membersResponse = await _teamService.getTeamMembers(team.teamId);
        for (final member in membersResponse.members) {
          if (member.status == MemberStatus.member && !seenEmails.contains(member.email)) {
            seenEmails.add(member.email);
            chips.add(TeamMemberChip(
              userId: member.userId,
              name: member.name,
              email: member.email,
              teamId: team.teamId,
              teamName: team.name,
            ));
          }
        }
      }

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

  /// Admin complete a task
  Future<void> completeTask(String taskId) async {
    await _taskService.adminCompleteTask(
      taskId: taskId,
      timeZone: _getDeviceTimezone(),
    );
    // Update local state: change status to completed
    _previousTasks = _previousTasks.map((t) {
      if (t.taskId == taskId) {
        return AdminTaskData(
          taskId: t.taskId,
          userId: t.userId,
          username: t.username,
          taskType: t.taskType,
          openDatetime: t.openDatetime,
          closeDatetime: t.closeDatetime,
          status: 'completed',
          rpttaskId: t.rpttaskId,
          rpttaskName: t.rpttaskName,
          rpttaskInfo: t.rpttaskInfo,
          rpttaskType: t.rpttaskType,
          rpttaskList: t.rpttaskList,
          smallTaskId: t.smallTaskId,
          minInterval: t.minInterval,
          familyId: t.familyId,
          familyName: t.familyName,
        );
      }
      return t;
    }).toList();
    _upcomingTasks = _upcomingTasks.map((t) {
      if (t.taskId == taskId) {
        return AdminTaskData(
          taskId: t.taskId,
          userId: t.userId,
          username: t.username,
          taskType: t.taskType,
          openDatetime: t.openDatetime,
          closeDatetime: t.closeDatetime,
          status: 'completed',
          rpttaskId: t.rpttaskId,
          rpttaskName: t.rpttaskName,
          rpttaskInfo: t.rpttaskInfo,
          rpttaskType: t.rpttaskType,
          rpttaskList: t.rpttaskList,
          smallTaskId: t.smallTaskId,
          minInterval: t.minInterval,
          familyId: t.familyId,
          familyName: t.familyName,
        );
      }
      return t;
    }).toList();
    notifyListeners();
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
