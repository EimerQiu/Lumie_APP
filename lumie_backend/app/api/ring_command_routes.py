"""Ring live command routes.

GET  /ring/command/pending          — Flutter polls for a pending command
POST /ring/command/{request_id}/result — Flutter posts BLE result
"""

import logging
from fastapi import APIRouter, Depends, HTTPException

from ..services.auth_service import get_current_user_id
from ..models.ring_command import (
    RingCommandPendingResponse,
    RingCommandResultRequest,
    RingCommandResultResponse,
)
from ..services import ring_command_service

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/ring", tags=["ring"])


@router.get("/command/pending", response_model=RingCommandPendingResponse | None)
async def get_pending_command(user_id: str = Depends(get_current_user_id)):
    """Return the oldest pending ring command for the authenticated user, or null."""
    doc = await ring_command_service.get_pending_command(user_id)
    if doc is None:
        return None
    return RingCommandPendingResponse(
        request_id=doc["request_id"],
        command_type=doc["command_type"],
        duration_seconds=doc.get("duration_seconds", 10),
    )


@router.post("/command/{request_id}/result", response_model=RingCommandResultResponse)
async def post_command_result(
    request_id: str,
    body: RingCommandResultRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Store the BLE measurement result for a pending ring command."""
    stored = await ring_command_service.store_result(
        request_id=request_id,
        user_id=user_id,  # noqa: F821 — injected by Depends above
        success=body.success,
        data=body.data,
        error=body.error,
    )
    if not stored:
        raise HTTPException(status_code=404, detail="Command not found or already completed")
    logger.info(f"[RingCommand] Result stored for {request_id}: success={body.success}")
    return RingCommandResultResponse(request_id=request_id, stored=True)
