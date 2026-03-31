"""SpO2 (blood oxygen) API routes."""
from fastapi import APIRouter, Depends, Query

from ..services.auth_service import get_current_user_id
from ..services.spo2_service import spo2_service
from ..models.spo2 import (
    Spo2SyncRequest,
    Spo2SyncResponse,
    Spo2HistoryResponse,
)

router = APIRouter(prefix="/spo2", tags=["spo2"])


@router.post("/sync", response_model=Spo2SyncResponse)
async def sync_spo2_readings(
    body: Spo2SyncRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Batch-upload SpO2 (blood oxygen) readings from the ring (command 0x66).

    Duplicates are silently ignored (upsert by timestamp).
    """
    return await spo2_service.sync_readings(user_id, body.readings)


@router.get("", response_model=Spo2HistoryResponse)
async def get_spo2_history(
    days: int = Query(default=7, ge=1, le=90),
    user_id: str = Depends(get_current_user_id),
):
    """Return SpO2 readings for the past N days (default 7)."""
    readings = await spo2_service.get_history(user_id, days=days)
    return Spo2HistoryResponse(readings=readings)
