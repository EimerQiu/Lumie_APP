"""Advisor check-in preference routes.

Lets users enable/disable proactive advisor check-in push notifications
and configure their preferred time and frequency.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..core.database import get_database
from ..services.auth_service import get_current_user_id

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/advisor/checkin", tags=["advisor"])


# ── Models ────────────────────────────────────────────────────────────────────

class CheckinPrefsResponse(BaseModel):
    enabled: bool = False
    frequency: str = "daily"       # "daily" | "weekdays"
    hour_utc: int = 9
    minute_utc: int = 0


class CheckinPrefsUpdate(BaseModel):
    enabled: Optional[bool] = None
    frequency: Optional[str] = Field(None, pattern=r"^(daily|weekdays)$")
    hour_utc: Optional[int] = Field(None, ge=0, le=23)
    minute_utc: Optional[int] = Field(None, ge=0, le=59)


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/preferences", response_model=CheckinPrefsResponse)
async def get_checkin_preferences(
    user_id: str = Depends(get_current_user_id),
):
    """Get the current user's advisor check-in notification preferences."""
    db = get_database()
    doc = await db.advisor_checkins.find_one(
        {"user_id": user_id},
        {"_id": 0, "user_id": 0, "last_sent_date": 0, "messages": 0},
    )
    if not doc:
        return CheckinPrefsResponse()
    return CheckinPrefsResponse(
        enabled=doc.get("enabled", False),
        frequency=doc.get("frequency", "daily"),
        hour_utc=doc.get("hour_utc", 9),
        minute_utc=doc.get("minute_utc", 0),
    )


@router.patch("/preferences", response_model=CheckinPrefsResponse)
async def update_checkin_preferences(
    body: CheckinPrefsUpdate,
    user_id: str = Depends(get_current_user_id),
):
    """Update the current user's advisor check-in notification preferences.

    Only the provided fields are updated (partial update).
    """
    db = get_database()

    update_fields = {k: v for k, v in body.model_dump().items() if v is not None}
    if not update_fields:
        # Nothing to update — just return current
        return await get_checkin_preferences(user_id)

    await db.advisor_checkins.update_one(
        {"user_id": user_id},
        {"$set": update_fields, "$setOnInsert": {"user_id": user_id, "last_sent_date": None}},
        upsert=True,
    )

    return await get_checkin_preferences(user_id)
