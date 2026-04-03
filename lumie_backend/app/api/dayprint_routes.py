"""Dayprint API routes — daily action + thinking log."""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, Query

from ..services.auth_service import get_current_user_id
from ..services.dayprint_service import get_dayprint, get_dayprint_history
from ..models.dayprint import DayprintResponse, DayprintEvent, DayprintHistoryResponse


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


@router.get("/history", response_model=DayprintHistoryResponse)
async def get_dayprint_history_route(
    limit: int = Query(default=14, ge=1, le=60, description="Number of dayprint days to fetch"),
    before_date: Optional[str] = Query(
        default=None,
        description="Cursor date YYYY-MM-DD (returns records older than this date)",
    ),
    user_id: str = Depends(get_current_user_id),
):
    """Get paginated dayprint history (newest date first)."""
    docs, has_more, next_before_date = await get_dayprint_history(
        user_id=user_id,
        limit=limit,
        before_date=before_date,
    )
    return DayprintHistoryResponse(
        dayprints=[
            DayprintResponse(
                user_id=doc["user_id"],
                date=doc["date"],
                events=[DayprintEvent(**e) for e in doc.get("events", [])],
            )
            for doc in docs
        ],
        has_more=has_more,
        next_before_date=next_before_date,
    )
