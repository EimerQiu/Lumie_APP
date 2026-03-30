"""Pydantic models for Habit Tracker daily entries."""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class HabitEntryUpsert(BaseModel):
    """Payload sent by the client to log or update today's habits."""
    date: str  # YYYY-MM-DD in the user's local date
    mood: Optional[int] = None          # 1–5 (1=very bad, 5=great)
    energy: Optional[str] = None        # "low" | "moderate" | "high"
    hunger: Optional[str] = None        # "low" | "normal" | "high"
    workload: Optional[str] = None      # "light" | "moderate" | "heavy"
    fatigue: Optional[str] = None       # "low" | "moderate" | "high"
    condition_metric: Optional[float] = None  # optional numeric (e.g. blood pressure)


class HabitEntryResponse(BaseModel):
    """Full habit entry returned to the client."""
    user_id: str
    date: str
    mood: Optional[int] = None
    energy: Optional[str] = None
    hunger: Optional[str] = None
    workload: Optional[str] = None
    fatigue: Optional[str] = None
    condition_metric: Optional[float] = None
    updated_at: datetime
