"""Step count API routes — receive ring data and serve daily step history."""
from datetime import datetime

from fastapi import APIRouter, Depends, Query

from ..services.auth_service import get_current_user_id
from ..services.steps_service import steps_service
from ..models.steps import StepSyncRequest, DailyStepResponse, StepGoalResponse

router = APIRouter(prefix="/steps", tags=["steps"])


@router.post("/sync", status_code=204)
async def sync_steps(
    body: StepSyncRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Upload daily step records collected from the ring (command 0x51)."""
    await steps_service.sync_records(user_id, body.records)


@router.get("/history", response_model=list[DailyStepResponse])
async def get_step_history(
    start: datetime = Query(..., description="Range start (ISO 8601)"),
    end: datetime = Query(..., description="Range end (ISO 8601)"),
    user_id: str = Depends(get_current_user_id),
):
    """Return daily step records within a date range, newest first."""
    return await steps_service.get_history(user_id, start, end)


@router.get("/goal", response_model=StepGoalResponse)
async def get_step_goal(
    date: datetime = Query(default=None, description="Date to compute goal for (defaults to today)"),
    user_id: str = Depends(get_current_user_id),
):
    """Return the adaptive activity goal for a given day.

    Goal is based on last night's sleep quality (if available) and day of week.
    Falls back to the baseline (60 min weekday / 45 min weekend) when no sleep
    data is found.
    """
    return await steps_service.get_goal(user_id, date or datetime.utcnow())
