"""Step count data models for the Lumie Ring daily step sync."""
from typing import Optional
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
    goal_steps: int
    goal_reason: str
    goal_is_reduced: bool
    goal_type: str = "minutes"   # "steps" or "minutes"


class StepGoalResponse(BaseModel):
    """Adaptive activity goal for a single day."""
    goal_minutes: int
    goal_steps: int
    reason: str
    is_reduced: bool
    goal_type: str = "minutes"       # "steps" or "minutes" — user preference
    condition_adjusted: bool = False  # True when baseline was reduced for ICD-10


class GoalSettingsResponse(BaseModel):
    """User's persisted goal-type preference and optional manual override."""
    goal_type: str = "minutes"       # "steps" or "minutes"
    custom_goal: Optional[int] = None  # user override; None = use condition default
    default_steps: int               # condition-adjusted step baseline
    default_minutes: int             # condition-adjusted minute baseline
    condition_adjusted: bool         # True when an ICD-10 code reduced the baseline


class GoalSettingsUpdate(BaseModel):
    goal_type: str = Field(..., pattern="^(steps|minutes)$")
    custom_goal: Optional[int] = Field(default=None, ge=1)
