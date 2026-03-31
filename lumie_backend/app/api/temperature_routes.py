"""Temperature API routes."""
from fastapi import APIRouter, Depends, Query

from ..services.auth_service import get_current_user_id
from ..services.temperature_service import temperature_service
from ..models.temperature import (
    TemperatureSyncRequest,
    TemperatureSyncResponse,
    TemperatureHistoryResponse,
)

router = APIRouter(prefix="/temperature", tags=["temperature"])


@router.post("/sync", response_model=TemperatureSyncResponse)
async def sync_temperature_readings(
    body: TemperatureSyncRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Batch-upload temperature readings from the ring (command 0x62).

    Duplicates are silently ignored (upsert by timestamp).
    """
    return await temperature_service.sync_readings(user_id, body.readings)


@router.get("", response_model=TemperatureHistoryResponse)
async def get_temperature_history(
    days: int = Query(default=7, ge=1, le=90),
    user_id: str = Depends(get_current_user_id),
):
    """Return temperature readings for the past N days (default 7)."""
    readings = await temperature_service.get_history(user_id, days=days)
    return TemperatureHistoryResponse(readings=readings)
