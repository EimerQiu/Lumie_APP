/// Team and team member models

/// Helper: backend timestamps omit the 'Z' suffix – append it before parsing.
String _ensureUtcSuffix(String dateStr) {
  if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
    return '${dateStr}Z';
  }
  return dateStr;
}

enum TeamRole {
  admin,
  member;

  String get displayName {
    switch (this) {
      case TeamRole.admin:
        return 'Admin';
      case TeamRole.member:
        return 'Member';
    }
  }
}

enum MemberStatus {
  pending,
  member;

  String get displayName {
    switch (this) {
      case MemberStatus.pending:
        return 'Pending';
      case MemberStatus.member:
        return 'Active';
    }
  }
}

class Team {
  final String teamId;
  final String name;
  final String? description;
  final TeamRole role;
  final MemberStatus status;
  final int memberCount;
  final DateTime createdAt;
  final String createdBy;

  const Team({
    required this.teamId,
    required this.name,
    this.description,
    required this.role,
    required this.status,
    required this.memberCount,
    required this.createdAt,
    required this.createdBy,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      teamId: json['team_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      role: TeamRole.values.firstWhere((e) => e.name == json['role']),
      status: MemberStatus.values.firstWhere((e) => e.name == json['status']),
      memberCount: json['member_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'team_id': teamId,
      'name': name,
      'description': description,
      'role': role.name,
      'status': status.name,
      'member_count': memberCount,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
    };
  }
}

class TeamInvitation {
  final String teamId;
  final String teamName;
  final String invitedByName;
  final DateTime invitedAt;

  const TeamInvitation({
    required this.teamId,
    required this.teamName,
    required this.invitedByName,
    required this.invitedAt,
  });

  factory TeamInvitation.fromJson(Map<String, dynamic> json) {
    return TeamInvitation(
      teamId: json['team_id'] as String,
      teamName: json['team_name'] as String,
      invitedByName: json['invited_by_name'] as String,
      invitedAt: DateTime.parse(json['invited_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'team_id': teamId,
      'team_name': teamName,
      'invited_by_name': invitedByName,
      'invited_at': invitedAt.toIso8601String(),
    };
  }
}

class TeamsListResponse {
  final List<Team> teams;
  final List<TeamInvitation> pendingInvitations;

  const TeamsListResponse({
    required this.teams,
    required this.pendingInvitations,
  });

  factory TeamsListResponse.fromJson(Map<String, dynamic> json) {
    return TeamsListResponse(
      teams: (json['teams'] as List)
          .map((t) => Team.fromJson(t as Map<String, dynamic>))
          .toList(),
      pendingInvitations: (json['pending_invitations'] as List)
          .map((i) => TeamInvitation.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teams': teams.map((t) => t.toJson()).toList(),
      'pending_invitations': pendingInvitations.map((i) => i.toJson()).toList(),
    };
  }
}

class DataSharing {
  final bool profile;
  final bool activity;
  final bool sleep;
  final bool testResults;

  const DataSharing({
    required this.profile,
    required this.activity,
    required this.sleep,
    required this.testResults,
  });

  factory DataSharing.fromJson(Map<String, dynamic> json) {
    return DataSharing(
      profile: json['profile'] as bool,
      activity: json['activity'] as bool,
      sleep: json['sleep'] as bool,
      testResults: json['test_results'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile': profile,
      'activity': activity,
      'sleep': sleep,
      'test_results': testResults,
    };
  }

  /// Check if any data category is shared
  bool get hasSharedData => profile || activity || sleep || testResults;

  /// Count of shared categories
  int get sharedCount {
    int count = 0;
    if (profile) count++;
    if (activity) count++;
    if (sleep) count++;
    if (testResults) count++;
    return count;
  }
}

class TeamMember {
  final String userId;
  final String name;
  final String email;
  final TeamRole role;
  final MemberStatus status;
  final DateTime? joinedAt;
  final DataSharing dataSharing;

  const TeamMember({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.joinedAt,
    required this.dataSharing,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      userId: json['user_id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: TeamRole.values.firstWhere((e) => e.name == json['role']),
      status: MemberStatus.values.firstWhere((e) => e.name == json['status']),
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
      dataSharing: DataSharing.fromJson(json['data_sharing'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'email': email,
      'role': role.name,
      'status': status.name,
      'joined_at': joinedAt?.toIso8601String(),
      'data_sharing': dataSharing.toJson(),
    };
  }
}

class TeamMembersResponse {
  final String teamId;
  final List<TeamMember> members;
  final int totalMembers;

  const TeamMembersResponse({
    required this.teamId,
    required this.members,
    required this.totalMembers,
  });

  factory TeamMembersResponse.fromJson(Map<String, dynamic> json) {
    return TeamMembersResponse(
      teamId: json['team_id'] as String,
      members: (json['members'] as List)
          .map((m) => TeamMember.fromJson(m as Map<String, dynamic>))
          .toList(),
      totalMembers: json['total_members'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'team_id': teamId,
      'members': members.map((m) => m.toJson()).toList(),
      'total_members': totalMembers,
    };
  }
}

// ─── Team Feed (Dayprint) Models ─────────────────────────────────────────────

enum TeamFeedItemType {
  taskWithPhoto,
  taskText,
  sleepScore,
  meal;

  static TeamFeedItemType fromString(String value) {
    switch (value) {
      case 'task_with_photo':
        return TeamFeedItemType.taskWithPhoto;
      case 'sleep_score':
        return TeamFeedItemType.sleepScore;
      case 'meal':
        return TeamFeedItemType.meal;
      default:
        return TeamFeedItemType.taskText;
    }
  }
}

class FeedAttachment {
  final String url;
  final String? thumbnailUrl;

  const FeedAttachment({required this.url, this.thumbnailUrl});

  factory FeedAttachment.fromJson(Map<String, dynamic> json) {
    return FeedAttachment(
      url: json['url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }
}

class TeamFeedItem {
  final String itemId;
  final TeamFeedItemType type;
  final String memberUserId;
  final String memberName;
  final DateTime timestamp;
  // Task fields
  final String? taskName;
  final String? taskType;
  final List<FeedAttachment>? attachments;
  // Sleep fields
  final int? sleepScore;
  final double? sleepHours;
  // Meal fields (type=meal)
  final String? mealId;
  final String? foodPreview;
  final Map<String, dynamic>? macroRatio;

  const TeamFeedItem({
    required this.itemId,
    required this.type,
    required this.memberUserId,
    required this.memberName,
    required this.timestamp,
    this.taskName,
    this.taskType,
    this.attachments,
    this.sleepScore,
    this.sleepHours,
    this.mealId,
    this.foodPreview,
    this.macroRatio,
  });

  factory TeamFeedItem.fromJson(Map<String, dynamic> json) {
    return TeamFeedItem(
      itemId: json['item_id'] as String,
      type: TeamFeedItemType.fromString(json['type'] as String),
      memberUserId: json['member_user_id'] as String,
      memberName: json['member_name'] as String,
      timestamp: DateTime.parse(_ensureUtcSuffix(json['timestamp'] as String)),
      taskName: json['task_name'] as String?,
      taskType: json['task_type'] as String?,
      attachments: (json['attachments'] as List?)
          ?.map((a) => FeedAttachment.fromJson(a as Map<String, dynamic>))
          .toList(),
      sleepScore: json['sleep_score'] as int?,
      sleepHours: (json['sleep_hours'] as num?)?.toDouble(),
      mealId: json['meal_id'] as String?,
      foodPreview: json['food_preview'] as String?,
      macroRatio: (json['macro_ratio'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

class TeamFeedResponse {
  final List<TeamFeedItem> items;
  final bool hasMore;
  final String? nextBefore;

  const TeamFeedResponse({
    required this.items,
    required this.hasMore,
    this.nextBefore,
  });

  factory TeamFeedResponse.fromJson(Map<String, dynamic> json) {
    return TeamFeedResponse(
      items: (json['items'] as List)
          .map((i) => TeamFeedItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool,
      nextBefore: json['next_before'] as String?,
    );
  }
}
