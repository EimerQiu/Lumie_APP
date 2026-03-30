"""Heart Rate history API routes."""
from fastapi import APIRouter, Depends

from ..services.auth_service import get_current_user_id
from ..services.hr_service import hr_service
from ..models.hr import HrSyncRequest, HrSyncResponse

router = APIRouter(prefix="/hr", tags=["heart_rate"])


@router.post("/sync", response_model=HrSyncResponse)
async def sync_hr_readings(
    body: HrSyncRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Batch-upload heart rate readings collected from the ring.

    Each reading is identified by its timestamp. Duplicates are silently
    ignored (upsert semantics), so re-sending the same data is safe.
    """
    return await hr_service.sync_readings(user_id, body.readings)
