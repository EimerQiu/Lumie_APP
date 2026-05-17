"""Workout API routes — exercises, templates, sessions, PRs, overload advice."""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from ..services.auth_service import get_current_user_id
from ..services.workout_service import workout_service
from ..models.workout import (
    ExerciseCreate,
    ExerciseUpdate,
    TemplateCreate,
    TemplateUpdate,
    SessionCreate,
    AdvisorSessionCreate,
    SessionUpdate,
)
from ..core.database import get_database
from ..models.user import SubscriptionTier

logger = logging.getLogger(__name__)

router = APIRouter(tags=["workout"])


# ── Helpers ────────────────────────────────────────────────────────────────────

async def _require_pro(user_id: str) -> None:
    """Raise 403 if user is on the free tier."""
    db = get_database()
    user = await db.users.find_one({"user_id": user_id})
    tier = (user or {}).get("subscription", {}).get("tier", "free")
    if tier == SubscriptionTier.FREE:
        raise HTTPException(
            status_code=403,
            detail={
                "error": {
                    "code": "SUBSCRIPTION_LIMIT_REACHED",
                    "message": "This feature requires a Pro subscription",
                    "subscription": {
                        "current_tier": "free",
                        "required_tier": "pro",
                        "upgrade_required": True,
                    },
                    "action": {
                        "type": "upgrade",
                        "label": "Upgrade to Pro",
                        "destination": "/subscription/upgrade",
                    },
                }
            },
        )


# ── Exercise Library ───────────────────────────────────────────────────────────

@router.get("/exercises")
async def list_exercises(
    muscle_group: Optional[str] = Query(None),
    equipment_type: Optional[str] = Query(None),
    movement_type: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    user_id: str = Depends(get_current_user_id),
):
    """List exercises from the library, including user's custom exercises."""
    # Get user's ICD-10 code for caution flagging
    db = get_database()
    profile = await db.profiles.find_one({"user_id": user_id})
    icd10_code = (profile or {}).get("icd10_code")

    exercises = await workout_service.list_exercises(
        user_id=user_id,
        muscle_group=muscle_group,
        equipment_type=equipment_type,
        movement_type=movement_type,
        search=search,
        icd10_code=icd10_code,
    )
    return {"exercises": exercises}


@router.get("/exercises/{exercise_id}")
async def get_exercise(
    exercise_id: str,
    user_id: str = Depends(get_current_user_id),
):
    exercise = await workout_service.get_exercise(exercise_id)
    if not exercise:
        raise HTTPException(status_code=404, detail="Exercise not found")
    return exercise


@router.post("/exercises", status_code=201)
async def create_exercise(
    data: ExerciseCreate,
    user_id: str = Depends(get_current_user_id),
):
    """Create a custom exercise (Pro only)."""
    await _require_pro(user_id)
    return await workout_service.create_exercise(user_id, data)


@router.put("/exercises/{exercise_id}")
async def update_exercise(
    exercise_id: str,
    data: ExerciseUpdate,
    user_id: str = Depends(get_current_user_id),
):
    """Update a custom exercise owned by the user."""
    result = await workout_service.update_exercise(user_id, exercise_id, data)
    if not result:
        raise HTTPException(status_code=404, detail="Exercise not found or not owned by you")
    return result


@router.delete("/exercises/{exercise_id}")
async def delete_exercise(
    exercise_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Soft-delete a custom exercise."""
    deleted = await workout_service.delete_exercise(user_id, exercise_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Exercise not found or not owned by you")
    return {"deleted": True}


# ── Workout Templates ──────────────────────────────────────────────────────────

@router.get("/workout-templates")
async def list_templates(
    user_id: str = Depends(get_current_user_id),
):
    templates = await workout_service.list_templates(user_id)
    return {"templates": templates}


@router.get("/workout-templates/{template_id}")
async def get_template(
    template_id: str,
    user_id: str = Depends(get_current_user_id),
):
    template = await workout_service.get_template(template_id)
    if not template:
        raise HTTPException(status_code=404, detail="Template not found")
    return template


@router.post("/workout-templates", status_code=201)
async def create_template(
    data: TemplateCreate,
    user_id: str = Depends(get_current_user_id),
):
    """Create a new workout template (Pro only)."""
    await _require_pro(user_id)
    return await workout_service.create_template(user_id, data)


@router.put("/workout-templates/{template_id}")
async def update_template(
    template_id: str,
    data: TemplateUpdate,
    user_id: str = Depends(get_current_user_id),
):
    result = await workout_service.update_template(user_id, template_id, data)
    if not result:
        raise HTTPException(status_code=404, detail="Template not found or not owned by you")
    return result


@router.delete("/workout-templates/{template_id}")
async def delete_template(
    template_id: str,
    user_id: str = Depends(get_current_user_id),
):
    deleted = await workout_service.delete_template(user_id, template_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Template not found or not owned by you")
    return {"deleted": True}


@router.post("/workout-templates/{template_id}/duplicate", status_code=201)
async def duplicate_template(
    template_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Duplicate a template (Pro only)."""
    await _require_pro(user_id)
    result = await workout_service.duplicate_template(user_id, template_id)
    if not result:
        raise HTTPException(status_code=404, detail="Template not found")
    return result


# ── Workout Sessions ───────────────────────────────────────────────────────────

@router.post("/workout-sessions", status_code=201)
async def create_session(
    data: SessionCreate,
    user_id: str = Depends(get_current_user_id),
):
    """Save a completed workout session."""
    return await workout_service.create_session(user_id, data)


@router.get("/workout-sessions")
async def list_sessions(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user_id: str = Depends(get_current_user_id),
):
    sessions = await workout_service.list_sessions(user_id, limit=limit, offset=offset)
    return {"sessions": sessions}


@router.get("/workout-sessions/{session_id}")
async def get_session(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
):
    session = await workout_service.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


@router.post("/workout-sessions/for-user/{target_user_id}", status_code=201)
async def create_session_for_user(
    target_user_id: str,
    data: AdvisorSessionCreate,
    advisor_id: str = Depends(get_current_user_id),
):
    """Advisor logs a workout session on behalf of a user they work with."""
    try:
        return await workout_service.create_session_for_user(
            advisor_id=advisor_id,
            target_user_id=target_user_id,
            data=data,
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc))


@router.put("/workout-sessions/{session_id}")
async def update_session(
    session_id: str,
    data: SessionUpdate,
    user_id: str = Depends(get_current_user_id),
):
    """Edit a session (post-workout corrections)."""
    result = await workout_service.update_session(user_id, session_id, data)
    if not result:
        raise HTTPException(status_code=404, detail="Session not found")
    return result


# ── Personal Records ───────────────────────────────────────────────────────────

@router.get("/personal-records")
async def list_personal_records(
    user_id: str = Depends(get_current_user_id),
):
    records = await workout_service.list_personal_records(user_id)
    return {"records": records}


@router.get("/personal-records/{exercise_id}")
async def get_exercise_prs(
    exercise_id: str,
    user_id: str = Depends(get_current_user_id),
):
    records = await workout_service.get_exercise_prs(user_id, exercise_id)
    return {"records": records}


# ── Exercise History ───────────────────────────────────────────────────────────

@router.get("/exercises/{exercise_id}/history")
async def get_exercise_history(
    exercise_id: str,
    limit: int = Query(20, ge=1, le=100),
    user_id: str = Depends(get_current_user_id),
):
    history = await workout_service.get_exercise_history(user_id, exercise_id, limit=limit)
    return {"history": history}


# ── Progressive Overload Advice ────────────────────────────────────────────────

@router.get("/workout-templates/{template_id}/overload-advice")
async def get_overload_advice(
    template_id: str,
    user_id: str = Depends(get_current_user_id),
):
    advice = await workout_service.get_overload_advice(user_id, template_id)
    return {"suggestions": advice}
