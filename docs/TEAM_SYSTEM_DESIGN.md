# Team System (Family System) - Technical Design Document

## Table of Contents
1. [Feature Overview](#1-feature-overview)
2. [Data Structure Design](#2-data-structure-design)
3. [API Endpoints Design](#3-api-endpoints-design)
4. [Screen/Page Design](#4-screenpage-design)
5. [System Architecture](#5-system-architecture)
6. [Integration Points](#6-integration-points)
7. [Implementation Priority](#7-implementation-priority)
8. [Security & Privacy](#8-security--privacy)

---

## 1. Feature Overview

### 1.1 Purpose

The Team System allows teens and parents to form **private teams** for shared support, coordination, and encouragement around health-related routines and daily responsibilities.

**Key Principles:**
- Privacy-first design (all sharing is opt-in)
- Teen autonomy and consent-driven
- Role-based access control
- Foundation for Med-Reminder coordination
- Subscription-gated (requires paid plan)

### 1.2 Core Capabilities

- Create and manage private teams
- Invite members by email
- Accept/decline invitations
- View team members and shared data
- Control data visibility through Settings
- Remove members or leave teams
- Admin vs member role distinction

### 1.3 Key Requirements from PRD

- Users can belong to multiple teams
- **Free users can create/join 1 team maximum**
- **Paid users (Monthly/Annual) can create/join unlimited teams**
- Pending members have zero access to team data
- Admins cannot override privacy settings
- Team membership alone never implies data access

---

## 2. Data Structure Design

### 2.1 Core Models

#### Team Model (Python/Pydantic)

```python
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field
from enum import Enum

class Team(BaseModel):
    """Team/Family group model"""
    team_id: str = Field(..., description="Unique team identifier")
    name: str = Field(..., min_length=1, max_length=100, description="Team name")
    description: Optional[str] = Field(None, max_length=500, description="Team description")
    created_by: str = Field(..., description="User ID of team creator")
    created_at: datetime = Field(..., description="Team creation timestamp")
    updated_at: datetime = Field(..., description="Last update timestamp")
    is_deleted: bool = Field(default=False, description="Soft delete flag")
    deleted_at: Optional[datetime] = Field(None, description="Deletion timestamp")

class TeamRole(str, Enum):
    """Team member roles"""
    ADMIN = "admin"  # Can manage team and invitations
    MEMBER = "member"  # Regular team participant

class MemberStatus(str, Enum):
    """Team member status"""
    PENDING = "pending"  # Invitation sent, not yet accepted
    MEMBER = "member"   # Active team participant

class TeamMember(BaseModel):
    """Team membership model"""
    team_id: str = Field(..., description="Team identifier")
    user_id: str = Field(..., description="User identifier")
    role: TeamRole = Field(..., description="Member role (admin/member)")
    status: MemberStatus = Field(..., description="Member status (pending/member)")
    invited_by: str = Field(..., description="User ID who sent invitation")
    invited_at: datetime = Field(..., description="Invitation timestamp")
    joined_at: Optional[datetime] = Field(None, description="Acceptance timestamp")
```

#### Request/Response Models

```python
class TeamCreate(BaseModel):
    """Request model for creating a team"""
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)

class TeamUpdate(BaseModel):
    """Request model for updating a team"""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)

class TeamInvite(BaseModel):
    """Request model for inviting a member"""
    email: str = Field(..., description="Email of user to invite")

class TeamResponse(BaseModel):
    """Response model for team data"""
    team_id: str
    name: str
    description: Optional[str]
    role: TeamRole
    status: MemberStatus
    member_count: int
    created_at: datetime
    created_by: str

class TeamMemberResponse(BaseModel):
    """Response model for team member data"""
    user_id: str
    name: str
    email: str
    role: TeamRole
    status: MemberStatus
    joined_at: Optional[datetime]
    data_sharing: dict  # Based on user's privacy settings

class TeamSharedData(BaseModel):
    """Response model for team shared data"""
    user_id: str
    name: str
    role: TeamRole
    data: dict  # Contains profile, activity, sleep, test_results
```

#### Flutter/Dart Models

```dart
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
}
```

### 2.2 Database Schema (MongoDB)

#### teams Collection

```javascript
{
  _id: ObjectId,
  team_id: "team_uuid_123",
  name: "Smith Family",
  description: "Our family support team",
  created_by: "user_uuid_456",
  created_at: ISODate("2026-02-05T00:00:00Z"),
  updated_at: ISODate("2026-02-05T00:00:00Z"),
  is_deleted: false,
  deleted_at: null
}

// Indexes
db.teams.createIndex({ team_id: 1 }, { unique: true })
db.teams.createIndex({ created_by: 1 })
db.teams.createIndex({ is_deleted: 1 })
```

#### team_members Collection

```javascript
{
  _id: ObjectId,
  team_id: "team_uuid_123",
  user_id: "user_uuid_789",
  role: "member",  // "admin" | "member"
  status: "member",  // "pending" | "member"
  invited_by: "user_uuid_456",
  invited_at: ISODate("2026-02-05T00:00:00Z"),
  joined_at: ISODate("2026-02-05T01:00:00Z")
}

// Indexes
db.team_members.createIndex({ team_id: 1, user_id: 1 }, { unique: true })
db.team_members.createIndex({ user_id: 1, status: 1 })
db.team_members.createIndex({ team_id: 1, status: 1 })
db.team_members.createIndex({ invited_at: 1 })
```

---

## 3. API Endpoints Design

### 3.1 Team Management Endpoints

#### **POST /api/teams** - Create a new team

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User profile must be complete
- ✓ Team name must be non-empty (1-100 chars)
- **Subscription-based limits:**
  - ✓ Free users: Can create 1 team maximum (check current team count)
  - ✓ Paid users: Can create unlimited teams
  - ✗ Reject if Free user already has 1 team

**Request Body:**
```json
{
  "name": "Smith Family",
  "description": "Our family support team"
}
```

**Response:** `201 Created`
```json
{
  "team_id": "team_123",
  "name": "Smith Family",
  "description": "Our family support team",
  "role": "admin",
  "status": "member",
  "member_count": 1,
  "created_at": "2026-02-05T00:00:00Z",
  "created_by": "user_456"
}
```

**Error Responses:**
- `401 Unauthorized` - Not authenticated
- `403 Forbidden` - Free user already has 1 team (team limit reached)
- `400 Bad Request` - Invalid team name

**Business Logic:**
```python
async def create_team(user_id: str, data: TeamCreate):
    user = await get_user(user_id)

    # Check team limit based on subscription
    current_team_count = await get_user_team_count(user_id)

    if user.subscription.tier == SubscriptionTier.FREE:
        if current_team_count >= 1:
            raise HTTPException(
                status_code=403,
                detail="Free users can create 1 team maximum. Upgrade to create more teams."
            )

    # Paid users have no limit
    # Continue with team creation...
```

---

#### **GET /api/teams** - Get all teams user belongs to

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ All subscription tiers can access (Free users see their 1 team, Paid users see all)

**Query Parameters:**
- `?status=member|pending` - Optional: filter by member status
- `?role=admin|member` - Optional: filter by role

**Response:** `200 OK`
```json
{
  "teams": [
    {
      "team_id": "team_123",
      "name": "Smith Family",
      "role": "admin",
      "status": "member",
      "member_count": 4,
      "created_at": "2026-02-05T00:00:00Z"
    }
  ],
  "pending_invitations": [
    {
      "team_id": "team_456",
      "name": "Johnson Family",
      "invited_by": "John Johnson",
      "invited_at": "2026-02-04T12:00:00Z"
    }
  ]
}
```

---

#### **GET /api/teams/{team_id}** - Get team details

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must be a member of the team (status='member')
- ✗ Pending invitations do not grant access
- ✓ Works for all subscription tiers

**Response:** `200 OK`
```json
{
  "team_id": "team_123",
  "name": "Smith Family",
  "description": "Our family support team",
  "role": "admin",
  "member_count": 4,
  "created_at": "2026-02-05T00:00:00Z",
  "created_by": "user_456",
  "admins": [
    {
      "user_id": "user_456",
      "name": "John Smith"
    }
  ]
}
```

**Error Responses:**
- `403 Forbidden` - Not a team member
- `404 Not Found` - Team doesn't exist

---

#### **PUT /api/teams/{team_id}** - Update team info (Admin only)

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must be a team member (status='member')
- ✓ User must be an admin (role='admin')
- ✗ Regular members cannot update team info
- ✓ Works for all subscription tiers

**Request Body:**
```json
{
  "name": "Updated Team Name",
  "description": "Updated description"
}
```

**Response:** `200 OK` with updated Team object

**Error Responses:**
- `403 Forbidden` - Not an admin
- `400 Bad Request` - Invalid data

---

#### **DELETE /api/teams/{team_id}** - Delete team (Admin only)

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must be an admin of the team
- ✓ Confirmation required (pass `?confirm=true`)
- ✓ Works for all subscription tiers

**Business Logic:**
- Soft delete (mark as deleted, keep data for 30 days)
- Remove all team_members entries
- Cancel all pending invitations
- Notify all members via email

**Response:** `200 OK`
```json
{
  "message": "Team deleted successfully",
  "deleted_at": "2026-02-05T10:00:00Z",
  "recovery_deadline": "2026-03-07T10:00:00Z"
}
```

**Error Responses:**
- `403 Forbidden` - Not an admin
- `400 Bad Request` - Missing confirmation

---

### 3.2 Member Management Endpoints

#### **POST /api/teams/{team_id}/invite** - Invite member by email

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must be a team admin (role='admin')
- ✓ Team must exist and not be deleted
- ✓ Invited email must be a registered Lumie user
- ✗ Cannot invite users already in the team
- ✗ Cannot re-invite pending invitations
- **Invited user team limit check:**
  - ✓ If invited user has Free subscription: Check if they already have 1 team
  - ✓ If invited user has Paid subscription: No limit
  - ✗ Reject if Free user already has 1 team

**Request Body:**
```json
{
  "email": "newmember@example.com"
}
```

**Response:** `201 Created`
```json
{
  "team_id": "team_123",
  "invited_user": {
    "user_id": "user_789",
    "email": "newmember@example.com",
    "name": "Jane Doe"
  },
  "status": "pending",
  "invited_at": "2026-02-05T10:00:00Z"
}
```

**Error Responses:**
- `403 Forbidden` - Not an admin OR invited user has reached team limit (Free user already has 1 team)
- `404 Not Found` - Email not registered
- `409 Conflict` - User already in team or has pending invitation

**Business Logic:**
```python
async def invite_member(team_id: str, inviter_user_id: str, email: str):
    # Verify inviter is admin
    inviter_member = await get_team_member(team_id, inviter_user_id)
    if inviter_member.role != TeamRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admins can invite members")

    # Find invited user
    invited_user = await get_user_by_email(email)
    if not invited_user:
        raise HTTPException(status_code=404, detail="User not found")

    # Check invited user's team limit
    invited_user_team_count = await get_user_team_count(invited_user.user_id)

    if invited_user.subscription.tier == SubscriptionTier.FREE:
        if invited_user_team_count >= 1:
            raise HTTPException(
                status_code=403,
                detail=f"{invited_user.name} has reached their team limit (1 team max for Free users). They must upgrade to join more teams."
            )

    # Continue with invitation...
```

---

#### **POST /api/teams/{team_id}/accept** - Accept invitation

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must have a pending invitation to this team
- ✓ Invitation must not be expired (30-day limit)
- ✗ Cannot accept if already a member
- **Team limit check:**
  - ✓ Free users: Can accept only if current team count < 1
  - ✓ Paid users: Can accept unlimited invitations
  - ✗ Reject if Free user already has 1 team

**Business Logic:**
- Update team_member status: pending → member
- Set joined_at timestamp
- Set role to 'member'
- Send notification to team admins

**Response:** `200 OK`
```json
{
  "team_id": "team_123",
  "status": "member",
  "role": "member",
  "joined_at": "2026-02-05T10:00:00Z",
  "team": {
    "name": "Smith Family",
    "member_count": 5
  }
}
```

**Error Responses:**
- `403 Forbidden` - No pending invitation OR team limit reached (Free user already has 1 team)
- `404 Not Found` - Team or invitation doesn't exist
- `410 Gone` - Invitation expired

**Business Logic:**
```python
async def accept_invitation(team_id: str, user_id: str):
    user = await get_user(user_id)

    # Check team limit before accepting
    current_team_count = await get_user_team_count(user_id)

    if user.subscription.tier == SubscriptionTier.FREE:
        if current_team_count >= 1:
            raise HTTPException(
                status_code=403,
                detail="You have reached your team limit (1 team max for Free users). Upgrade to join more teams."
            )

    # Update status: pending → member
    await update_team_member(
        team_id=team_id,
        user_id=user_id,
        status=MemberStatus.MEMBER,
        joined_at=datetime.utcnow()
    )

    # Send notification to admins...
```

---

#### **POST /api/teams/{team_id}/leave** - Leave team

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must be a team member (status='member')
- ✗ Cannot leave if you're the only admin (must promote another member first)
- ✓ Confirmation required (pass `?confirm=true`)

**Business Logic:**
- Remove user's team_member record
- Revoke access to all team data immediately
- Notify team admins
- If last admin: prevent or force promote another member

**Response:** `200 OK`
```json
{
  "message": "Successfully left the team",
  "team_name": "Smith Family",
  "left_at": "2026-02-05T10:00:00Z"
}
```

**Error Responses:**
- `403 Forbidden` - Not a team member
- `409 Conflict` - Last admin (must promote someone first)
- `400 Bad Request` - Missing confirmation

---

#### **DELETE /api/teams/{team_id}/members/{user_id}** - Remove member (Admin only)

**Authorization Conditions:**
- ✓ User (requester) must be authenticated
- ✓ User (requester) must be a team admin
- ✓ Target user must be a team member
- ✗ Cannot remove yourself (use /leave instead)
- ✗ Cannot remove another admin (must demote first)

**Business Logic:**
- Remove target user's team_member record
- Revoke target user's access immediately
- Send notification to removed user
- Send notification to other admins

**Response:** `200 OK`
```json
{
  "message": "Member removed successfully",
  "removed_user": {
    "user_id": "user_789",
    "name": "Jane Doe"
  },
  "removed_at": "2026-02-05T10:00:00Z"
}
```

**Error Responses:**
- `403 Forbidden` - Not an admin or trying to remove yourself
- `404 Not Found` - Target user not in team
- `409 Conflict` - Cannot remove another admin

---

#### **GET /api/teams/{team_id}/members** - Get all members

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must be a team member (status='member')
- ✗ Pending invitations cannot see member list
- ✓ Works for all subscription tiers

**Query Parameters:**
- `?status=member|pending` - Optional: filter by status
- `?role=admin|member` - Optional: filter by role

**Response:** `200 OK`
```json
{
  "team_id": "team_123",
  "members": [
    {
      "user_id": "user_456",
      "name": "John Smith",
      "role": "admin",
      "status": "member",
      "joined_at": "2026-01-01T00:00:00Z",
      "data_sharing": {
        "profile": true,
        "activity": true,
        "sleep": false,
        "test_results": false
      }
    },
    {
      "user_id": "user_789",
      "name": "Jane Doe",
      "role": "member",
      "status": "member",
      "joined_at": "2026-02-05T10:00:00Z",
      "data_sharing": {
        "profile": true,
        "activity": false,
        "sleep": false,
        "test_results": false
      }
    }
  ],
  "total_members": 2
}
```

**Error Responses:**
- `403 Forbidden` - Not a team member

---

#### **GET /api/teams/{team_id}/invitations** - Get pending invitations (Admin only)

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must be a team admin
- ✗ Regular members cannot view pending invitations
- ✓ Works for all subscription tiers

**Response:** `200 OK`
```json
{
  "team_id": "team_123",
  "pending_invitations": [
    {
      "user_id": "user_999",
      "email": "pending@example.com",
      "name": "Bob Johnson",
      "invited_by": {
        "user_id": "user_456",
        "name": "John Smith"
      },
      "invited_at": "2026-02-04T12:00:00Z",
      "days_pending": 1
    }
  ],
  "total_pending": 1
}
```

**Error Responses:**
- `403 Forbidden` - Not an admin

---

### 3.3 Team Data Views Endpoints

#### **GET /api/teams/{team_id}/shared-data** - Get all shared data from team members

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User must be a team member (status='member')
- ✗ Pending invitations have zero access
- ✓ Works for all subscription tiers

**Business Logic:**
- For each team member:
  1. Check their Settings.familySharing preferences
  2. Return ONLY data categories they've enabled
  3. Display "Not shared" for disabled categories
- Never return data from pending members
- Respects individual privacy settings
- Admins cannot override privacy settings

**Response:** `200 OK`
```json
{
  "team_id": "team_123",
  "shared_data": [
    {
      "user_id": "user_456",
      "name": "John Smith",
      "role": "admin",
      "data": {
        "profile": {
          "shared": true,
          "age": 45,
          "role": "parent"
        },
        "activity": {
          "shared": true,
          "today_steps": 8500,
          "today_6mwt": 520
        },
        "sleep": {
          "shared": false,
          "message": "Not shared"
        },
        "test_results": {
          "shared": true,
          "recent_tests": []
        }
      }
    }
  ]
}
```

**Error Responses:**
- `403 Forbidden` - Not a team member

---

#### **GET /api/teams/{team_id}/members/{user_id}/data** - Get specific member's shared data

**Authorization Conditions:**
- ✓ Requester must be authenticated
- ✓ Requester must be a team member (status='member')
- ✓ Target user must be a team member (status='member')
- ✗ Cannot access pending members' data
- ✓ Works for all subscription tiers
- ✓ Target user's privacy settings control what's returned

**Response:** `200 OK`
```json
{
  "user_id": "user_789",
  "name": "Jane Doe",
  "role": "member",
  "data_sharing": {
    "profile": {
      "shared": true,
      "name": "Jane Doe",
      "age": 16,
      "role": "teen"
    },
    "activity": {
      "shared": true,
      "recent_activity": [
        {
          "date": "2026-02-05",
          "steps": 7200,
          "6mwt_distance": 480
        }
      ]
    },
    "sleep": {
      "shared": false
    },
    "test_results": {
      "shared": false
    }
  }
}
```

**Error Responses:**
- `403 Forbidden` - Not a team member or target is pending
- `404 Not Found` - Target user not in team

---

## 4. Screen/Page Design

### 4.1 Navigation Structure

```
Settings
  └── Teams (NEW)
      ├── Team List
      ├── Create Team
      ├── Team Detail
      │   ├── Member List
      │   ├── Shared Data View
      │   └── Invite Member
      └── Pending Invitations
```

### 4.2 Team List Screen

**Path:** `/teams` or accessible from Settings

**Purpose:** Display all teams user belongs to and pending invitations

**UI Elements:**
- **Header:** "My Teams"
- **Subscription Status Banner:**
  - If Free tier and has 1 team: Show "Team limit reached (1/1). Upgrade to join more teams"
  - If Free tier and has 0 teams: Show "Free plan: 1 team available"
  - If Paid tier: Show "Unlimited teams"
- **Active Teams Section:**
  - List of teams (card layout)
  - Each card shows:
    - Team name
    - Member count
    - Role badge (Admin/Member)
    - Last activity timestamp
  - Tap card → Navigate to Team Detail
- **Pending Invitations Section:**
  - Separate section with badge count
  - Each invitation shows:
    - Team name
    - Inviter name
    - "Accept" and "Ignore" buttons
- **Floating Action Button:** "+" to Create Team

**API Calls:**
- `GET /api/teams` (on load)

**State Management:**
```dart
class TeamsProvider extends ChangeNotifier {
  List<Team> _teams = [];
  List<TeamInvitation> _pendingInvitations = [];
  bool _isLoading = false;

  Future<void> loadTeams() async {
    _isLoading = true;
    notifyListeners();

    final response = await teamService.getTeams();
    _teams = response.teams;
    _pendingInvitations = response.pendingInvitations;

    _isLoading = false;
    notifyListeners();
  }

  Future<void> acceptInvitation(String teamId) async {
    await teamService.acceptInvitation(teamId);
    await loadTeams();
  }
}
```

---

### 4.3 Create Team Screen

**Path:** `/teams/create`

**Purpose:** Create a new team

**UI Elements:**
- **Header:** "Create Team"
- **Form Fields:**
  - Team Name (required, max 100 chars)
  - Description (optional, max 500 chars)
- **Validation:**
  - Show character count
  - Disable submit if name is empty
- **Submit Button:** "Create Team"
- **Cancel Button:** Go back to Team List

**API Calls:**
- `POST /api/teams`

**Flow:**
1. User fills form
2. Tap "Create Team"
3. Show loading indicator
4. On success: Navigate to Team Detail Screen for new team
5. On error: Show error message (subscription check, etc.)

---

### 4.4 Team Detail Screen

**Path:** `/teams/{team_id}`

**Purpose:** View team members, shared data, and manage team (if admin)

**UI Elements:**

**Header Section:**
- Team name and description
- Member count
- Edit button (admin only)

**Tabs:**
1. **Members Tab:**
   - List of all team members
   - Each member card shows:
     - Avatar (placeholder)
     - Name
     - Role badge
     - Data sharing status icons (✓/✗)
     - Tap card → View member's shared data
   - Admin-only actions:
     - "Invite Member" button at top
     - Remove button on each member card (except self)
   - Pending invitations section (admin only)

2. **Shared Data Tab:**
   - Grid view of all members' shared data
   - Categories: Profile, Activity, Sleep, Test Results
   - Each cell shows:
     - "✓ Shared" with summary
     - "Not shared" if disabled
   - Tap cell → View detailed data

**Bottom Actions:**
- Admin: "Delete Team" (destructive)
- Member: "Leave Team" (destructive)

**API Calls:**
- `GET /api/teams/{team_id}` (on load)
- `GET /api/teams/{team_id}/members` (on load)
- `GET /api/teams/{team_id}/shared-data` (on load)
- `DELETE /api/teams/{team_id}/members/{user_id}` (remove member)
- `POST /api/teams/{team_id}/leave` (leave team)

---

### 4.5 Invite Member Screen

**Path:** `/teams/{team_id}/invite`

**Purpose:** Invite new members to the team (Admin only)

**UI Elements:**
- **Header:** "Invite Member"
- **Email Input:**
  - Email field with validation
  - Helper text: "Enter a Lumie user's email"
- **Submit Button:** "Send Invitation"
- **Pending Invitations List:**
  - Show all pending invitations
  - Each shows: name, email, days pending
  - Option to cancel invitation (future)

**API Calls:**
- `POST /api/teams/{team_id}/invite`
- `GET /api/teams/{team_id}/invitations`

**Validation:**
- Check valid email format
- Show error if user not found
- Show error if user has Free subscription
- Show error if already in team

---

### 4.6 Member Shared Data Screen

**Path:** `/teams/{team_id}/members/{user_id}/data`

**Purpose:** View detailed shared data for a specific team member

**UI Elements:**
- **Header:** Member name
- **Data Categories (Conditional Display):**

  **Profile Section (if shared):**
  - Age
  - Role (Teen/Parent)
  - Join date

  **Activity Section (if shared):**
  - Recent steps
  - Recent 6MWT results
  - Activity chart (last 7 days)

  **Sleep Section (if shared):**
  - Recent sleep duration
  - Sleep quality
  - Sleep chart (last 7 days)

  **Test Results Section (if shared):**
  - Recent test entries
  - Test trend chart

- **Not Shared Message:**
  - For each category not shared, show:
    - Icon with lock symbol
    - "This data is not shared"
    - Helper text: "Member can enable sharing in Settings"

**API Calls:**
- `GET /api/teams/{team_id}/members/{user_id}/data`

---

### 4.7 Accept Invitation Dialog

**Purpose:** Accept or ignore team invitation

**UI Elements:**
- Modal or bottom sheet
- Team name
- Inviter name and avatar
- Member count
- "Accept" button (primary)
- "Ignore" button (secondary)
- "View Team Details" link (optional, shows public info)

**API Calls:**
- `POST /api/teams/{team_id}/accept`

**Flow:**
1. User taps "Accept"
2. Show loading
3. On success:
   - Show success message
   - Navigate to Team Detail Screen
   - Refresh Team List
4. On error: Show error message

---

## 5. System Architecture

### 5.1 Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    TEAM/FAMILY SYSTEM ARCHITECTURE               │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│    User      │         │     Team     │         │   Settings   │
│  (Profile)   │         │              │         │  (Privacy)   │
├──────────────┤         ├──────────────┤         ├──────────────┤
│ user_id      │◄───────►│ team_id      │         │ user_id      │
│ email        │         │ name         │         │ familySharing│
│ name         │         │ created_by   │         │ - profile    │
│ subscription │         │ created_at   │         │ - activity   │
│ role         │         └──────────────┘         │ - tests      │
└──────────────┘                │                 │ - sleep      │
       │                        │                 └──────────────┘
       │                        │                        │
       │                        ▼                        │
       │              ┌──────────────────┐              │
       │              │  TeamMember      │              │
       │              ├──────────────────┤              │
       └─────────────►│ team_id          │              │
                      │ user_id          │◄─────────────┘
                      │ role (admin/mem) │
                      │ status (pend/mem)│
                      │ invited_by       │
                      │ joined_at        │
                      └──────────────────┘
                               │
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        DATA VISIBILITY FLOW                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. User A belongs to Team X (status: member)                   │
│  2. User B belongs to Team X (status: member)                   │
│  3. User B enables "activity sharing" in Settings               │
│  4. User A views Team X                                         │
│  5. System checks User B's privacy settings                     │
│  6. System returns ONLY shared data categories                  │
│  7. Display: "User B - Activity: ✓ | Sleep: Not shared"        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      INVITATION FLOW                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────┐   POST /teams/{id}/invite    ┌──────────────┐         │
│  │Admin├───────────────────────────────►│TeamMember   │         │
│  └─────┘    (email: user@email.com)    │status:pending│         │
│                                         └──────────────┘         │
│                                                │                 │
│                                                │ Email sent      │
│                                                ▼                 │
│  ┌──────┐  POST /teams/{id}/accept    ┌──────────────┐         │
│  │Invitee├───────────────────────────►│TeamMember    │         │
│  └──────┘                              │status:member │         │
│                                        │joined_at: now│         │
│                                        └──────────────┘         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Authorization Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     AUTHORIZATION LAYERS                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Layer 1: Authentication                                         │
│  ├─ JWT token validation                                        │
│  ├─ User session check                                          │
│  └─ Return user_id                                              │
│                                                                  │
│  Layer 2: Subscription & Team Limit Check                       │
│  ├─ Load user's subscription tier                               │
│  ├─ If creating/joining team:                                   │
│  │   ├─ Free tier: Check current team count < 1                 │
│  │   ├─ Paid tier: No limit                                     │
│  │   └─ Reject if Free tier already has 1 team                  │
│  └─ For other operations: All tiers allowed                     │
│                                                                  │
│  Layer 3: Team Membership Check                                 │
│  ├─ Load user's team_member record                              │
│  ├─ Check: status == 'member'                                   │
│  └─ Reject if not member or pending                             │
│                                                                  │
│  Layer 4: Role Check (for admin operations)                     │
│  ├─ Load user's team role                                       │
│  ├─ Check: role == 'admin'                                      │
│  └─ Reject if not admin                                         │
│                                                                  │
│  Layer 5: Privacy Check (for data access)                       │
│  ├─ Load target user's Settings                                 │
│  ├─ Check: familySharing.{category} == true                     │
│  └─ Return only shared categories                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 Service Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      BACKEND SERVICE LAYERS                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  API Routes Layer (FastAPI)                                     │
│  └─ /api/teams/*                                                │
│      ├─ Request validation (Pydantic)                           │
│      ├─ Authentication middleware                               │
│      └─ Call service layer                                      │
│                                                                  │
│  Service Layer                                                  │
│  └─ TeamService                                                 │
│      ├─ create_team()                                           │
│      ├─ get_user_teams()                                        │
│      ├─ invite_member()                                         │
│      ├─ accept_invitation()                                     │
│      ├─ get_team_members()                                      │
│      ├─ get_shared_data()                                       │
│      └─ Authorization checks                                    │
│                                                                  │
│  Data Access Layer                                              │
│  └─ Database (MongoDB)                                          │
│      ├─ teams collection                                        │
│      ├─ team_members collection                                 │
│      ├─ users collection (subscription check)                   │
│      └─ settings collection (privacy check)                     │
│                                                                  │
│  Integration Layer                                              │
│  └─ External Services                                           │
│      ├─ Email service (invitations)                             │
│      ├─ Notification service (team events)                      │
│      └─ Analytics service (tracking)                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Integration Points

### 6.1 With Settings Module

**Privacy Controls Integration:**

The Team System depends on user privacy settings to determine data visibility.

**Flow:**
1. User updates `Settings.familySharing` toggles
2. Changes are saved to `settings` collection
3. Team data views immediately reflect new settings
4. No need to rejoin teams or notify members

**Settings Model Integration:**
```python
class UserSettings(BaseModel):
    user_id: str
    familySharing: FamilySharing

class FamilySharing(BaseModel):
    profile: bool = False
    activity: bool = False
    testResults: bool = False
    sleep: bool = False
```

**API Dependency:**
```python
# In team service
async def get_member_shared_data(team_id: str, member_user_id: str):
    # Load member's privacy settings
    settings = await settings_service.get_user_settings(member_user_id)

    # Return only shared data
    return {
        "profile": get_profile() if settings.familySharing.profile else None,
        "activity": get_activity() if settings.familySharing.activity else None,
        # ...
    }
```

---

### 6.2 With Med-Reminder Module (Future)

**Task Assignment to Teams:**

Med-Reminder tasks can be assigned to `team_id` instead of just `user_id`.

**Task Model Extension:**
```python
class Task(BaseModel):
    task_id: str
    name: str
    user_id: Optional[str] = None  # Personal task
    team_id: Optional[str] = None  # Team task (mutually exclusive)
    # ... other fields
```

**Visibility Rules:**
- Team members see task completion status for team tasks
- Parents can assign tasks to teens within team context
- Task visibility respects team membership and privacy settings

---

### 6.3 With User Profile & Subscription

**Subscription Gating:**

Team operations have tier-based limits:
- **Free users:** Can create/join 1 team maximum
- **Paid users:** Can create/join unlimited teams

```python
# Helper function to check team limit
async def check_team_limit(user: UserInDB, db):
    """Check if user can create or join a team based on subscription tier."""
    if user.subscription.tier == SubscriptionTier.FREE:
        # Count current teams (as member, not pending)
        current_team_count = await db.team_members.count_documents({
            "user_id": user.user_id,
            "status": MemberStatus.MEMBER.value
        })

        if current_team_count >= 1:
            raise HTTPException(
                status_code=403,
                detail="Team limit reached (1 team max for Free users). Upgrade to join more teams."
            )

    # Paid users have no limit
    return True
```

**Usage in Routes:**
```python
@router.post("/teams", response_model=TeamResponse)
async def create_team(
    data: TeamCreate,
    user: UserInDB = Depends(get_current_user),
    db = Depends(get_database)
):
    # Check team limit before creating
    await check_team_limit(user, db)
    return await team_service.create_team(user.user_id, data)

@router.post("/teams/{team_id}/accept", response_model=TeamResponse)
async def accept_invitation(
    team_id: str,
    user: UserInDB = Depends(get_current_user),
    db = Depends(get_database)
):
    # Check team limit before accepting
    await check_team_limit(user, db)
    return await team_service.accept_invitation(team_id, user.user_id)
```

---

### 6.4 With Notification System (Future)

**Team Event Notifications:**

- Member invited → Email to invitee
- Invitation accepted → Notification to admins
- Member removed → Notification to removed user
- Team deleted → Email to all members
- Privacy settings changed → No notification (silent)

**Notification Types:**
```python
class TeamNotificationType(str, Enum):
    INVITED = "team.invited"
    INVITATION_ACCEPTED = "team.invitation_accepted"
    MEMBER_REMOVED = "team.member_removed"
    TEAM_DELETED = "team.deleted"
    LEFT_TEAM = "team.left"
```

---

## 7. Implementation Priority

### Phase 1: Core Team Management (MVP)

**Goal:** Users can create teams and manage basic membership

**Backend Tasks:**
1. ✅ Define data models (Team, TeamMember, enums)
2. ✅ Create database collections and indexes
3. ✅ Implement TeamService class
4. ✅ Build team management endpoints:
   - POST /teams (create)
   - GET /teams (list)
   - GET /teams/{id} (detail)
   - PUT /teams/{id} (update)
   - DELETE /teams/{id} (delete)
5. ✅ Add subscription gating middleware
6. ✅ Write unit tests

**Frontend Tasks:**
1. ✅ Define Dart models (Team, TeamMember, enums)
2. ✅ Create TeamService class
3. ✅ Build Team List Screen
4. ✅ Build Create Team Screen
5. ✅ Build Team Detail Screen
6. ✅ Add navigation from Settings
7. ✅ Add subscription gate UI (upgrade prompt for Free users)

**Estimated Time:** 1-2 weeks

---

### Phase 2: Invitation System

**Goal:** Admins can invite members, users can accept invitations

**Backend Tasks:**
1. ✅ Implement invitation endpoints:
   - POST /teams/{id}/invite
   - POST /teams/{id}/accept
   - GET /teams/{id}/invitations
2. ✅ Add email notification service integration
3. ✅ Add invitation expiration logic (30 days)
4. ✅ Implement invitation validation (check user exists, subscription, etc.)
5. ✅ Write unit tests

**Frontend Tasks:**
1. ✅ Build Invite Member Screen
2. ✅ Build Accept Invitation Dialog
3. ✅ Add pending invitations section to Team List
4. ✅ Add invitation badges and notifications
5. ✅ Handle invitation errors (user not found, etc.)

**Estimated Time:** 1 week

---

### Phase 3: Member Management

**Goal:** Admins can remove members, members can leave teams

**Backend Tasks:**
1. ✅ Implement member management endpoints:
   - GET /teams/{id}/members
   - POST /teams/{id}/leave
   - DELETE /teams/{id}/members/{user_id}
2. ✅ Add "last admin" protection logic
3. ✅ Add member removal notifications
4. ✅ Write unit tests

**Frontend Tasks:**
1. ✅ Add member list to Team Detail Screen
2. ✅ Add "Leave Team" button with confirmation
3. ✅ Add "Remove Member" button (admin only) with confirmation
4. ✅ Handle edge cases (last admin, etc.)

**Estimated Time:** 3-5 days

---

### Phase 4: Data Sharing Integration

**Goal:** Team members can see shared data based on privacy settings

**Backend Tasks:**
1. ✅ Implement shared data endpoints:
   - GET /teams/{id}/shared-data
   - GET /teams/{id}/members/{user_id}/data
2. ✅ Integrate with Settings service
3. ✅ Implement privacy-driven data filtering
4. ✅ Add real-time privacy setting updates
5. ✅ Write unit tests

**Frontend Tasks:**
1. ✅ Build Shared Data Tab in Team Detail
2. ✅ Build Member Shared Data Screen
3. ✅ Add data sharing status indicators
4. ✅ Add "Not shared" placeholders
5. ✅ Link to Settings for privacy control

**Estimated Time:** 1 week

---

### Phase 5: Polish & Advanced Features

**Goal:** Improve UX and add nice-to-have features

**Tasks:**
1. ✅ Add team analytics (member activity, engagement)
2. ✅ Add team search/filter
3. ✅ Add bulk invite feature
4. ✅ Add role promotion/demotion (promote member to admin)
5. ✅ Add team avatar/image
6. ✅ Improve error messages and loading states
7. ✅ Add onboarding flow for first-time team creators
8. ✅ Performance optimization (caching, pagination)

**Estimated Time:** 1-2 weeks

---

## 8. Security & Privacy

### 8.1 Privacy Principles

1. **Opt-in by Default:** All data sharing is disabled by default
2. **User Control:** Users can enable/disable sharing at any time
3. **No Admin Override:** Admins cannot force members to share data
4. **Immediate Effect:** Privacy changes take effect immediately
5. **Pending Isolation:** Pending members have zero access to team data
6. **Post-Exit:** Leaving/removal immediately revokes all access

### 8.2 Security Measures

**Authentication:**
- JWT token validation on all endpoints
- Token expiration and refresh
- Secure password hashing (bcrypt)

**Authorization:**
- Multi-layer authorization checks
- Role-based access control
- Subscription tier validation

**Data Protection:**
- HTTPS/TLS for all API calls
- Input validation and sanitization
- SQL injection prevention (parameterized queries)
- XSS prevention (escaped output)

**Rate Limiting:**
- API rate limits per user
- Invitation limit per team (e.g., 10/day)
- Team creation limit per user (e.g., 5 total)

**Audit Logging:**
- Log all team admin actions
- Log member additions/removals
- Log privacy setting changes
- Retention policy (90 days)

### 8.3 Data Retention

**Soft Delete:**
- Teams: 30 days retention after deletion
- Members: Immediate hard delete upon removal/leave
- Invitations: 30 days expiration

**User Account Deletion:**
- Remove from all teams immediately
- Delete all team_member records
- Transfer admin role if sole admin (or delete team)

---

## 9. Testing Strategy

### 9.1 Unit Tests

**Backend (Python/Pytest):**
```python
# Test team creation
def test_create_team_success()
def test_create_team_free_user_blocked()
def test_create_team_invalid_name()

# Test invitation
def test_invite_member_success()
def test_invite_nonexistent_user()
def test_invite_free_user_blocked()
def test_invite_already_member()

# Test authorization
def test_member_cannot_invite()
def test_non_member_cannot_view()
def test_pending_cannot_access_data()
```

**Frontend (Dart/Flutter Test):**
```dart
// Test team list
void testTeamListLoading()
void testTeamListEmpty()
void testTeamListDisplay()

// Test invitation flow
void testAcceptInvitation()
void testInvitationValidation()
```

### 9.2 Integration Tests

**API Integration:**
- Test full invitation flow (invite → accept → view data)
- Test privacy setting changes reflect in team views
- Test team deletion removes all members
- Test last admin protection

**End-to-End:**
- User A creates team
- User A invites User B
- User B accepts invitation
- User B enables activity sharing
- User A views User B's activity data
- User B disables activity sharing
- User A sees "Not shared" message

---

## 10. Deployment Checklist

### Backend Deployment

- [ ] Create MongoDB indexes (teams, team_members)
- [ ] Deploy new API endpoints to production
- [ ] Set up email service for invitations
- [ ] Configure rate limiting
- [ ] Set up monitoring and alerts
- [ ] Update API documentation

### Frontend Deployment

- [ ] Build and test iOS app
- [ ] Build and test Android app
- [ ] Update app version
- [ ] Submit to app stores
- [ ] Update in-app documentation

### Post-Deployment

- [ ] Monitor error rates
- [ ] Check email delivery
- [ ] Verify subscription gates
- [ ] Test privacy controls
- [ ] Collect user feedback

---

## 11. Future Enhancements

### Phase 6+: Advanced Features

1. **Team Types:**
   - Family teams
   - Support group teams
   - Healthcare provider teams

2. **Role Extensions:**
   - Custom roles (e.g., Guardian, Counselor)
   - Granular permissions

3. **Team Communication:**
   - In-app messaging
   - Team announcements
   - Shared calendar

4. **Team Analytics:**
   - Progress tracking
   - Engagement metrics
   - Health trends comparison

5. **Med-Reminder Integration:**
   - Assign tasks to team members
   - View task completion status
   - Coordinate medication schedules

---

## Appendix

### A. Error Codes Reference

| Code | Message | Description |
|------|---------|-------------|
| 401 | Unauthorized | User not authenticated |
| 402 | Payment Required | User has Free subscription |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Duplicate or invalid state |
| 410 | Gone | Resource expired |
| 429 | Too Many Requests | Rate limit exceeded |

### B. Database Migration Scripts

```javascript
// Create teams collection
db.createCollection("teams")
db.teams.createIndex({ team_id: 1 }, { unique: true })
db.teams.createIndex({ created_by: 1 })
db.teams.createIndex({ is_deleted: 1 })

// Create team_members collection
db.createCollection("team_members")
db.team_members.createIndex({ team_id: 1, user_id: 1 }, { unique: true })
db.team_members.createIndex({ user_id: 1, status: 1 })
db.team_members.createIndex({ team_id: 1, status: 1 })
db.team_members.createIndex({ invited_at: 1 })
```

### C. API Rate Limits

| Endpoint | Rate Limit | Window |
|----------|------------|--------|
| POST /teams | 5 | 1 hour |
| POST /teams/{id}/invite | 10 | 1 day |
| POST /teams/{id}/accept | 10 | 1 hour |
| GET /teams | 100 | 1 minute |
| GET /teams/{id}/shared-data | 60 | 1 minute |

---

**Document Version:** 1.0
**Last Updated:** 2026-02-05
**Author:** Claude Code Assistant
**Status:** Ready for Implementation
