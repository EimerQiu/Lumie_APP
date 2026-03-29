"""Internal proactive advisor endpoint.

Called by the notification daemon — NOT accessible to regular users.
Protected by the X-Internal-Secret header (must match the INTERNAL_SECRET
env var, which defaults to SECRET_KEY if not set).
"""

import logging
import os

from fastapi import APIRouter, Header, HTTPException, Path

from ..services.proactive_advisor_service import run_proactive_check

logger = logging.getLogger(__name__)

# Resolved once at import time; both API server and daemon read the same env var.
_INTERNAL_SECRET = os.getenv("INTERNAL_SECRET") or os.getenv("SECRET_KEY", "")

router = APIRouter(prefix="/internal/advisor", tags=["internal"])


@router.post("/proactive/run/{user_id}")
async def run_proactive(
    user_id: str = Path(...),
    x_internal_secret: str = Header(...),
):
    """Trigger a proactive advisor check for one user.

    The daemon calls this once per eligible user on each poll cycle.
    Returns the nudge decision (nudged, message, reason).
    """
    if not _INTERNAL_SECRET or x_internal_secret != _INTERNAL_SECRET:
        raise HTTPException(status_code=403, detail="Forbidden")

    result = await run_proactive_check(user_id)
    return result
