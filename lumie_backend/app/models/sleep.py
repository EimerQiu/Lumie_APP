"""Pydantic models for sleep data."""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class SleepStageData(BaseModel):
    stage: str  # "light", "deep", "rem", "awake"
    duration_minutes: int
    percentage: float


class SleepTimelineSegment(BaseModel):
    """One ordered block in the sleep timeline (stage + time window)."""
    stage: str  # "awake", "light", "deep", "rem"
    start_offset_minutes: int  # minutes from session bedtime
    duration_minutes: int


class SleepSessionSync(BaseModel):
    """A single sleep session uploaded from the ring."""
    session_id: str
    bedtime: datetime
    wake_time: datetime
    total_sleep_minutes: int
    time_awake_minutes: int
    stages: list[SleepStageData]
    resting_heart_rate: int = 0
    sleep_quality_score: float
    source: str = "ring"  # always "ring" for BLE-synced data


class SleepSyncRequest(BaseModel):
    sessions: list[SleepSessionSync]


class SleepSessionResponse(BaseModel):
    session_id: str
    user_id: str
    bedtime: datetime
    wake_time: datetime
    total_sleep_minutes: int
    time_awake_minutes: int
    stages: list[SleepStageData]
    resting_heart_rate: int
    sleep_quality_score: float
    created_at: datetime
    source: str = "ring"  # defaults to "ring" for records predating this field
    timeline_segments: list[SleepTimelineSegment] = []
    wake_count: int = 0


class SleepSummaryResponse(BaseModel):
    start_date: datetime
    end_date: datetime
    average_sleep_hours: float
    average_resting_hr: float
    average_sleep_quality: float
    sleep_consistency: float
    average_stage_percentages: dict[str, float]


class SleepTargetResponse(BaseModel):
    min_duration_minutes: int
    max_duration_minutes: int
    target_duration_minutes: int
    target_stage_percentages: dict[str, float]
