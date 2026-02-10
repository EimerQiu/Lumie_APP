"""
Team and Team Member Models
"""

from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field
from enum import Enum


class TeamRole(str, Enum):
    """Team member roles"""
    ADMIN = "admin"
    MEMBER = "member"


class MemberStatus(str, Enum):
    """Team member status"""
    PENDING = "pending"
    MEMBER = "member"


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


class TeamMember(BaseModel):
    """Team membership model"""
    team_id: str = Field(..., description="Team identifier")
    user_id: str = Field(..., description="User identifier")
    role: TeamRole = Field(..., description="Member role (admin/member)")
    status: MemberStatus = Field(..., description="Member status (pending/member)")
    invited_by: str = Field(..., description="User ID who sent invitation")
    invited_at: datetime = Field(..., description="Invitation timestamp")
    joined_at: Optional[datetime] = Field(None, description="Acceptance timestamp")


# Request Models

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


# Response Models

class AdminInfo(BaseModel):
    """Team admin information"""
    user_id: str
    name: str


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
    admins: Optional[List[AdminInfo]] = None


class DataSharing(BaseModel):
    """Data sharing settings for a team member"""
    profile: bool
    activity: bool
    sleep: bool
    test_results: bool


class TeamMemberResponse(BaseModel):
    """Response model for team member data"""
    user_id: str
    name: str
    email: str
    role: TeamRole
    status: MemberStatus
    joined_at: Optional[datetime]
    data_sharing: DataSharing


class TeamInvitation(BaseModel):
    """Pending team invitation"""
    team_id: str
    team_name: str
    invited_by_name: str
    invited_at: datetime


class TeamsListResponse(BaseModel):
    """Response for GET /teams endpoint"""
    teams: List[TeamResponse]
    pending_invitations: List[TeamInvitation]


class TeamMembersResponse(BaseModel):
    """Response for GET /teams/{id}/members endpoint"""
    team_id: str
    members: List[TeamMemberResponse]
    total_members: int


class SharedDataCategory(BaseModel):
    """Shared data for a specific category"""
    shared: bool
    data: Optional[dict] = None
    message: Optional[str] = None


class TeamMemberSharedData(BaseModel):
    """All shared data for a team member"""
    user_id: str
    name: str
    role: TeamRole
    profile: SharedDataCategory
    activity: SharedDataCategory
    sleep: SharedDataCategory
    test_results: SharedDataCategory


class TeamSharedDataResponse(BaseModel):
    """Response for GET /teams/{id}/shared-data endpoint"""
    team_id: str
    shared_data: List[TeamMemberSharedData]


# Subscription Error Models

class SubscriptionInfo(BaseModel):
    """Subscription details in error response"""
    current_tier: str  # "free" | "monthly" | "annual"
    required_tier: str  # "monthly" | "annual" | "pro"
    upgrade_required: bool = True


class SubscriptionActionInfo(BaseModel):
    """Action information for subscription errors"""
    type: str = "upgrade"  # "upgrade" | "downgrade" | "none"
    label: str = "Upgrade to Pro"
    destination: str = "/subscription/upgrade"


class SubscriptionErrorDetail(BaseModel):
    """Detailed subscription error information"""
    code: str  # "SUBSCRIPTION_LIMIT_REACHED"
    message: str  # Short user-facing message
    detail: str  # Detailed explanation
    subscription: SubscriptionInfo
    action: SubscriptionActionInfo


class SubscriptionError(BaseModel):
    """Top-level subscription error response"""
    error: SubscriptionErrorDetail


# Invitation Token Response

class InvitationDetailsResponse(BaseModel):
    """Response for GET /invitations/token/{token} endpoint"""
    invitation_token: str
    team: dict
    invited_by: dict
    invited_email: str
    invited_at: datetime
    expires_at: datetime
    is_registered: bool


class InvitationAcceptResponse(BaseModel):
    """Response for accepting an invitation"""
    team_id: str
    status: MemberStatus
    role: TeamRole
    joined_at: datetime
    team: dict
