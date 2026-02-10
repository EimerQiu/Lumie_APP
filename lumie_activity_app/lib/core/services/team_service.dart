/// Team Service - API client for team operations

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../shared/models/team_models.dart';
import '../../shared/models/subscription_error.dart';

class TeamService {
  // Singleton pattern
  static final TeamService _instance = TeamService._internal();
  factory TeamService() => _instance;
  TeamService._internal();

  String? _token;

  void setToken(String token) {
    _token = token;
    print('🔐 TeamService: Token set - ${token.substring(0, 20)}...');
  }

  void clearToken() {
    _token = null;
    print('🔐 TeamService: Token cleared');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Parse subscription error from 403 response
  SubscriptionErrorResponse? _parseSubscriptionError(dynamic responseBody) {
    try {
      if (responseBody is Map<String, dynamic> &&
          responseBody.containsKey('error')) {
        return SubscriptionErrorResponse.fromJson(responseBody);
      }
    } catch (e) {
      // Failed to parse subscription error
      return null;
    }
    return null;
  }

  /// Create a new team
  Future<Team> createTeam({required String name, String? description}) async {
    print('🔐 TeamService.createTeam: Token is ${_token == null ? 'NULL' : 'set (${_token!.substring(0, 20)}...)'}');
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/teams'),
        headers: _headers,
        body: json.encode({
          'name': name,
          'description': description,
        }),
      );

      if (response.statusCode == 201) {
        return Team.fromJson(json.decode(response.body));
      } else if (response.statusCode == 403) {
        final errorResponse = _parseSubscriptionError(json.decode(response.body));
        if (errorResponse != null && errorResponse.isSubscriptionError) {
          throw SubscriptionLimitException(errorResponse);
        }
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Permission denied');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to create team');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get all teams user belongs to
  Future<TeamsListResponse> getTeams() async {
    print('🔐 TeamService.getTeams: Token is ${_token == null ? 'NULL' : 'set (${_token!.substring(0, 20)}...)'}');
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/teams'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return TeamsListResponse.fromJson(json.decode(response.body));
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to get teams');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get team details
  Future<Team> getTeam(String teamId) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return Team.fromJson(json.decode(response.body));
      } else if (response.statusCode == 403) {
        throw Exception('You are not a member of this team');
      } else if (response.statusCode == 404) {
        throw Exception('Team not found');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to get team');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update team information (admin only)
  Future<Team> updateTeam({
    required String teamId,
    String? name,
    String? description,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId'),
        headers: _headers,
        body: json.encode({
          if (name != null) 'name': name,
          if (description != null) 'description': description,
        }),
      );

      if (response.statusCode == 200) {
        return Team.fromJson(json.decode(response.body));
      } else if (response.statusCode == 403) {
        throw Exception('Only admins can update team info');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to update team');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete team (admin only)
  Future<void> deleteTeam(String teamId) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 403) {
        throw Exception('Only admins can delete teams');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to delete team');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Invite member to team by email (admin only)
  Future<void> inviteMember({
    required String teamId,
    required String email,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId/invite'),
        headers: _headers,
        body: json.encode({'email': email}),
      );

      if (response.statusCode == 201) {
        return;
      } else if (response.statusCode == 403) {
        throw Exception('Only admins can invite members');
      } else if (response.statusCode == 404) {
        throw Exception('User not found. User must register first.');
      } else if (response.statusCode == 409) {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'User already invited or is a member');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to invite member');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Accept team invitation
  Future<void> acceptInvitation(String teamId) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId/accept'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 403) {
        // Check if subscription limit error
        final errorResponse = _parseSubscriptionError(json.decode(response.body));
        if (errorResponse != null && errorResponse.isSubscriptionError) {
          throw SubscriptionLimitException(errorResponse);
        }
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'No pending invitation found');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to accept invitation');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Leave team
  Future<void> leaveTeam(String teamId) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId/leave'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 403) {
        throw Exception('You are not a member of this team');
      } else if (response.statusCode == 409) {
        throw Exception(
            'Cannot leave as the only admin. Promote another member first or delete the team.');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to leave team');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Remove member from team (admin only)
  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId/members/$userId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 403) {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Only admins can remove members');
      } else if (response.statusCode == 404) {
        throw Exception('User is not a member of this team');
      } else if (response.statusCode == 409) {
        throw Exception('Cannot remove another admin');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to remove member');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get team members
  Future<TeamMembersResponse> getTeamMembers(String teamId) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId/members'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return TeamMembersResponse.fromJson(json.decode(response.body));
      } else if (response.statusCode == 403) {
        throw Exception('You are not a member of this team');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to get team members');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get pending invitations (admin only)
  Future<List<Map<String, dynamic>>> getPendingInvitations(String teamId) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId/invitations'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['pending_invitations']);
      } else if (response.statusCode == 403) {
        throw Exception('Only admins can view pending invitations');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to get pending invitations');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get shared data from all team members
  Future<Map<String, dynamic>> getSharedData(String teamId) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId/shared-data'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 403) {
        throw Exception('You are not a member of this team');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to get shared data');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get specific member's shared data
  Future<Map<String, dynamic>> getMemberData({
    required String teamId,
    required String userId,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/teams/$teamId/members/$userId/data'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 403) {
        throw Exception('You are not a member of this team');
      } else if (response.statusCode == 404) {
        throw Exception('User is not a member of this team');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to get member data');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get invitation details from token (public endpoint, no auth required)
  Future<Map<String, dynamic>> getInvitationFromToken(String token) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/teams/invitations/token/$token'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 400) {
        throw Exception('Invalid or expired invitation link');
      } else if (response.statusCode == 404) {
        throw Exception('Invitation not found or has been cancelled');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to get invitation details');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Accept invitation using token (requires authentication)
  Future<void> acceptInvitationByToken(String token) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/teams/invitations/token/$token/accept'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 400) {
        throw Exception('Invalid or expired invitation link');
      } else if (response.statusCode == 403) {
        final error = json.decode(response.body);
        // Check if it's a subscription limit error
        if (error['error'] != null && error['error']['code'] == 'SUBSCRIPTION_LIMIT_REACHED') {
          throw SubscriptionLimitException(
            SubscriptionErrorResponse.fromJson(error['error']),
          );
        }
        throw Exception(error['detail'] ?? 'This invitation was sent to a different email address');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to accept invitation');
      }
    } catch (e) {
      rethrow;
    }
  }
}

// Singleton instance
final teamService = TeamService();
