"""
Team Service
Business logic for team operations
"""

import uuid
from datetime import datetime, timedelta
from typing import List, Optional
from fastapi import HTTPException, status
import jwt

from ..core.database import get_database
from ..core.config import settings
from ..core.subscription_helpers import get_team_limit, raise_subscription_limit_error
from ..models.team import (
    Team, TeamMember, TeamRole, MemberStatus,
    TeamCreate, TeamUpdate, TeamInvite,
    TeamResponse, TeamMemberResponse, TeamsListResponse,
    TeamInvitation, TeamMembersResponse, AdminInfo,
    DataSharing, SharedDataCategory, TeamMemberSharedData,
    TeamSharedDataResponse, InvitationDetailsResponse,
    InvitationAcceptResponse
)
from ..models.user import SubscriptionTier
from .email_service import email_service


class TeamService:
    """Service for handling team operations"""

    async def get_user_team_count(self, user_id: str) -> int:
        """
        Count number of teams user is an active member of

        Args:
            user_id: User ID to count teams for

        Returns:
            Number of teams where user status is MEMBER
        """
        db = get_database()
        count = await db.team_members.count_documents({
            "user_id": user_id,
            "status": MemberStatus.MEMBER.value
        })
        return count

    async def create_team(self, user_id: str, data: TeamCreate) -> TeamResponse:
        """
        Create a new team with subscription limit check

        Args:
            user_id: ID of user creating the team
            data: Team creation data

        Returns:
            TeamResponse with created team details

        Raises:
            HTTPException: If subscription limit reached or other error
        """
        db = get_database()

        # Get user and check subscription tier
        user = await db.users.find_one({"user_id": user_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )

        subscription = user.get("subscription", {})
        tier_value = subscription.get("tier", "free")
        subscription_tier = SubscriptionTier(tier_value)

        # Check team limit
        current_count = await self.get_user_team_count(user_id)
        limit = get_team_limit(subscription_tier)

        if current_count >= limit:
            raise_subscription_limit_error(
                user_tier=tier_value,
                current_count=current_count,
                limit=limit,
                action="create"
            )

        # Create team
        team_id = str(uuid.uuid4())
        now = datetime.utcnow()

        team_doc = {
            "team_id": team_id,
            "name": data.name,
            "description": data.description,
            "created_by": user_id,
            "created_at": now,
            "updated_at": now,
            "is_deleted": False,
            "deleted_at": None
        }

        await db.teams.insert_one(team_doc)

        # Add creator as admin member
        member_doc = {
            "team_id": team_id,
            "user_id": user_id,
            "role": TeamRole.ADMIN.value,
            "status": MemberStatus.MEMBER.value,
            "invited_by": user_id,
            "invited_at": now,
            "joined_at": now
        }

        await db.team_members.insert_one(member_doc)

        return TeamResponse(
            team_id=team_id,
            name=data.name,
            description=data.description,
            role=TeamRole.ADMIN,
            status=MemberStatus.MEMBER,
            member_count=1,
            created_at=now,
            created_by=user_id
        )

    async def get_teams(self, user_id: str) -> TeamsListResponse:
        """
        Get all teams user belongs to plus pending invitations

        Args:
            user_id: ID of user

        Returns:
            TeamsListResponse with active teams and pending invitations
        """
        db = get_database()

        # Get all team memberships (both active and pending)
        memberships = await db.team_members.find({"user_id": user_id}).to_list(length=None)

        teams = []
        pending_invitations = []

        for membership in memberships:
            team = await db.teams.find_one({
                "team_id": membership["team_id"],
                "is_deleted": False
            })

            if not team:
                continue

            if membership["status"] == MemberStatus.MEMBER.value:
                # Active team - count members
                member_count = await db.team_members.count_documents({
                    "team_id": team["team_id"],
                    "status": MemberStatus.MEMBER.value
                })

                teams.append(TeamResponse(
                    team_id=team["team_id"],
                    name=team["name"],
                    description=team.get("description"),
                    role=TeamRole(membership["role"]),
                    status=MemberStatus.MEMBER,
                    member_count=member_count,
                    created_at=team["created_at"],
                    created_by=team["created_by"]
                ))
            else:
                # Pending invitation - get inviter name
                inviter = await db.users.find_one({"user_id": membership["invited_by"]})
                inviter_profile = await db.profiles.find_one({"user_id": membership["invited_by"]})

                inviter_name = inviter_profile.get("name", "Unknown") if inviter_profile else "Unknown"

                pending_invitations.append(TeamInvitation(
                    team_id=team["team_id"],
                    team_name=team["name"],
                    invited_by_name=inviter_name,
                    invited_at=membership["invited_at"]
                ))

        return TeamsListResponse(
            teams=teams,
            pending_invitations=pending_invitations
        )

    async def get_team(self, team_id: str, user_id: str) -> TeamResponse:
        """
        Get team details (must be member)

        Args:
            team_id: Team ID
            user_id: Requesting user ID

        Returns:
            TeamResponse with team details

        Raises:
            HTTPException: If not a member or team not found
        """
        db = get_database()

        # Check if user is member
        membership = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "status": MemberStatus.MEMBER.value
        })

        if not membership:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not a member of this team"
            )

        # Get team
        team = await db.teams.find_one({"team_id": team_id, "is_deleted": False})
        if not team:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Team not found"
            )

        # Count members
        member_count = await db.team_members.count_documents({
            "team_id": team_id,
            "status": MemberStatus.MEMBER.value
        })

        # Get admins
        admin_members = await db.team_members.find({
            "team_id": team_id,
            "role": TeamRole.ADMIN.value,
            "status": MemberStatus.MEMBER.value
        }).to_list(length=None)

        admins = []
        for admin_member in admin_members:
            admin_profile = await db.profiles.find_one({"user_id": admin_member["user_id"]})
            if admin_profile:
                admins.append(AdminInfo(
                    user_id=admin_member["user_id"],
                    name=admin_profile.get("name", "Unknown")
                ))

        return TeamResponse(
            team_id=team["team_id"],
            name=team["name"],
            description=team.get("description"),
            role=TeamRole(membership["role"]),
            status=MemberStatus.MEMBER,
            member_count=member_count,
            created_at=team["created_at"],
            created_by=team["created_by"],
            admins=admins
        )

    async def update_team(self, team_id: str, user_id: str, data: TeamUpdate) -> TeamResponse:
        """
        Update team info (admin only)

        Args:
            team_id: Team ID
            user_id: Requesting user ID
            data: Team update data

        Returns:
            TeamResponse with updated team

        Raises:
            HTTPException: If not admin or validation fails
        """
        db = get_database()

        # Check if user is admin
        membership = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "role": TeamRole.ADMIN.value,
            "status": MemberStatus.MEMBER.value
        })

        if not membership:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only admins can update team info"
            )

        # Build update dict
        update_doc = {"updated_at": datetime.utcnow()}
        if data.name is not None:
            update_doc["name"] = data.name
        if data.description is not None:
            update_doc["description"] = data.description

        # Update team
        await db.teams.update_one(
            {"team_id": team_id},
            {"$set": update_doc}
        )

        # Return updated team
        return await self.get_team(team_id, user_id)

    async def delete_team(self, team_id: str, user_id: str) -> dict:
        """
        Soft delete team (admin only)

        Args:
            team_id: Team ID
            user_id: Requesting user ID

        Returns:
            Dict with success message

        Raises:
            HTTPException: If not admin
        """
        db = get_database()

        # Check if user is admin
        membership = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "role": TeamRole.ADMIN.value,
            "status": MemberStatus.MEMBER.value
        })

        if not membership:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only admins can delete teams"
            )

        # Soft delete team
        now = datetime.utcnow()
        await db.teams.update_one(
            {"team_id": team_id},
            {"$set": {"is_deleted": True, "deleted_at": now, "updated_at": now}}
        )

        # Remove all team members
        await db.team_members.delete_many({"team_id": team_id})

        return {
            "message": "Team deleted successfully",
            "deleted_at": now.isoformat(),
            "recovery_deadline": (now + timedelta(days=30)).isoformat()
        }

    def generate_invitation_token(self, team_id: str, email: str, expires_in_days: int = 30) -> str:
        """
        Generate JWT token for team invitation

        Args:
            team_id: Team ID
            email: Invitee email
            expires_in_days: Token expiration in days

        Returns:
            JWT token string
        """
        payload = {
            "team_id": team_id,
            "email": email,
            "type": "team_invitation",
            "exp": datetime.utcnow() + timedelta(days=expires_in_days),
            "iat": datetime.utcnow()
        }
        return jwt.encode(payload, settings.SECRET_KEY, algorithm="HS256")

    def decode_invitation_token(self, token: str) -> Optional[dict]:
        """
        Decode and validate invitation token

        Args:
            token: JWT token

        Returns:
            Payload dict or None if invalid
        """
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=["HS256"])
            if payload.get("type") != "team_invitation":
                return None
            return payload
        except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
            return None

    async def invite_member(self, team_id: str, inviter_user_id: str, email: str) -> dict:
        """
        Invite member by email (admin only)

        Args:
            team_id: Team ID
            inviter_user_id: User ID of inviter (must be admin)
            email: Email of user to invite

        Returns:
            Dict with invitation details

        Raises:
            HTTPException: If not admin or other validation fails
        """
        db = get_database()

        # Check if inviter is admin
        inviter_member = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": inviter_user_id,
            "role": TeamRole.ADMIN.value,
            "status": MemberStatus.MEMBER.value
        })

        if not inviter_member:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only admins can invite members"
            )

        # Get team and inviter details
        team = await db.teams.find_one({"team_id": team_id, "is_deleted": False})
        if not team:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Team not found"
            )

        inviter = await db.users.find_one({"user_id": inviter_user_id})
        inviter_profile = await db.profiles.find_one({"user_id": inviter_user_id})
        inviter_name = inviter_profile.get("name", "Unknown") if inviter_profile else "Unknown"

        # Check if email is registered
        invited_user = await db.users.find_one({"email": email})

        if invited_user:
            # User is registered - check if already in team
            existing_member = await db.team_members.find_one({
                "team_id": team_id,
                "user_id": invited_user["user_id"]
            })

            if existing_member:
                if existing_member["status"] == MemberStatus.MEMBER.value:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="User is already a team member"
                    )
                elif existing_member["status"] == MemberStatus.PENDING.value:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="User already has a pending invitation"
                    )

            # Create pending invitation
            now = datetime.utcnow()
            await db.team_members.insert_one({
                "team_id": team_id,
                "user_id": invited_user["user_id"],
                "role": TeamRole.MEMBER.value,
                "status": MemberStatus.PENDING.value,
                "invited_by": inviter_user_id,
                "invited_at": now,
                "joined_at": None
            })
        else:
            # User not registered - store invitation by email
            # Check if email invitation already exists
            existing_invitation = await db.pending_invitations.find_one({
                "team_id": team_id,
                "email": email.lower()
            })

            if existing_invitation:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Invitation already sent to this email"
                )

            # Store email-based invitation
            now = datetime.utcnow()
            await db.pending_invitations.insert_one({
                "team_id": team_id,
                "email": email.lower(),
                "invited_by": inviter_user_id,
                "invited_at": now,
                "expires_at": now + timedelta(days=30)
            })

        # Generate invitation token
        invitation_token = self.generate_invitation_token(team_id, email)
        # Use production domain for invitation link
        invitation_link = f"https://yumo.org/invite/{invitation_token}"

        # Send invitation email
        email_service.send_invitation_email(
            to_email=email,
            inviter_name=inviter_name,
            team_name=team["name"],
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

    async def accept_invitation(self, team_id: str, user_id: str) -> InvitationAcceptResponse:
        """
        Accept team invitation with subscription check

        Args:
            team_id: Team ID
            user_id: User ID accepting invitation

        Returns:
            InvitationAcceptResponse with team details

        Raises:
            HTTPException: If no invitation, limit reached, or other error
        """
        db = get_database()

        # Check if user has pending invitation
        membership = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "status": MemberStatus.PENDING.value
        })

        if not membership:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No pending invitation found"
            )

        # Get user and check subscription
        user = await db.users.find_one({"user_id": user_id})
        subscription = user.get("subscription", {})
        tier_value = subscription.get("tier", "free")
        subscription_tier = SubscriptionTier(tier_value)

        # Check team limit
        current_count = await self.get_user_team_count(user_id)
        limit = get_team_limit(subscription_tier)

        if current_count >= limit:
            raise_subscription_limit_error(
                user_tier=tier_value,
                current_count=current_count,
                limit=limit,
                action="join"
            )

        # Accept invitation
        now = datetime.utcnow()
        await db.team_members.update_one(
            {"team_id": team_id, "user_id": user_id},
            {"$set": {"status": MemberStatus.MEMBER.value, "joined_at": now}}
        )

        # Get team details
        team = await db.teams.find_one({"team_id": team_id})

        return InvitationAcceptResponse(
            team_id=team_id,
            status=MemberStatus.MEMBER,
            role=TeamRole(membership["role"]),
            joined_at=now,
            team={
                "name": team["name"],
                "description": team.get("description"),
                "member_count": await db.team_members.count_documents({
                    "team_id": team_id,
                    "status": MemberStatus.MEMBER.value
                })
            }
        )

    async def leave_team(self, team_id: str, user_id: str) -> dict:
        """
        Leave team (cannot leave if only admin)

        Args:
            team_id: Team ID
            user_id: User ID leaving

        Returns:
            Dict with success message

        Raises:
            HTTPException: If last admin or not member
        """
        db = get_database()

        # Check if user is member
        membership = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "status": MemberStatus.MEMBER.value
        })

        if not membership:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not a member of this team"
            )

        # If admin, check if only admin
        if membership["role"] == TeamRole.ADMIN.value:
            admin_count = await db.team_members.count_documents({
                "team_id": team_id,
                "role": TeamRole.ADMIN.value,
                "status": MemberStatus.MEMBER.value
            })

            if admin_count <= 1:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Cannot leave team as the only admin. Promote another member first or delete the team."
                )

        # Remove member
        await db.team_members.delete_one({
            "team_id": team_id,
            "user_id": user_id
        })

        team = await db.teams.find_one({"team_id": team_id})

        return {
            "message": "Successfully left the team",
            "team_name": team["name"],
            "left_at": datetime.utcnow().isoformat()
        }

    async def remove_member(self, team_id: str, admin_user_id: str, target_user_id: str) -> dict:
        """
        Remove member from team (admin only, cannot remove self)

        Args:
            team_id: Team ID
            admin_user_id: User ID of admin performing removal
            target_user_id: User ID to remove

        Returns:
            Dict with success message

        Raises:
            HTTPException: If not admin or trying to remove self
        """
        db = get_database()

        # Check if requester is admin
        admin_member = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": admin_user_id,
            "role": TeamRole.ADMIN.value,
            "status": MemberStatus.MEMBER.value
        })

        if not admin_member:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only admins can remove members"
            )

        # Cannot remove self
        if admin_user_id == target_user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot remove yourself. Use /leave endpoint instead."
            )

        # Get target member
        target_member = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": target_user_id
        })

        if not target_member:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User is not a member of this team"
            )

        # Cannot remove another admin
        if target_member["role"] == TeamRole.ADMIN.value:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot remove another admin"
            )

        # Remove member
        await db.team_members.delete_one({
            "team_id": team_id,
            "user_id": target_user_id
        })

        target_profile = await db.profiles.find_one({"user_id": target_user_id})
        target_name = target_profile.get("name", "Unknown") if target_profile else "Unknown"

        return {
            "message": "Member removed successfully",
            "removed_user": {
                "user_id": target_user_id,
                "name": target_name
            },
            "removed_at": datetime.utcnow().isoformat()
        }

    async def get_team_members(self, team_id: str, user_id: str) -> TeamMembersResponse:
        """
        Get all team members (must be member)

        Args:
            team_id: Team ID
            user_id: Requesting user ID

        Returns:
            TeamMembersResponse with member list

        Raises:
            HTTPException: If not member
        """
        db = get_database()

        # Check if user is member
        membership = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "status": MemberStatus.MEMBER.value
        })

        if not membership:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not a member of this team"
            )

        # Get all members
        team_members = await db.team_members.find({
            "team_id": team_id,
            "status": MemberStatus.MEMBER.value
        }).to_list(length=None)

        members = []
        for member in team_members:
            user_doc = await db.users.find_one({"user_id": member["user_id"]})
            profile = await db.profiles.find_one({"user_id": member["user_id"]})

            if user_doc and profile:
                # Get data sharing settings (placeholder - would come from settings in real implementation)
                data_sharing = DataSharing(
                    profile=True,
                    activity=False,
                    sleep=False,
                    test_results=False
                )

                members.append(TeamMemberResponse(
                    user_id=member["user_id"],
                    name=profile.get("name", "Unknown"),
                    email=user_doc["email"],
                    role=TeamRole(member["role"]),
                    status=MemberStatus(member["status"]),
                    joined_at=member.get("joined_at"),
                    data_sharing=data_sharing
                ))

        return TeamMembersResponse(
            team_id=team_id,
            members=members,
            total_members=len(members)
        )

    async def get_pending_invitations(self, team_id: str, user_id: str) -> dict:
        """
        Get pending invitations for team (admin only)

        Args:
            team_id: Team ID
            user_id: Requesting user ID (must be admin)

        Returns:
            Dict with pending invitations

        Raises:
            HTTPException: If not admin
        """
        db = get_database()

        # Check if user is admin
        admin_member = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "role": TeamRole.ADMIN.value,
            "status": MemberStatus.MEMBER.value
        })

        if not admin_member:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only admins can view pending invitations"
            )

        # Get pending invitations
        pending = await db.team_members.find({
            "team_id": team_id,
            "status": MemberStatus.PENDING.value
        }).to_list(length=None)

        invitations = []
        for inv in pending:
            user_doc = await db.users.find_one({"user_id": inv["user_id"]})
            profile = await db.profiles.find_one({"user_id": inv["user_id"]})
            inviter_profile = await db.profiles.find_one({"user_id": inv["invited_by"]})

            if user_doc:
                invitations.append({
                    "user_id": inv["user_id"],
                    "email": user_doc["email"],
                    "name": profile.get("name", "Unknown") if profile else "Unknown",
                    "invited_by": {
                        "user_id": inv["invited_by"],
                        "name": inviter_profile.get("name", "Unknown") if inviter_profile else "Unknown"
                    },
                    "invited_at": inv["invited_at"].isoformat(),
                    "days_pending": (datetime.utcnow() - inv["invited_at"]).days
                })

        return {
            "team_id": team_id,
            "pending_invitations": invitations,
            "total_pending": len(invitations)
        }

    async def get_shared_data(self, team_id: str, user_id: str) -> TeamSharedDataResponse:
        """
        Get all shared data from team members

        Args:
            team_id: Team ID
            user_id: Requesting user ID (must be member)

        Returns:
            TeamSharedDataResponse with shared data

        Raises:
            HTTPException: If not member
        """
        db = get_database()

        # Check if user is member
        membership = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "status": MemberStatus.MEMBER.value
        })

        if not membership:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not a member of this team"
            )

        # Get all members
        team_members = await db.team_members.find({
            "team_id": team_id,
            "status": MemberStatus.MEMBER.value
        }).to_list(length=None)

        shared_data = []
        for member in team_members:
            profile = await db.profiles.find_one({"user_id": member["user_id"]})

            if profile:
                # Placeholder data - in real implementation, would check privacy settings
                shared_data.append(TeamMemberSharedData(
                    user_id=member["user_id"],
                    name=profile.get("name", "Unknown"),
                    role=TeamRole(member["role"]),
                    profile=SharedDataCategory(
                        shared=True,
                        data={"age": profile.get("age"), "role": profile.get("role")}
                    ),
                    activity=SharedDataCategory(
                        shared=False,
                        message="Not shared"
                    ),
                    sleep=SharedDataCategory(
                        shared=False,
                        message="Not shared"
                    ),
                    test_results=SharedDataCategory(
                        shared=False,
                        message="Not shared"
                    )
                ))

        return TeamSharedDataResponse(
            team_id=team_id,
            shared_data=shared_data
        )

    async def get_member_data(self, team_id: str, requester_user_id: str, target_user_id: str) -> dict:
        """
        Get specific member's shared data

        Args:
            team_id: Team ID
            requester_user_id: User requesting data (must be member)
            target_user_id: User whose data to retrieve

        Returns:
            Dict with member's shared data

        Raises:
            HTTPException: If not member or target not member
        """
        db = get_database()

        # Check if requester is member
        requester_member = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": requester_user_id,
            "status": MemberStatus.MEMBER.value
        })

        if not requester_member:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not a member of this team"
            )

        # Check if target is member
        target_member = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": target_user_id,
            "status": MemberStatus.MEMBER.value
        })

        if not target_member:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User is not a member of this team"
            )

        # Get target's profile
        profile = await db.profiles.find_one({"user_id": target_user_id})

        if not profile:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Profile not found"
            )

        # Placeholder - would check privacy settings
        return {
            "user_id": target_user_id,
            "name": profile.get("name", "Unknown"),
            "role": TeamRole(target_member["role"]).value,
            "data_sharing": {
                "profile": {
                    "shared": True,
                    "name": profile.get("name"),
                    "age": profile.get("age"),
                    "role": profile.get("role")
                },
                "activity": {
                    "shared": False
                },
                "sleep": {
                    "shared": False
                },
                "test_results": {
                    "shared": False
                }
            }
        }
    async def get_invitation_from_token(self, token: str) -> dict:
        """
        Get invitation details from token

        Args:
            token: Invitation JWT token

        Returns:
            Dict with team and invitation details

        Raises:
            HTTPException: If token invalid or expired
        """
        payload = self.decode_invitation_token(token)
        if not payload:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired invitation link"
            )

        db = get_database()
        team_id = payload["team_id"]
        email = payload["email"]

        # Get team details
        team = await db.teams.find_one({"team_id": team_id, "is_deleted": False})
        if not team:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Team not found or has been deleted"
            )

        # Check if this is a pending email invitation or user invitation
        user = await db.users.find_one({"email": email.lower()})

        if user:
            # User registered - check if they have a pending invitation
            membership = await db.team_members.find_one({
                "team_id": team_id,
                "user_id": user["user_id"]
            })

            if membership:
                if membership["status"] == MemberStatus.MEMBER.value:
                    return {
                        "team_id": team_id,
                        "team_name": team["name"],
                        "team_description": team.get("description"),
                        "email": email,
                        "status": "already_member",
                        "message": "You are already a member of this team"
                    }
                elif membership["status"] == MemberStatus.PENDING.value:
                    # Get inviter name
                    inviter = await db.profiles.find_one({"user_id": membership["invited_by"]})
                    inviter_name = inviter.get("name", "Unknown") if inviter else "Unknown"

                    return {
                        "team_id": team_id,
                        "team_name": team["name"],
                        "team_description": team.get("description"),
                        "invited_by": inviter_name,
                        "email": email,
                        "status": "pending",
                        "message": "You have been invited to join this team"
                    }
        else:
            # User not registered - check pending invitations
            pending = await db.pending_invitations.find_one({
                "team_id": team_id,
                "email": email.lower()
            })

            if pending:
                inviter = await db.profiles.find_one({"user_id": pending["invited_by"]})
                inviter_name = inviter.get("name", "Unknown") if inviter else "Unknown"

                return {
                    "team_id": team_id,
                    "team_name": team["name"],
                    "team_description": team.get("description"),
                    "invited_by": inviter_name,
                    "email": email,
                    "status": "needs_signup",
                    "message": f"Sign up with {email} to join this team"
                }

        # No invitation found
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invitation not found or has been cancelled"
        )

    async def accept_invitation_by_token(self, token: str, user_id: str) -> InvitationAcceptResponse:
        """
        Accept team invitation using token (for logged-in users)

        Args:
            token: Invitation JWT token
            user_id: User ID accepting invitation

        Returns:
            InvitationAcceptResponse with team details

        Raises:
            HTTPException: If token invalid, expired, or acceptance fails
        """
        payload = self.decode_invitation_token(token)
        if not payload:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired invitation link"
            )

        team_id = payload["team_id"]
        email = payload["email"]

        # Verify user's email matches the invitation
        db = get_database()
        user = await db.users.find_one({"user_id": user_id})
        if not user or user["email"].lower() != email.lower():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This invitation was sent to a different email address"
            )

        # Use the existing accept_invitation method
        return await self.accept_invitation(team_id, user_id)

    async def process_pending_invitations(self, user_id: str, email: str) -> int:
        """
        Process pending invitations for newly registered user

        Converts email-based invitations to actual team memberships

        Args:
            user_id: New user's ID
            email: User's email address

        Returns:
            Number of invitations processed
        """
        db = get_database()

        # Find all pending invitations for this email
        pending = await db.pending_invitations.find({"email": email.lower()}).to_list(length=None)

        count = 0
        for invitation in pending:
            # Check if team still exists
            team = await db.teams.find_one({
                "team_id": invitation["team_id"],
                "is_deleted": False
            })

            if not team:
                # Team was deleted, skip this invitation
                await db.pending_invitations.delete_one({"_id": invitation["_id"]})
                continue

            # Check if invitation expired
            if invitation.get("expires_at") and datetime.utcnow() > invitation["expires_at"]:
                await db.pending_invitations.delete_one({"_id": invitation["_id"]})
                continue

            # Check if user is already a member
            existing = await db.team_members.find_one({
                "team_id": invitation["team_id"],
                "user_id": user_id
            })

            if existing:
                # Already a member, just delete the invitation
                await db.pending_invitations.delete_one({"_id": invitation["_id"]})
                continue

            # Create pending team membership
            await db.team_members.insert_one({
                "team_id": invitation["team_id"],
                "user_id": user_id,
                "role": TeamRole.MEMBER.value,
                "status": MemberStatus.PENDING.value,
                "invited_by": invitation["invited_by"],
                "invited_at": invitation["invited_at"],
                "joined_at": None
            })

            # Delete the email invitation
            await db.pending_invitations.delete_one({"_id": invitation["_id"]})
            count += 1

        return count


# Singleton instance
team_service = TeamService()
