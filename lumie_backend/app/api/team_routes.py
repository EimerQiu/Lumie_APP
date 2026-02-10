"""
Team API Routes
"""

from fastapi import APIRouter, HTTPException, Depends, Query, status
from typing import Optional

from ..services.auth_service import get_current_user_id
from ..services.team_service import team_service
from ..models.team import (
    TeamCreate, TeamUpdate, TeamInvite,
    TeamResponse, TeamsListResponse, TeamMembersResponse,
    TeamSharedDataResponse, InvitationAcceptResponse
)

router = APIRouter(prefix="/teams", tags=["teams"])


@router.post("", response_model=TeamResponse, status_code=status.HTTP_201_CREATED)
async def create_team(
    data: TeamCreate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Create a new team

    - **Subscription limits:** Free users can create 1 team, Pro users can create up to 100 teams
    - Returns 403 with subscription error if limit reached
    """
    return await team_service.create_team(user_id, data)


@router.get("", response_model=TeamsListResponse)
async def get_teams(
    status_filter: Optional[str] = Query(None, alias="status"),
    user_id: str = Depends(get_current_user_id)
):
    """
    Get all teams user belongs to plus pending invitations

    - Returns active teams where user is member
    - Returns pending invitations
    """
    return await team_service.get_teams(user_id)


@router.get("/{team_id}", response_model=TeamResponse)
async def get_team(
    team_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Get team details

    - User must be an active member of the team
    - Returns 403 if not a member
    """
    return await team_service.get_team(team_id, user_id)


@router.put("/{team_id}", response_model=TeamResponse)
async def update_team(
    team_id: str,
    data: TeamUpdate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Update team information

    - **Admin only**
    - Update team name and/or description
    - Returns 403 if not admin
    """
    return await team_service.update_team(team_id, user_id, data)


@router.delete("/{team_id}")
async def delete_team(
    team_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Delete team (soft delete)

    - **Admin only**
    - Removes all team members
    - Returns 403 if not admin
    """
    return await team_service.delete_team(team_id, user_id)


@router.post("/{team_id}/invite", status_code=status.HTTP_201_CREATED)
async def invite_member(
    team_id: str,
    data: TeamInvite,
    user_id: str = Depends(get_current_user_id)
):
    """
    Invite a member to the team by email

    - **Admin only**
    - Sends invitation email
    - No subscription check on invite side (check happens when invitee accepts)
    - Returns 403 if not admin
    - Returns 404 if user not found
    - Returns 409 if already member or has pending invitation
    """
    return await team_service.invite_member(team_id, user_id, data.email)


@router.post("/{team_id}/accept", response_model=InvitationAcceptResponse)
async def accept_invitation(
    team_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Accept a team invitation

    - **Subscription check:** Free users can join 1 team, Pro users can join up to 100 teams
    - Returns 403 with subscription error if limit reached
    - Returns 403 if no pending invitation
    """
    return await team_service.accept_invitation(team_id, user_id)


@router.post("/{team_id}/leave")
async def leave_team(
    team_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Leave a team

    - Cannot leave if you're the only admin
    - Returns 403 if not a member
    - Returns 409 if last admin
    """
    return await team_service.leave_team(team_id, user_id)


@router.delete("/{team_id}/members/{target_user_id}")
async def remove_member(
    team_id: str,
    target_user_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Remove a member from the team

    - **Admin only**
    - Cannot remove yourself (use /leave endpoint)
    - Cannot remove another admin
    - Returns 403 if not admin
    - Returns 404 if target user not in team
    - Returns 409 if trying to remove another admin
    """
    return await team_service.remove_member(team_id, user_id, target_user_id)


@router.get("/{team_id}/members", response_model=TeamMembersResponse)
async def get_team_members(
    team_id: str,
    status_filter: Optional[str] = Query(None, alias="status"),
    role_filter: Optional[str] = Query(None, alias="role"),
    user_id: str = Depends(get_current_user_id)
):
    """
    Get all team members

    - User must be an active member
    - Returns member list with data sharing settings
    - Returns 403 if not a member
    """
    return await team_service.get_team_members(team_id, user_id)


@router.get("/{team_id}/invitations")
async def get_pending_invitations(
    team_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Get pending invitations for the team

    - **Admin only**
    - Returns list of pending invitations
    - Returns 403 if not admin
    """
    return await team_service.get_pending_invitations(team_id, user_id)


@router.get("/{team_id}/shared-data", response_model=TeamSharedDataResponse)
async def get_shared_data(
    team_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Get all shared data from team members

    - User must be an active member
    - Returns data based on each member's privacy settings
    - Returns 403 if not a member
    """
    return await team_service.get_shared_data(team_id, user_id)


@router.get("/{team_id}/members/{target_user_id}/data")
async def get_member_data(
    team_id: str,
    target_user_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Get specific member's shared data

    - User must be an active member
    - Target user must be an active member
    - Returns data based on target's privacy settings
    - Returns 403 if requester not a member
    - Returns 404 if target not a member
    """
    return await team_service.get_member_data(team_id, user_id, target_user_id)


@router.get("/invitations/token/{token}")
async def get_invitation_from_token(token: str):
    """
    Get invitation details from token (public endpoint)

    - **No authentication required**
    - Used when user clicks invitation link
    - Returns team name, inviter, and invitation status
    - Returns 400 if token invalid or expired
    - Returns 404 if invitation not found
    """
    return await team_service.get_invitation_from_token(token)


@router.post("/invitations/token/{token}/accept", response_model=InvitationAcceptResponse)
async def accept_invitation_by_token(
    token: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Accept team invitation using token

    - **Requires authentication**
    - User's email must match invitation email
    - Checks subscription limits before accepting
    - Returns 400 if token invalid or expired
    - Returns 403 if email doesn't match or limit reached
    """
    return await team_service.accept_invitation_by_token(token, user_id)
