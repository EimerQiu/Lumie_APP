"""Dayprint API routes — daily action + thinking log."""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, Query

from ..services.auth_service import get_current_user_id
from ..services.dayprint_service import get_dayprint
from ..models.dayprint import DayprintResponse, DayprintEvent


logger = logging.getLogger(__name__)

router = APIRouter(prefix="/dayprint", tags=["dayprint"])


@router.get("", response_model=Optional[DayprintResponse])
async def get_today_dayprint(
    date: Optional[str] = Query(None, description="Date YYYY-MM-DD, defaults to today (UTC)"),
    user_id: str = Depends(get_current_user_id),
):
    """Get the user's Dayprint for today (or a specific date).

    Returns null if no events have been logged yet for that date.
    """
    doc = await get_dayprint(user_id, date)
    if not doc:
        return None

    return DayprintResponse(
        user_id=doc["user_id"],
        date=doc["date"],
        events=[DayprintEvent(**e) for e in doc.get("events", [])],
    )
