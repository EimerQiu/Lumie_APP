"""Step count data models for the Lumie Ring daily step sync."""
from pydantic import BaseModel, Field


class DailyStepRecord(BaseModel):
    """One day of ring step data (from command 0x51)."""
    date_str: str                          # YYYY-MM-DD (local date from ring BCD)
    steps: int = Field(..., ge=0)
    exercise_time_seconds: int = Field(..., ge=0)
    distance_km: float = Field(..., ge=0)


class StepSyncRequest(BaseModel):
    records: list[DailyStepRecord]


class DailyStepResponse(BaseModel):
    """Per-day step summary returned by GET /steps/history."""
    date_str: str
    steps: int
    active_minutes: int       # exercise_time_seconds // 60
    distance_km: float
    goal_minutes: int
    goal_reason: str
    goal_is_reduced: bool


class StepGoalResponse(BaseModel):
    """Adaptive activity goal for a single day."""
    goal_minutes: int
    reason: str
    is_reduced: bool
