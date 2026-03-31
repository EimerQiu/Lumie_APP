"""HRV / stress / blood pressure API routes."""
from fastapi import APIRouter, Depends, Query

from ..services.auth_service import get_current_user_id
from ..services.hrv_service import hrv_service
from ..models.hrv import HrvSyncRequest, HrvSyncResponse, HrvHistoryResponse

router = APIRouter(prefix="/hrv", tags=["hrv"])


@router.post("/sync", response_model=HrvSyncResponse)
async def sync_hrv_readings(
    body: HrvSyncRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Batch-upload HRV / stress / blood pressure readings from the ring.

    Duplicates are silently ignored (upsert by timestamp), so re-sending
    the same data is safe.
    """
    return await hrv_service.sync_readings(user_id, body.readings)


@router.get("", response_model=HrvHistoryResponse)
async def get_hrv_history(
    days: int = Query(default=7, ge=1, le=90),
    user_id: str = Depends(get_current_user_id),
):
    """Return HRV readings for the past N days (default 7)."""
    readings = await hrv_service.get_history(user_id, days=days)
    return HrvHistoryResponse(readings=readings)
