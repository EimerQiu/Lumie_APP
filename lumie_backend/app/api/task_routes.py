"""
Task API Routes (Med-Reminder)
"""

from fastapi import APIRouter, Depends, Query, status
from typing import Optional

from ..services.auth_service import get_current_user_id
from ..services.task_service import task_service
from ..models.task import (
    TaskCreate, TaskResponse, TaskListResponse,
    TemplateCreate, TemplateResponse, TemplateListResponse,
    BatchGenerateRequest, BatchGenerateResponse,
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

    - **Subscription limits:** Free users limited to 6 active tasks
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

    - **Subscription limits:** Free users limited to 6 active tasks, Pro unlimited
    - Returns 403 with subscription error if limit reached
    - For team tasks: set team_id and user_id (must be team admin)
    """
    return await task_service.create_task(user_id, data)


@router.get("", response_model=TaskListResponse)
async def get_tasks(
    status_filter: Optional[str] = Query(None, alias="status"),
    date: Optional[str] = Query(None, description="yyyy-MM-dd"),
    user_id: str = Depends(get_current_user_id)
):
    """
    List tasks for current user

    - Optional filters: status (pending/completed/overdue), date (yyyy-MM-dd)
    - Automatically marks overdue tasks
    - Sorted by open_datetime ascending
    """
    return await task_service.get_tasks(user_id, status_filter=status_filter, date=date)


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
    return await task_service.complete_task(task_id, user_id)


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
