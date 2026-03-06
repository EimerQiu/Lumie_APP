"""
Admin Task API Routes (Med-Reminder Admin Dashboard)
"""

from fastapi import APIRouter, Depends, Query
from typing import Optional

from ..services.auth_service import get_current_user_id
from ..services.admin_task_service import admin_task_service
from ..models.task import AdminTaskListResponse, AdminTaskCompleteRequest, AdminTaskData

router = APIRouter(prefix="/admin", tags=["admin-tasks"])


@router.get("/task-list-ios", response_model=AdminTaskListResponse)
async def get_admin_task_list(
    email: Optional[str] = Query(None, description="Filter by member email"),
    time_zone: str = Query("UTC", description="IANA timezone"),
    current_time: Optional[str] = Query(None, description="Current time ISO8601"),
    previous_offset: int = Query(0, ge=0, description="Pagination offset for previous tasks"),
    upcoming_offset: int = Query(0, ge=0, description="Pagination offset for upcoming tasks"),
    user_id: str = Depends(get_current_user_id),
):
    """
    Admin dashboard: global task view across all team members

    - Only accessible by team admins
    - Returns previous and upcoming tasks split by current time
    - Supports email filter and pagination
    """
    return await admin_task_service.get_admin_task_list(
        admin_user_id=user_id,
        email=email,
        time_zone=time_zone,
        current_time=current_time,
        previous_offset=previous_offset,
        upcoming_offset=upcoming_offset,
    )


@router.post("/task_complete")
async def admin_complete_task(
    data: AdminTaskCompleteRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Admin marks any team member's task as completed

    - Admin must be admin of the team the task belongs to
    - Task status updates to completed but remains visible in admin list
    """
    return await admin_task_service.admin_complete_task(
        admin_user_id=user_id,
        task_id=data.task_id,
        time_zone=data.time_zone,
    )


@router.delete("/delete_task/{task_id}")
async def admin_delete_task(
    task_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """
    Admin permanently deletes a team member's task

    - Admin must be admin of the team the task belongs to, or the task creator
    """
    return await admin_task_service.admin_delete_task(
        admin_user_id=user_id,
        task_id=task_id,
    )


@router.get("/reward-calc")
async def get_reward_calc_tasks(
    email: str = Query(..., description="Member email (required)"),
    time_zone: str = Query("UTC", description="IANA timezone"),
    offset: int = Query(0, ge=0, description="Pagination offset"),
    user_id: str = Depends(get_current_user_id),
):
    """
    Get tasks for reward calculation view

    - Returns tasks in chronological order for a specific member
    - Pagination: 10 tasks per page
    - Calculation is done client-side
    """
    return await admin_task_service.get_reward_calc_tasks(
        admin_user_id=user_id,
        email=email,
        time_zone=time_zone,
        offset=offset,
    )
