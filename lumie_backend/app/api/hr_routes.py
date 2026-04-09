"""Heart Rate API routes — ring sync and manual measurement sessions."""
from typing import List
from fastapi import APIRouter, Depends, HTTPException, Query

from ..services.auth_service import get_current_user_id
from ..services.hr_service import hr_service
from ..models.hr import HrSyncRequest, HrSyncResponse
from ..models.hr_session import (
    HrSessionCreate,
    HrSessionSaveResponse,
    HrSessionSummary,
    HrSessionTimeseriesResponse,
)

router = APIRouter(prefix="/hr", tags=["heart_rate"])


# ── Ring background sync ──────────────────────────────────────────────────────

@router.post("/sync", response_model=HrSyncResponse)
async def sync_hr_readings(
    body: HrSyncRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Batch-upload periodic HR readings collected from the ring.

    Each reading is identified by its timestamp. Duplicates are silently
    ignored (upsert semantics), so re-sending the same data is safe.
    """
    return await hr_service.sync_readings(user_id, body.readings)


# ── Manual measurement sessions ───────────────────────────────────────────────

@router.post("/sessions", response_model=HrSessionSaveResponse, status_code=201)
async def save_hr_session(
    body: HrSessionCreate,
    user_id: str = Depends(get_current_user_id),
):
    """Save a completed manual HR measurement session.

    Creates two records:
    - A session summary in `hr_sessions` (avg/min/max, duration).
    - N bucket documents in `hr_timeseries`, each covering 5 minutes of the
      session, storing readings as compact {t, bpm} pairs.
    """
    if body.ended_at <= body.started_at:
        raise HTTPException(status_code=422, detail="ended_at must be after started_at")
    return await hr_service.save_session(user_id, body)


@router.get("/sessions", response_model=List[HrSessionSummary])
async def list_hr_sessions(
    limit: int = Query(default=20, ge=1, le=100),
    user_id: str = Depends(get_current_user_id),
):
    """List the user's most recent HR sessions, newest first."""
    return await hr_service.list_sessions(user_id, limit=limit)


@router.get("/sessions/{session_id}/timeseries", response_model=HrSessionTimeseriesResponse)
async def get_session_timeseries(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Return the full bucketed time-series for a session.

    Each bucket covers 5 minutes and includes pre-computed stats plus the
    individual {t, bpm} readings (t = seconds from bucket_start).
    Reconstruct a timestamp: bucket_start + timedelta(seconds=t).
    """
    return await hr_service.get_session_timeseries(user_id, session_id)
