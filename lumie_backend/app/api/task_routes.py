"""
Task API Routes (Med-Reminder)
"""

from fastapi import APIRouter, Depends, Query, status
from typing import Optional

import asyncio

from ..services.auth_service import get_current_user_id
from ..services.task_service import task_service
from ..services.ai_tips_service import get_ai_tips
from ..services.dayprint_service import log_task_completed
from ..models.task import (
    TaskCreate, TaskResponse, TaskListResponse,
    TemplateCreate, TemplateUpdate, TemplateResponse, TemplateListResponse,
    BatchGenerateRequest, BatchGenerateResponse,
    AiTipsRequest, AiTipsResponse,
)

router = APIRouter(prefix="/tasks", tags=["tasks"])


# ---- Templates (must be before /{task_id} routes to avoid path conflicts) ----

@router.get("/templates", response_model=TemplateListResponse)
async def get_templates(
    user_id: str = Depends(get_current_user_id)
):
    """
    List user's task templates

    - Returns all templates created by the current user
    """
    return await task_service.get_templates(user_id)


@router.post("/templates", response_model=TemplateResponse, status_code=status.HTTP_201_CREATED)
async def create_template(
    data: TemplateCreate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Create a new task template

    - Template defines time windows for recurring tasks
    - Used for batch task generation
    """
    return await task_service.create_template(user_id, data)


@router.get("/templates/{template_id}", response_model=TemplateResponse)
async def get_template(
    template_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Get template detail

    - Must be the template creator
    """
    return await task_service.get_template(template_id, user_id)


@router.put("/templates/{template_id}", response_model=TemplateResponse)
async def update_template(
    template_id: str,
    data: TemplateUpdate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Update a template

    - Must be the template creator
    - All fields are optional (partial update)
    - Does not affect already-generated tasks
    """
    return await task_service.update_template(template_id, user_id, data)


@router.delete("/templates/{template_id}")
async def delete_template(
    template_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Delete a template

    - Must be the template creator
    - Does not affect already-created tasks
    """
    return await task_service.delete_template(template_id, user_id)


# ---- Batch Generation ----

@router.post("/batch/preview")
async def batch_preview(
    data: BatchGenerateRequest,
    user_id: str = Depends(get_current_user_id)
):
    """
    Preview tasks that would be generated from a template

    - Returns task count and preview list without creating tasks
    """
    return await task_service.batch_preview(user_id, data)


@router.post("/batch/generate", response_model=BatchGenerateResponse, status_code=status.HTTP_201_CREATED)
async def batch_generate(
    data: BatchGenerateRequest,
    user_id: str = Depends(get_current_user_id)
):
    """
    Generate tasks from template for a date range

    - **Subscription limits:** Free users limited to 7-day date range
    - Creates tasks for each time window in each day of the range
    """
    return await task_service.batch_generate(user_id, data)


# ---- Tasks ----

@router.post("", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    data: TaskCreate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Create a new task

    - **Subscription limits:** Free users limited to 7-day date range, Pro unlimited
    - Returns 403 with subscription error if date range exceeded
    - For team tasks: set team_id and user_id (must be team admin)
    """
    return await task_service.create_task(user_id, data)


@router.get("", response_model=TaskListResponse)
async def get_tasks(
    date: Optional[str] = Query(None, description="yyyy-MM-dd"),
    timezone: Optional[str] = Query(None, description="User's timezone (e.g., America/Los_Angeles). If not provided, uses profile timezone."),
    user_id: str = Depends(get_current_user_id)
):
    """
    List tasks for current user

    - Default: returns only tasks within current open/close window and not done
    - Optional date filter: returns all tasks for that date (yyyy-MM-dd)
    - Sorted by open_datetime ascending
    """
    return await task_service.get_tasks(user_id, date=date, timezone=timezone)


@router.post("/{task_id}/complete", response_model=TaskResponse)
async def complete_task(
    task_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Mark a task as completed

    - Only the assigned user can complete
    - Records completion timestamp
    """
    result = await task_service.complete_task(task_id, user_id)
    asyncio.create_task(log_task_completed(user_id, result.task_name, result.task_type))
    return result


@router.post("/{task_id}/extend", response_model=TaskResponse)
async def extend_task(
    task_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Extend a task's close_datetime by 10% of its duration.

    - Only the assigned user can extend
    - Cannot extend a completed task
    """
    return await task_service.extend_task(task_id, user_id)


@router.delete("/{task_id}")
async def delete_task(
    task_id: str,
    user_id: str = Depends(get_current_user_id)
):
    """
    Delete a task

    - Assigned user or task creator can delete
    """
    return await task_service.delete_task(task_id, user_id)


# ---- AI Tips ----

@router.post("/ai-tips", response_model=AiTipsResponse)
async def ai_tips(
    data: AiTipsRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Generate a personalised AI tip based on task completion history.

    - Analyses tasks from the past `days_back` days (default 30, max 90)
    - Returns a single motivating sentence and task statistics
    """
    return await get_ai_tips(
        user_id=user_id,
        days_back=data.days_back,
        time_zone=data.time_zone,
    )
