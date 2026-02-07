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
- **Pro users (Monthly/Annual) can create/join unlimited teams**
- Pending members have zero access to team data
- Admins cannot override privacy settings
- Team membership alone never implies data access

### 1.4 Subscription Branding

**User-Facing Display Names:**
- Free tier: **"Free"**
- Monthly plan: **"Pro"** (displayed as "Pro • $16.99/month")
- Annual plan: **"Pro"** (displayed as "Pro • $179/year")

**Technical/Internal References:**
- Code and documentation may refer to "Free users", "Pro users", or "Paid users" for clarity
- Database tier values remain: `free`, `monthly`, `annual`

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

### 3.0 Standardized Subscription Error Response

When a subscription limit is reached, endpoints return a `403 Forbidden` with a structured error payload that includes upgrade information.

**Error Response Structure:**
```json
{
  "error": {
    "code": "SUBSCRIPTION_LIMIT_REACHED",
    "message": "You've reached your team limit (1 team maximum)",
    "detail": "Free users can create/join 1 team. Upgrade to Pro for unlimited teams.",
    "subscription": {
      "current_tier": "free",
      "required_tier": "pro",
      "upgrade_required": true
    },
    "action": {
      "type": "upgrade",
      "label": "Upgrade to Pro",
      "destination": "/subscription/upgrade"
    }
  }
}
```

**Python Error Model:**
```python
from pydantic import BaseModel
from typing import Optional

class SubscriptionActionInfo(BaseModel):
    """Action information for subscription errors"""
    type: str = "upgrade"  # "upgrade" | "downgrade" | "none"
    label: str = "Upgrade to Pro"
    destination: str = "/subscription/upgrade"

class SubscriptionInfo(BaseModel):
    """Subscription details in error response"""
    current_tier: str  # "free" | "monthly" | "annual"
    required_tier: str  # "monthly" | "annual"
    upgrade_required: bool = True

class SubscriptionErrorDetail(BaseModel):
    """Detailed subscription error information"""
    code: str  # "SUBSCRIPTION_LIMIT_REACHED" | "FEATURE_REQUIRES_PRO"
    message: str  # Short user-facing message
    detail: str  # Detailed explanation
    subscription: SubscriptionInfo
    action: SubscriptionActionInfo

class SubscriptionError(BaseModel):
    """Top-level subscription error response"""
    error: SubscriptionErrorDetail
```

**Usage in Endpoints:**
```python
from fastapi import HTTPException

def raise_subscription_limit_error(
    user_tier: str,
    message: str = "You've reached your team limit",
    detail: str = "Free users can create/join 1 team. Upgrade to Pro for unlimited teams."
):
    """Raise a standardized subscription limit error"""
    error_response = {
        "error": {
            "code": "SUBSCRIPTION_LIMIT_REACHED",
            "message": message,
            "detail": detail,
            "subscription": {
                "current_tier": user_tier,
                "required_tier": "pro",
                "upgrade_required": True
            },
            "action": {
                "type": "upgrade",
                "label": "Upgrade to Pro",
                "destination": "/subscription/upgrade"
            }
        }
    }
    raise HTTPException(status_code=403, detail=error_response)
```

**Flutter/Dart Error Model:**
```dart
class SubscriptionErrorResponse {
  final String code;
  final String message;
  final String detail;
  final SubscriptionInfo subscription;
  final SubscriptionAction action;

  const SubscriptionErrorResponse({
    required this.code,
    required this.message,
    required this.detail,
    required this.subscription,
    required this.action,
  });

  factory SubscriptionErrorResponse.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>;
    return SubscriptionErrorResponse(
      code: error['code'] as String,
      message: error['message'] as String,
      detail: error['detail'] as String,
      subscription: SubscriptionInfo.fromJson(error['subscription']),
      action: SubscriptionAction.fromJson(error['action']),
    );
  }

  bool get isSubscriptionError => code == 'SUBSCRIPTION_LIMIT_REACHED';
}

class SubscriptionInfo {
  final String currentTier;
  final String requiredTier;
  final bool upgradeRequired;

  const SubscriptionInfo({
    required this.currentTier,
    required this.requiredTier,
    required this.upgradeRequired,
  });

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      currentTier: json['current_tier'] as String,
      requiredTier: json['required_tier'] as String,
      upgradeRequired: json['upgrade_required'] as bool,
    );
  }
}

class SubscriptionAction {
  final String type;
  final String label;
  final String destination;

  const SubscriptionAction({
    required this.type,
    required this.label,
    required this.destination,
  });

  factory SubscriptionAction.fromJson(Map<String, dynamic> json) {
    return SubscriptionAction(
      type: json['type'] as String,
      label: json['label'] as String,
      destination: json['destination'] as String,
    );
  }
}
```

---

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
- `403 Forbidden` - Free user already has 1 team (team limit reached) - **Returns standardized subscription error**
- `400 Bad Request` - Invalid team name

**403 Subscription Limit Error Example:**
```json
{
  "error": {
    "code": "SUBSCRIPTION_LIMIT_REACHED",
    "message": "You've reached your team limit (1/1 teams)",
    "detail": "Free users can create 1 team. Upgrade to Pro for unlimited teams.",
    "subscription": {
      "current_tier": "free",
      "required_tier": "pro",
      "upgrade_required": true
    },
    "action": {
      "type": "upgrade",
      "label": "Upgrade to Pro",
      "destination": "/subscription/upgrade"
    }
  }
}
```

**Business Logic:**
```python
async def create_team(user_id: str, data: TeamCreate):
    user = await get_user(user_id)

    # Check team limit based on subscription
    current_team_count = await get_user_team_count(user_id)

    if user.subscription.tier == SubscriptionTier.FREE:
        if current_team_count >= 1:
            raise_subscription_limit_error(
                user_tier="free",
                message=f"You've reached your team limit ({current_team_count}/1 teams)",
                detail="Free users can create 1 team. Upgrade to Pro for unlimited teams."
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
- **No subscription check on invite:** Invitations can be sent to any user regardless of their subscription tier or team count. The subscription check happens when the invitee accepts the invitation.

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
- `403 Forbidden` - Not an admin
- `409 Conflict` - Email already in team or has pending invitation
- ✅ **No 404 error** - Unregistered users can be invited

**Business Logic:**
```python
async def invite_member(team_id: str, inviter_user_id: str, email: str):
    # Verify inviter is admin
    inviter_member = await get_team_member(team_id, inviter_user_id)
    if inviter_member.role != TeamRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admins can invite members")

    # Get team and inviter details for email
    team = await get_team(team_id)
    inviter = await get_user(inviter_user_id)

    # Check if email is already registered
    invited_user = await get_user_by_email(email)

    if invited_user:
        # User is registered - check if already in team
        existing_member = await get_team_member(team_id, invited_user.user_id)
        if existing_member:
            if existing_member.status == MemberStatus.MEMBER:
                raise HTTPException(status_code=409, detail="User is already a team member")
            elif existing_member.status == MemberStatus.PENDING:
                raise HTTPException(status_code=409, detail="User already has a pending invitation")

        # Create pending invitation for registered user
        await create_team_member(
            team_id=team_id,
            user_id=invited_user.user_id,
            role=TeamRole.MEMBER,
            status=MemberStatus.PENDING,
            invited_by=inviter_user_id,
            invited_at=datetime.utcnow()
        )
    else:
        # User is NOT registered - check if email already invited
        existing_invitation = await get_pending_invitation_by_email(team_id, email)
        if existing_invitation:
            raise HTTPException(status_code=409, detail="Email already has a pending invitation")

        # Create pending invitation with email (no user_id yet)
        await create_pending_invitation_by_email(
            team_id=team_id,
            email=email,
            invited_by=inviter_user_id,
            invited_at=datetime.utcnow()
        )

    # Generate invitation token (JWT with team_id and email)
    invitation_token = generate_invitation_token(
        team_id=team_id,
        email=email,
        expires_in_days=30
    )

    # Generate invitation link
    invitation_link = f"https://lumie.app/invite/{invitation_token}"
    # Or deep link: lumie://invite/{invitation_token}

    # Send invitation email
    await send_invitation_email(
        to_email=email,
        inviter_name=inviter.name,
        team_name=team.name,
        invitation_link=invitation_link,
        is_registered=invited_user is not None
    )

    return {
        "team_id": team_id,
        "invited_email": email,
        "is_registered": invited_user is not None,
        "status": "pending",
        "invited_at": datetime.utcnow().isoformat(),
        "invitation_link": invitation_link
    }
```

**Invitation Token Structure (JWT):**
```python
def generate_invitation_token(team_id: str, email: str, expires_in_days: int = 30) -> str:
    """Generate a JWT token for team invitation"""
    payload = {
        "team_id": team_id,
        "email": email,
        "type": "team_invitation",
        "exp": datetime.utcnow() + timedelta(days=expires_in_days),
        "iat": datetime.utcnow()
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")

def decode_invitation_token(token: str) -> dict:
    """Decode and validate invitation token"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        if payload.get("type") != "team_invitation":
            return None
        return payload
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None
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
- `403 Forbidden` - No pending invitation OR team limit reached - **Returns standardized subscription error**
- `404 Not Found` - Team or invitation doesn't exist
- `410 Gone` - Invitation expired

**403 Subscription Limit Error Example:**
```json
{
  "error": {
    "code": "SUBSCRIPTION_LIMIT_REACHED",
    "message": "You've reached your team limit (1/1 teams)",
    "detail": "Free users can join 1 team. Upgrade to Pro for unlimited teams.",
    "subscription": {
      "current_tier": "free",
      "required_tier": "pro",
      "upgrade_required": true
    },
    "action": {
      "type": "upgrade",
      "label": "Upgrade to Pro",
      "destination": "/subscription/upgrade"
    }
  }
}
```

**Business Logic:**
```python
async def accept_invitation(team_id: str, user_id: str):
    user = await get_user(user_id)

    # Check team limit before accepting
    current_team_count = await get_user_team_count(user_id)

    if user.subscription.tier == SubscriptionTier.FREE:
        if current_team_count >= 1:
            raise_subscription_limit_error(
                user_tier="free",
                message=f"You've reached your team limit ({current_team_count}/1 teams)",
                detail="Free users can join 1 team. Upgrade to Pro for unlimited teams."
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

#### **GET /api/teams/invitations/token/{token}** - Get invitation details by token (Public)

**Purpose:** Allow unregistered users to view invitation details before registering

**Authorization Conditions:**
- ❌ **No authentication required** - This is a public endpoint
- ✓ Token must be valid and not expired
- ✓ Token must not have been accepted yet

**Response:** `200 OK`
```json
{
  "invitation_token": "inv_abc123xyz",
  "team": {
    "team_id": "team_123",
    "name": "Smith Family",
    "description": "Our family support team",
    "member_count": 4
  },
  "invited_by": {
    "name": "John Smith",
    "role": "parent"
  },
  "invited_email": "jane@example.com",
  "invited_at": "2026-02-05T10:00:00Z",
  "expires_at": "2026-03-07T10:00:00Z",
  "is_registered": false
}
```

**Error Responses:**
- `404 Not Found` - Token doesn't exist or invitation not found
- `410 Gone` - Invitation expired or already accepted

**Business Logic:**
```python
async def get_invitation_by_token(token: str):
    # Decode and validate token
    invitation_data = decode_invitation_token(token)
    if not invitation_data:
        raise HTTPException(status_code=404, detail="Invalid invitation token")

    team_id = invitation_data["team_id"]
    email = invitation_data["email"]

    # Get team member record
    team_member = await get_pending_invitation_by_email(team_id, email)
    if not team_member or team_member.status != MemberStatus.PENDING:
        raise HTTPException(status_code=410, detail="Invitation expired or already accepted")

    # Check if email is registered
    user = await get_user_by_email(email)
    is_registered = user is not None

    # Get team and inviter details
    team = await get_team(team_id)
    inviter = await get_user(team_member.invited_by)

    return {
        "invitation_token": token,
        "team": {
            "team_id": team.team_id,
            "name": team.name,
            "description": team.description,
            "member_count": await get_team_member_count(team_id)
        },
        "invited_by": {
            "name": inviter.name,
            "role": inviter.role
        },
        "invited_email": email,
        "invited_at": team_member.invited_at,
        "expires_at": team_member.invited_at + timedelta(days=30),
        "is_registered": is_registered
    }
```

---

#### **POST /api/teams/invitations/token/{token}/accept** - Accept invitation via token

**Purpose:** Accept invitation using a token (used after registration for unregistered users)

**Authorization Conditions:**
- ✓ User must be authenticated
- ✓ User's email must match the invitation email
- ✓ Token must be valid and not expired
- ✓ Invitation must still be pending

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
- `401 Unauthorized` - Not authenticated
- `403 Forbidden` - Email mismatch OR team limit reached
- `404 Not Found` - Token doesn't exist
- `410 Gone` - Invitation expired or already accepted

**Business Logic:**
```python
async def accept_invitation_by_token(token: str, user_id: str):
    # Decode token and validate
    invitation_data = decode_invitation_token(token)
    if not invitation_data:
        raise HTTPException(status_code=404, detail="Invalid invitation token")

    team_id = invitation_data["team_id"]
    invited_email = invitation_data["email"]

    # Verify user's email matches invitation
    user = await get_user(user_id)
    if user.email != invited_email:
        raise HTTPException(status_code=403, detail="Email mismatch")

    # Use existing accept_invitation logic
    return await accept_invitation(team_id, user_id)
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

### 4.0 Error Handling Strategy

**Exception Types:**

The Flutter app uses custom exceptions to handle subscription-related errors:

```dart
/// Base exception for subscription-related errors
class SubscriptionException implements Exception {
  final SubscriptionErrorResponse errorResponse;

  SubscriptionException(this.errorResponse);

  @override
  String toString() => errorResponse.message;
}

/// Thrown when user has reached their team limit
/// This applies to:
/// - Creating a new team (when at limit)
/// - Accepting an invitation (when at limit)
class SubscriptionLimitException extends SubscriptionException {
  SubscriptionLimitException(super.errorResponse);
}
```

**Service Layer Error Parsing:**

The TeamService should parse error responses and throw appropriate exceptions:

```dart
class TeamService {
  Future<Team> createTeam({required String name, String? description}) async {
    try {
      final response = await _apiClient.post(
        '/api/teams',
        body: {'name': name, 'description': description},
      );
      return Team.fromJson(response.data);
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        final errorResponse = _parseSubscriptionError(e.data);
        if (errorResponse != null) {
          if (errorResponse.code == 'SUBSCRIPTION_LIMIT_REACHED') {
            throw SubscriptionLimitException(errorResponse);
          }
        }
      }
      rethrow;
    }
  }

  Future<void> acceptInvitation(String teamId) async {
    try {
      await _apiClient.post('/api/teams/$teamId/accept');
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        final errorResponse = _parseSubscriptionError(e.data);
        if (errorResponse != null) {
          if (errorResponse.code == 'SUBSCRIPTION_LIMIT_REACHED') {
            throw SubscriptionLimitException(errorResponse);
          }
        }
      }
      rethrow;
    }
  }

  Future<void> inviteMember({required String teamId, required String email}) async {
    // No subscription error handling needed here
    // Subscription check happens when invitee accepts
    await _apiClient.post(
      '/api/teams/$teamId/invite',
      body: {'email': email},
    );
  }

  SubscriptionErrorResponse? _parseSubscriptionError(dynamic data) {
    try {
      if (data is Map<String, dynamic> && data.containsKey('error')) {
        return SubscriptionErrorResponse.fromJson(data);
      }
    } catch (e) {
      // Failed to parse subscription error
      return null;
    }
    return null;
  }
}
```

**UI Error Handling Pattern:**

All screens that may encounter subscription limits should follow this pattern:

1. Catch `SubscriptionLimitException` → Show upgrade prompt with button
2. Catch other exceptions → Show generic error message

**Subscription check locations:**
- ✅ **Create Team Screen** - Check when user creates a new team
- ✅ **Accept Invitation Dialog** - Check when user accepts an invitation
- ❌ **Invite Member Screen** - NO subscription check (invitations sent freely, check on accept)

**Example:**
```dart
try {
  // Call service method (createTeam or acceptInvitation)
  await teamService.createTeam(name: name);
} on SubscriptionLimitException catch (e) {
  // User's own limit - show upgrade prompt with button
  _showUpgradePrompt(error: e.errorResponse);
} catch (e) {
  // Generic error (not found, already exists, etc.)
  _showErrorSnackbar(message: e.toString());
}
```

---

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
  - If Free tier and has 1 team: Show "Team limit reached (1/1). Upgrade to Pro for unlimited teams"
  - If Free tier and has 0 teams: Show "Free: 1 team available"
  - If Pro tier: Show "Pro: Unlimited teams"
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
  - **Behavior:**
    - If Free user and already has 1 team: Show upgrade prompt immediately (don't navigate to create screen)
    - Otherwise: Navigate to Create Team Screen

**API Calls:**
- `GET /api/teams` (on load)

**State Management:**
```dart
class TeamsProvider extends ChangeNotifier {
  List<Team> _teams = [];
  List<TeamInvitation> _pendingInvitations = [];
  bool _isLoading = false;
  SubscriptionTier _userTier = SubscriptionTier.FREE;

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

  bool get canCreateTeam {
    if (_userTier == SubscriptionTier.FREE) {
      return _teams.length < 1;
    }
    return true; // Pro users can create unlimited
  }

  bool get hasReachedTeamLimit {
    if (_userTier == SubscriptionTier.FREE) {
      return _teams.length >= 1;
    }
    return false;
  }
}
```

**FAB Click Handler:**
```dart
void _onCreateTeamPressed() {
  final provider = context.read<TeamsProvider>();

  if (provider.hasReachedTeamLimit) {
    // Show upgrade prompt immediately
    _showUpgradePrompt(
      message: "You've reached your team limit (1/1 teams)",
      detail: "Free users can create 1 team. Upgrade to Pro for unlimited teams.",
    );
  } else {
    // Navigate to create team screen
    Navigator.of(context).pushNamed('/teams/create');
  }
}

void _showUpgradePrompt({required String message, required String detail}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => UpgradePromptBottomSheet(
      title: 'Upgrade to Pro',
      message: message,
      detail: detail,
      actionLabel: 'Upgrade to Pro',
      onUpgrade: () {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamed('/subscription/upgrade');
      },
    ),
  );
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
5. On error: Handle based on error type

**Error Handling:**

**Subscription Limit Error (403 with SUBSCRIPTION_LIMIT_REACHED):**
- Show modal/bottom sheet with:
  - Icon: Lock or Crown
  - Title: "Upgrade to Pro"
  - Message: Error message from API (`error.message`)
  - Detail: Error detail from API (`error.detail`)
  - Primary button: "Upgrade to Pro" → Navigate to `/subscription/upgrade`
  - Secondary button: "Not Now" → Dismiss and return to Team List

**Other Errors:**
- Show standard error snackbar/toast

**Flutter Implementation:**
```dart
class CreateTeamScreen extends StatefulWidget {
  // ...
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  Future<void> _createTeam() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final team = await teamService.createTeam(
        name: _nameController.text,
        description: _descriptionController.text,
      );

      // Success: Navigate to team detail
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TeamDetailScreen(teamId: team.teamId),
        ),
      );
    } on SubscriptionLimitException catch (e) {
      // Show upgrade dialog
      _showUpgradeDialog(
        context: context,
        error: e.errorResponse,
      );
    } catch (e) {
      // Show generic error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create team: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showUpgradeDialog({
    required BuildContext context,
    required SubscriptionErrorResponse error,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => UpgradePromptBottomSheet(
        title: 'Upgrade to Pro',
        message: error.message,
        detail: error.detail,
        actionLabel: error.action.label,
        onUpgrade: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushNamed('/subscription/upgrade');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ... UI implementation
  }
}
```

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

**Error Handling:**

**No subscription check on invite side:**
- Invitations can be sent to any user regardless of their subscription status
- If the invited user has reached their team limit, they will see an upgrade prompt when they try to accept the invitation
- This provides a better UX - the invitee can make their own decision to upgrade

**Validation:**
- Check valid email format
- Show error if user not found
- Show error if already in team or has pending invitation

**Flutter Implementation:**
```dart
Future<void> _inviteMember(String email) async {
  if (!_isValidEmail(email)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Please enter a valid email address')),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    await teamService.inviteMember(
      teamId: widget.teamId,
      email: email,
    );

    // Success
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invitation sent to $email')),
    );
    _emailController.clear();
    _loadInvitations();
  } catch (e) {
    // Handle generic errors (user not found, already in team, etc.)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to invite: ${_getErrorMessage(e)}')),
    );
  } finally {
    setState(() => _isLoading = false);
  }
}

bool _isValidEmail(String email) {
  return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
}

String _getErrorMessage(dynamic error) {
  if (error.toString().contains('404')) {
    return 'User not found. Make sure they have a Lumie account.';
  } else if (error.toString().contains('409')) {
    return 'User is already a member or has a pending invitation.';
  }
  return error.toString();
}
```

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
4. On error: Handle based on error type

**Error Handling:**

**Subscription Limit Error (403 with SUBSCRIPTION_LIMIT_REACHED):**
- Dismiss invitation dialog
- Show upgrade modal/bottom sheet with:
  - Icon: Lock or Crown
  - Title: "Upgrade to Pro"
  - Message: Error message from API (`error.message`)
  - Detail: Error detail from API (`error.detail`)
  - Primary button: "Upgrade to Pro" → Navigate to `/subscription/upgrade`
  - Secondary button: "Maybe Later" → Dismiss and return to Team List

**Other Errors:**
- Show error snackbar/toast

**Flutter Implementation:**
```dart
class AcceptInvitationDialog extends StatefulWidget {
  final TeamInvitation invitation;

  // ...
}

class _AcceptInvitationDialogState extends State<AcceptInvitationDialog> {
  bool _isLoading = false;

  Future<void> _acceptInvitation() async {
    setState(() => _isLoading = true);

    try {
      await teamService.acceptInvitation(widget.invitation.teamId);

      // Success
      Navigator.of(context).pop(); // Close invitation dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully joined ${widget.invitation.teamName}')),
      );

      // Navigate to team detail
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TeamDetailScreen(teamId: widget.invitation.teamId),
        ),
      );
    } on SubscriptionLimitException catch (e) {
      // Close invitation dialog first
      Navigator.of(context).pop();

      // Show upgrade dialog
      _showUpgradeDialog(
        context: context,
        error: e.errorResponse,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept invitation: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showUpgradeDialog({
    required BuildContext context,
    required SubscriptionErrorResponse error,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      builder: (context) => UpgradePromptBottomSheet(
        title: 'Upgrade to Pro',
        message: error.message,
        detail: error.detail,
        actionLabel: error.action.label,
        onUpgrade: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushNamed('/subscription/upgrade');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ... UI implementation
  }
}
```

---

### 4.8 Upgrade Prompt Bottom Sheet (Reusable Component)

**Purpose:** Reusable component to prompt users to upgrade when subscription limits are reached

**UI Elements:**
- **Bottom Sheet (Modal)**
  - Rounded top corners
  - Padding: 24px all sides
  - Max height: 60% of screen

- **Icon Section:**
  - Crown or Lock icon (configurable)
  - Size: 64px
  - Color: Primary/Gold color
  - Centered

- **Title:**
  - Text: "Upgrade to Pro"
  - Font: Headline, Bold
  - Centered

- **Message:**
  - Text: Error message (from API)
  - Font: Body, Medium weight
  - Color: Primary text color
  - Centered
  - Example: "You've reached your team limit (1/1 teams)"

- **Detail:**
  - Text: Error detail (from API)
  - Font: Body, Regular
  - Color: Secondary text color
  - Centered
  - Example: "Free users can create 1 team. Upgrade to Pro for unlimited teams."

- **Benefits List (Optional):**
  - Show key Pro features:
    - "✓ Unlimited teams"
    - "✓ Advanced family sharing"
    - "✓ Priority support"

- **Primary Button:**
  - Text: "Upgrade to Pro"
  - Style: Filled, Primary color
  - Full width
  - Action: Navigate to `/subscription/upgrade`

- **Secondary Button:**
  - Text: "Not Now" or "Maybe Later"
  - Style: Text button
  - Full width
  - Action: Dismiss bottom sheet

**Flutter Implementation:**
```dart
class UpgradePromptBottomSheet extends StatelessWidget {
  final String title;
  final String message;
  final String detail;
  final String actionLabel;
  final VoidCallback onUpgrade;
  final VoidCallback? onDismiss;
  final bool showBenefits;

  const UpgradePromptBottomSheet({
    Key? key,
    required this.title,
    required this.message,
    required this.detail,
    required this.actionLabel,
    required this.onUpgrade,
    this.onDismiss,
    this.showBenefits = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Crown icon
          Icon(
            Icons.workspace_premium,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          SizedBox(height: 16),

          // Title
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12),

          // Message
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),

          // Detail
          Text(
            detail,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),

          // Benefits (if enabled)
          if (showBenefits) ...[
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBenefit(context, 'Unlimited teams'),
                  SizedBox(height: 8),
                  _buildBenefit(context, 'Advanced family sharing'),
                  SizedBox(height: 8),
                  _buildBenefit(context, 'Priority support'),
                ],
              ),
            ),
            SizedBox(height: 24),
          ],

          // Primary button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onUpgrade,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(actionLabel),
            ),
          ),
          SizedBox(height: 12),

          // Secondary button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onDismiss ?? () => Navigator.of(context).pop(),
              child: Text('Not Now'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefit(BuildContext context, String text) {
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
```

**Usage Example:**
```dart
// In any screen that needs to show upgrade prompt
void _showUpgradePrompt(SubscriptionErrorResponse error) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (context) => UpgradePromptBottomSheet(
      title: 'Upgrade to Pro',
      message: error.message,
      detail: error.detail,
      actionLabel: error.action.label,
      onUpgrade: () {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamed(error.action.destination);
      },
    ),
  );
}
```

---

### 4.9 Invitation Landing Page (Web & App Deep Link)

**Purpose:** Handle invitation links for both registered and unregistered users

**Entry Points:**
- **Web:** `https://lumie.app/invite/{token}`
- **Deep Link:** `lumie://invite/{token}`

**Flow:**
1. User clicks invitation link (from email or message)
2. System detects if app is installed:
   - **App installed:** Deep link opens app → Navigate to invitation preview
   - **App not installed:** Web page opens → Show invitation preview on web

**Web Page UI Elements:**
- **Header:** Lumie logo
- **Invitation Card:**
  - Team name and description
  - "You've been invited by [Inviter Name]"
  - Member count: "Join 4 other members"
  - Team icon/avatar

- **Call-to-Action:**
  - If user is logged in (web session):
    - Button: "Accept Invitation" → Opens app or web app
  - If user is not logged in:
    - Primary button: "Download Lumie App"
    - Secondary button: "Sign Up on Web"
    - Link: "Already have an account? Sign In"

**API Calls:**
- `GET /api/teams/invitations/token/{token}` (public endpoint)

**Implementation:**
```dart
// Deep link handler in Flutter app
class DeepLinkHandler {
  static Future<void> handleDeepLink(Uri uri) async {
    if (uri.pathSegments.first == 'invite' && uri.pathSegments.length == 2) {
      final token = uri.pathSegments[1];

      // Check if user is logged in
      final authService = GetIt.I<AuthService>();
      if (await authService.isAuthenticated()) {
        // User is logged in - navigate to invitation preview
        navigatorKey.currentState?.pushNamed(
          '/invitation/preview',
          arguments: {'token': token},
        );
      } else {
        // User is not logged in - navigate to login with invitation context
        navigatorKey.currentState?.pushNamed(
          '/login',
          arguments: {'invitation_token': token},
        );
      }
    }
  }
}
```

**Web Implementation (React/Next.js example):**
```typescript
// pages/invite/[token].tsx
export default function InvitationPage({ invitation }) {
  const isAppInstalled = detectMobileApp();

  if (isAppInstalled) {
    // Redirect to deep link
    window.location.href = `lumie://invite/${invitation.token}`;
  }

  return (
    <div className="invitation-page">
      <h1>You've been invited to {invitation.team.name}</h1>
      <p>By {invitation.invited_by.name}</p>

      {invitation.is_registered ? (
        <button onClick={() => openApp(invitation.token)}>
          Accept Invitation
        </button>
      ) : (
        <>
          <button onClick={downloadApp}>Download Lumie App</button>
          <button onClick={() => router.push(`/signup?token=${invitation.token}`)}>
            Sign Up on Web
          </button>
          <a href={`/login?token=${invitation.token}`}>
            Already have an account? Sign In
          </a>
        </>
      )}
    </div>
  );
}
```

---

### 4.10 Registration/Login with Invitation Context

**Purpose:** Allow unregistered users to sign up while preserving invitation context

**UI Elements:**

**Registration Screen (Enhanced):**
- Standard registration form (email, password, name, etc.)
- **Invitation banner at top:**
  - "You're joining [Team Name]"
  - Inviter avatar and name
  - Dismissible (but invitation context preserved)

- After successful registration:
  - Auto-redirect to invitation preview screen
  - Show welcome message: "Welcome! You have a pending team invitation"

**Login Screen (Enhanced):**
- Standard login form
- **Invitation banner at top:**
  - "Sign in to accept your invitation to [Team Name]"

- After successful login:
  - Auto-redirect to invitation preview screen

**API Calls:**
- `POST /api/auth/register?invitation_token={token}` (modified to include token)
- `POST /api/auth/login?invitation_token={token}` (modified to include token)

**Flutter Implementation:**
```dart
class RegistrationScreen extends StatefulWidget {
  final String? invitationToken;

  const RegistrationScreen({this.invitationToken});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  InvitationPreview? _invitation;
  bool _isLoadingInvitation = false;

  @override
  void initState() {
    super.initState();
    if (widget.invitationToken != null) {
      _loadInvitationDetails();
    }
  }

  Future<void> _loadInvitationDetails() async {
    setState(() => _isLoadingInvitation = true);

    try {
      final invitation = await teamService.getInvitationByToken(
        widget.invitationToken!
      );
      setState(() {
        _invitation = invitation;
        _isLoadingInvitation = false;
      });
    } catch (e) {
      // Token invalid or expired - continue with normal registration
      setState(() => _isLoadingInvitation = false);
    }
  }

  Future<void> _register() async {
    // ... registration logic

    final success = await authService.register(
      email: _emailController.text,
      password: _passwordController.text,
      name: _nameController.text,
      invitationToken: widget.invitationToken,
    );

    if (success) {
      if (widget.invitationToken != null) {
        // Redirect to invitation preview
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => InvitationPreviewScreen(
              token: widget.invitationToken!,
            ),
          ),
        );
      } else {
        // Normal registration flow
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Account')),
      body: Column(
        children: [
          // Invitation banner
          if (_invitation != null)
            _buildInvitationBanner(_invitation!),

          // Registration form
          _buildRegistrationForm(),
        ],
      ),
    );
  }

  Widget _buildInvitationBanner(InvitationPreview invitation) {
    return Container(
      padding: EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(Icons.group, size: 32),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're joining ${invitation.team.name}",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "Invited by ${invitation.invitedBy.name}",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

### 4.11 Invitation Preview Screen (Post-Registration)

**Purpose:** Show invitation details after user registers/logs in with invitation context

**Path:** `/invitation/preview?token={token}`

**UI Elements:**
- **Header:** "Team Invitation"
- **Team Card:**
  - Team name and description
  - Team avatar/icon
  - Member count: "4 members"
  - Created date

- **Inviter Section:**
  - "Invited by [Name]"
  - Inviter avatar
  - Inviter role badge

- **Invitation Details:**
  - Invited date: "Invited on Feb 5, 2026"
  - Expiration: "Expires in 28 days"

- **Actions:**
  - Primary button: "Accept Invitation"
  - Secondary button: "Decline"

- **Info Message:**
  - "By accepting, you'll be able to share health data with team members based on your privacy settings."
  - Link: "Review Privacy Settings"

**API Calls:**
- `GET /api/teams/invitations/token/{token}` (on load)
- `POST /api/teams/invitations/token/{token}/accept` (on accept)

**Flow:**
1. User lands on screen (after registration or from deep link)
2. Load invitation details by token
3. User taps "Accept Invitation"
4. Show loading
5. On success:
   - Show success message: "You've joined [Team Name]!"
   - Navigate to Team Detail Screen
6. On error (subscription limit):
   - Show upgrade prompt

**Flutter Implementation:**
```dart
class InvitationPreviewScreen extends StatefulWidget {
  final String token;

  const InvitationPreviewScreen({required this.token});

  @override
  State<InvitationPreviewScreen> createState() => _InvitationPreviewScreenState();
}

class _InvitationPreviewScreenState extends State<InvitationPreviewScreen> {
  InvitationPreview? _invitation;
  bool _isLoading = true;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  Future<void> _loadInvitation() async {
    try {
      final invitation = await teamService.getInvitationByToken(widget.token);
      setState(() {
        _invitation = invitation;
        _isLoading = false;
      });
    } catch (e) {
      // Handle error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load invitation: $e')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _acceptInvitation() async {
    setState(() => _isAccepting = true);

    try {
      final result = await teamService.acceptInvitationByToken(widget.token);

      // Success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You\'ve joined ${_invitation!.team.name}!')),
      );

      // Navigate to team detail
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TeamDetailScreen(teamId: result.teamId),
        ),
      );
    } on SubscriptionLimitException catch (e) {
      // Show upgrade prompt
      _showUpgradePrompt(e.errorResponse);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept invitation: $e')),
      );
    } finally {
      setState(() => _isAccepting = false);
    }
  }

  void _showUpgradePrompt(SubscriptionErrorResponse error) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => UpgradePromptBottomSheet(
        title: 'Upgrade to Pro',
        message: error.message,
        detail: error.detail,
        actionLabel: error.action.label,
        onUpgrade: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushNamed(error.action.destination);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Team Invitation')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Team card
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.group, size: 64, color: Theme.of(context).colorScheme.primary),
                    SizedBox(height: 12),
                    Text(
                      _invitation!.team.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    if (_invitation!.team.description != null) ...[
                      SizedBox(height: 8),
                      Text(
                        _invitation!.team.description!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    SizedBox(height: 12),
                    Text(
                      '${_invitation!.team.memberCount} members',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Inviter section
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(_invitation!.invitedBy.name[0]),
                ),
                title: Text('Invited by ${_invitation!.invitedBy.name}'),
                subtitle: Text('Invited on ${_formatDate(_invitation!.invitedAt)}'),
              ),
            ),

            SizedBox(height: 16),

            // Info message
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'By accepting, you\'ll be able to share health data with team members based on your privacy settings.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            SizedBox(height: 24),

            // Accept button
            ElevatedButton(
              onPressed: _isAccepting ? null : _acceptInvitation,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isAccepting
                  ? CircularProgressIndicator()
                  : Text('Accept Invitation'),
            ),

            SizedBox(height: 12),

            // Decline button
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Decline'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}
```

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
                detail="Team limit reached (1 team max for Free users). Upgrade to Pro for unlimited teams."
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

**Document Version:** 1.2
**Last Updated:** 2026-02-06
**Author:** Claude Code Assistant
**Status:** Ready for Implementation
**Changelog:**
- v1.2 (2026-02-06): Added unregistered user invitation flow with deep linking, invitation tokens, and landing pages
- v1.1 (2026-02-06): Added standardized subscription error response format and upgrade flow UI
- v1.0 (2026-02-05): Initial version
