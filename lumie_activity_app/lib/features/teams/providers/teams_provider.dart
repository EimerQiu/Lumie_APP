// Teams Provider - State management for teams feature

import 'package:flutter/foundation.dart';
import '../../../core/services/team_service.dart';
import '../../../shared/models/team_models.dart';
import '../../../shared/models/user_models.dart';

enum TeamsState {
  initial,
  loading,
  loaded,
  error,
}

class TeamsProvider extends ChangeNotifier {
  final TeamService _teamService = TeamService();

  TeamsState _state = TeamsState.initial;
  List<Team> _teams = [];
  List<TeamInvitation> _pendingInvitations = [];
  String? _errorMessage;
  SubscriptionTier _userTier = SubscriptionTier.free;

  // Getters
  TeamsState get state => _state;
  List<Team> get teams => _teams;
  List<TeamInvitation> get pendingInvitations => _pendingInvitations;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == TeamsState.loading;
  bool get hasError => _state == TeamsState.error;

  /// Set user's subscription tier
  void setUserTier(SubscriptionTier tier) {
    _userTier = tier;
    notifyListeners();
  }

  /// Check if user can create more teams
  bool get canCreateTeam {
    if (_userTier == SubscriptionTier.free) {
      return _teams.length < 1;
    }
    // Pro users (monthly and annual) can create up to 100 teams
    return _teams.length < 100;
  }

  /// Check if user has reached team limit
  bool get hasReachedTeamLimit {
    if (_userTier == SubscriptionTier.free) {
      return _teams.length >= 1;
    }
    // Pro users: check against 100 team limit
    return _teams.length >= 100;
  }

  /// Get team limit text for UI display
  String get teamLimitText {
    if (_userTier == SubscriptionTier.free) {
      return '${_teams.length}/1 team';
    }
    return '${_teams.length}/100 teams';
  }

  /// Get banner message for subscription status
  String? get subscriptionBannerMessage {
    if (_userTier == SubscriptionTier.free) {
      if (_teams.isEmpty) {
        return 'Free: 1 team available';
      } else if (_teams.isNotEmpty) {
        return 'Team limit reached (1/1). Upgrade to Pro for up to 100 teams';
      }
    } else {
      // Pro user
      if (_teams.length >= 100) {
        return 'Team limit reached (100/100 teams)';
      }
    }
    return null;
  }

  /// Load all teams and pending invitations
  Future<void> loadTeams() async {
    _state = TeamsState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _teamService.getTeams();
      _teams = response.teams;
      _pendingInvitations = response.pendingInvitations;
      _state = TeamsState.loaded;
    } catch (e) {
      _state = TeamsState.error;
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  /// Create a new team
  Future<Team> createTeam({
    required String name,
    String? description,
  }) async {
    final team = await _teamService.createTeam(
      name: name,
      description: description,
    );

    // Refresh teams list
    await loadTeams();

    return team;
  }

  /// Accept a team invitation
  Future<void> acceptInvitation(String teamId) async {
    await _teamService.acceptInvitation(teamId);
    await loadTeams();
  }

  /// Decline/ignore a team invitation
  Future<void> declineInvitation(String teamId) async {
    // For now, just remove from pending list
    // In production, might want to track declined invitations
    _pendingInvitations.removeWhere((inv) => inv.teamId == teamId);
    notifyListeners();
  }

  /// Leave a team
  Future<void> leaveTeam(String teamId) async {
    await _teamService.leaveTeam(teamId);
    await loadTeams();
  }

  /// Update team information (admin only)
  Future<void> updateTeam({
    required String teamId,
    String? name,
    String? description,
  }) async {
    await _teamService.updateTeam(
      teamId: teamId,
      name: name,
      description: description,
    );
    await loadTeams();
  }

  /// Delete team (admin only)
  Future<void> deleteTeam(String teamId) async {
    await _teamService.deleteTeam(teamId);
    await loadTeams();
  }

  /// Invite member to team (admin only)
  Future<void> inviteMember({
    required String teamId,
    required String email,
  }) async {
    await _teamService.inviteMember(teamId: teamId, email: email);
  }

  /// Remove member from team (admin only)
  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async {
    await _teamService.removeMember(teamId: teamId, userId: userId);
  }

  /// Get team members
  Future<TeamMembersResponse> getTeamMembers(String teamId) async {
    return await _teamService.getTeamMembers(teamId);
  }

  /// Get pending invitations for a team (admin only)
  Future<List<Map<String, dynamic>>> getPendingInvitations(String teamId) async {
    return await _teamService.getPendingInvitations(teamId);
  }

  /// Get shared data from all team members
  Future<Map<String, dynamic>> getSharedData(String teamId) async {
    return await _teamService.getSharedData(teamId);
  }

  /// Get specific member's shared data
  Future<Map<String, dynamic>> getMemberData({
    required String teamId,
    required String userId,
  }) async {
    return await _teamService.getMemberData(
      teamId: teamId,
      userId: userId,
    );
  }

  /// Find team by ID in current list
  Team? findTeamById(String teamId) {
    try {
      return _teams.firstWhere((team) => team.teamId == teamId);
    } catch (e) {
      return null;
    }
  }

  /// Get invitation details from token (for email links)
  Future<Map<String, dynamic>> getInvitationFromToken(String token) async {
    try {
      return await _teamService.getInvitationFromToken(token);
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Accept invitation using token (for logged-in users)
  Future<void> acceptInvitationByToken(String token) async {
    try {
      await _teamService.acceptInvitationByToken(token);
      // Reload teams to show the newly joined team
      await loadTeams();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset provider state
  void reset() {
    _state = TeamsState.initial;
    _teams = [];
    _pendingInvitations = [];
    _errorMessage = null;
    _userTier = SubscriptionTier.free;
    notifyListeners();
  }
}
