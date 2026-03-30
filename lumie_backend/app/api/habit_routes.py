"""Habit Tracker API routes."""
from typing import Optional

from fastapi import APIRouter, Depends

from ..services.auth_service import get_current_user_id
from ..services.habit_service import habit_service
from ..models.habit import HabitEntryUpsert, HabitEntryResponse

router = APIRouter(prefix="/habit", tags=["habit"])


@router.put("/entry", response_model=HabitEntryResponse)
async def upsert_habit_entry(
    body: HabitEntryUpsert,
    user_id: str = Depends(get_current_user_id),
):
    """Log or update today's habit entry. Only non-null fields are written."""
    return await habit_service.upsert_entry(user_id, body)


@router.get("/entry/{date}", response_model=Optional[HabitEntryResponse])
async def get_habit_entry(
    date: str,
    user_id: str = Depends(get_current_user_id),
):
    """Return the habit entry for a given YYYY-MM-DD date, or null."""
    return await habit_service.get_entry(user_id, date)
