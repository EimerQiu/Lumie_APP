"""Sleep data API routes — receive ring data and serve sleep history."""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query

from ..services.auth_service import get_current_user_id
from ..services.sleep_service import sleep_service
from ..models.sleep import (
    SleepSyncRequest,
    SleepSessionResponse,
    SleepSummaryResponse,
    SleepTargetResponse,
)

router = APIRouter(prefix="/sleep", tags=["sleep"])


@router.post("/sync", status_code=204)
async def sync_sleep(
    body: SleepSyncRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Upload sleep sessions collected from the ring."""
    await sleep_service.sync_sessions(user_id, body.sessions)


@router.get("/latest", response_model=Optional[SleepSessionResponse])
async def get_latest_sleep(
    user_id: str = Depends(get_current_user_id),
):
    """Return the user's most recent sleep session."""
    return await sleep_service.get_latest(user_id)


@router.get("/history", response_model=list[SleepSessionResponse])
async def get_sleep_history(
    start: datetime = Query(..., description="Range start (ISO 8601)"),
    end: datetime = Query(..., description="Range end (ISO 8601)"),
    user_id: str = Depends(get_current_user_id),
):
    """Return sleep sessions within a date range."""
    return await sleep_service.get_history(user_id, start, end)


@router.get("/summary", response_model=SleepSummaryResponse)
async def get_sleep_summary(
    start: datetime = Query(..., description="Range start (ISO 8601)"),
    end: datetime = Query(..., description="Range end (ISO 8601)"),
    user_id: str = Depends(get_current_user_id),
):
    """Return aggregated sleep stats for a date range."""
    return await sleep_service.get_summary(user_id, start, end)


@router.get("/target", response_model=SleepTargetResponse)
async def get_sleep_target(
    user_id: str = Depends(get_current_user_id),
):
    """Return the age-appropriate sleep target for the user."""
    return await sleep_service.get_target(user_id)
