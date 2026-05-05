"""
Task API Routes (Med-Reminder)
"""

from fastapi import APIRouter, Body, Depends, Query, status, File, UploadFile
from typing import Optional

import asyncio
import logging

from ..core.database import get_database
from ..services.auth_service import get_current_user_id
from ..services.task_service import task_service
from ..services.meal_service import meal_service
from ..services.ai_tips_service import get_ai_tips
from ..services.dayprint_service import log_task_completed
from ..models.task import (
    TaskCreate, TaskUpdate, TaskResponse, TaskListResponse,
    TaskType,
    TemplateCreate, TemplateUpdate, TemplateResponse, TemplateListResponse,
    BatchGenerateRequest, BatchGenerateResponse,
    AiTipsRequest, AiTipsResponse,
)

logger = logging.getLogger(__name__)


async def _bridge_nutrition_task_to_meal(
    task_id: str,
    *,
    emit_dayprint: bool = False,
) -> None:
    """Fire-and-forget: when a Nutrition task is completed, mirror it as a Meal record.

    PRD Phase-1 backward compatibility (§9): Nutrition Task continues to work as
    today; a structured Meal is created in parallel so the meal feed/history
    surfaces it. Best-effort — failures are logged but do not affect task completion.
    """
    try:
        db = get_database()
        task = await db.tasks.find_one({"task_id": task_id})
        if not task or task.get("task_type") != TaskType.NUTRITION.value:
            return
        await meal_service.create_meal_from_nutrition_task(
            task,
            emit_dayprint=emit_dayprint,
        )
    except Exception as exc:
        logger.warning("Nutrition→Meal bridge failed for task %s: %s", task_id, exc)

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
    result = await task_service.create_task(user_id, data)
    # Auto-sync Nutrition tasks into the Meal feature so the user sees them
    # without re-entering. Bridge is fire-and-forget; helper checks task_type.
    if result.task_type == TaskType.NUTRITION:
        asyncio.create_task(_bridge_nutrition_task_to_meal(result.task_id))
    return result


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


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: str,
    data: TaskUpdate,
    user_id: str = Depends(get_current_user_id),
):
    """
    Edit a task's name, type, time window, or description.

    - Only the task owner or creator can edit
    - Datetime fields are in the user's local timezone; include `timezone` for correct conversion
    """
    result = await task_service.update_task(task_id, user_id, data)
    # Sync into Meals on every edit (note, team move, type change to Nutrition).
    # Bridge helper re-fetches the task and skips non-Nutrition types.
    if result.task_type == TaskType.NUTRITION:
        asyncio.create_task(_bridge_nutrition_task_to_meal(task_id))
    return result


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
    asyncio.create_task(
        log_task_completed(
            user_id,
            result.task_name,
            result.task_type,
            source_task_id=task_id,
        )
    )
    if result.task_type == TaskType.NUTRITION:
        asyncio.create_task(
            _bridge_nutrition_task_to_meal(task_id, emit_dayprint=True)
        )
    return result


@router.post("/{task_id}/attachments")
async def upload_task_attachments(
    task_id: str,
    files: list[UploadFile] = File(...),
    user_id: str = Depends(get_current_user_id),
):
    """
    Upload task check-in media attachments.

    - Supports image/* and video/*
    - Max 99 files per request and per task total
    """
    saved = await task_service.upload_task_attachments(task_id, user_id, files)
    # Refresh the linked Meal's image set if this task is a Nutrition task.
    # Helper re-fetches the task and silently no-ops for non-Nutrition types.
    asyncio.create_task(_bridge_nutrition_task_to_meal(task_id))
    return {"uploaded": saved, "count": len(saved)}


@router.post("/nutrition/analyze-images")
async def analyze_nutrition_images(
    files: list[UploadFile] = File(...),
    user_id: str = Depends(get_current_user_id),
):
    """
    Analyze selected food images and return one concise nutrition sentence.

    - Frontend calls this immediately after photo selection in completion dialog
    - Requires authentication
    """
    _ = user_id  # auth gate
    summary = await task_service.analyze_nutrition_uploads(files)
    return {"summary": summary}


@router.post("/medicine/analyze-images")
async def analyze_medicine_images(
    files: list[UploadFile] = File(...),
    user_id: str = Depends(get_current_user_id),
):
    """
    Analyze prescription photos and extract structured medicine rows.

    - Max 12 images
    - Returns medicine_name + frequency pairs
    """
    _ = user_id  # auth gate
    prescriptions = await task_service.analyze_medicine_prescription_uploads(files)
    return {"prescriptions": prescriptions}


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


@router.patch("/{task_id}/note", response_model=TaskResponse)
async def update_note(
    task_id: str,
    note: str = Body(..., embed=True, max_length=1000),
    user_id: str = Depends(get_current_user_id),
):
    """Save a user note on a task."""
    result = await task_service.update_note(task_id, user_id, note)
    # Note is the primary signal for the bridge's text→meal LLM call. Re-sync
    # so the meal's food_items reflect the latest note.
    if result.task_type == TaskType.NUTRITION:
        asyncio.create_task(_bridge_nutrition_task_to_meal(task_id))
    return result


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
