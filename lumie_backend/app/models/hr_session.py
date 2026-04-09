"""Pydantic models for HR measurement sessions and time-series storage."""
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field


# ── Request / inbound ─────────────────────────────────────────────────────────

class HrReadingPoint(BaseModel):
    """A single timestamped BPM reading sent from the app."""
    timestamp: datetime
    bpm: int = Field(..., ge=30, le=220)


class HrSessionCreate(BaseModel):
    """Payload sent by the app when a manual HR measurement finishes."""
    started_at: datetime
    ended_at: datetime
    avg_bpm: int = Field(..., ge=30, le=220)
    min_bpm: int = Field(..., ge=30, le=220)
    max_bpm: int = Field(..., ge=30, le=220)
    readings: List[HrReadingPoint]  # full time-series, bucketed server-side


# ── Response / outbound ───────────────────────────────────────────────────────

class HrSessionSaveResponse(BaseModel):
    """Returned after successfully saving a session."""
    session_id: str
    inserted_buckets: int
    reading_count: int


class HrSessionSummary(BaseModel):
    """One entry in the session list (no time-series payload)."""
    session_id: str
    started_at: datetime
    ended_at: datetime
    duration_seconds: int
    avg_bpm: int
    min_bpm: int
    max_bpm: int
    reading_count: int
    created_at: datetime


# ── Timeseries retrieval ──────────────────────────────────────────────────────

class HrBucketReading(BaseModel):
    """A single reading inside a bucket: offset in seconds + BPM."""
    t: int   # seconds from bucket_start
    bpm: int


class HrBucketResponse(BaseModel):
    """One 5-minute bucket returned by the timeseries endpoint."""
    bucket_start: datetime
    bucket_end: datetime
    count: int
    avg_bpm: Optional[float] = None
    min_bpm: int
    max_bpm: int
    readings: List[HrBucketReading]


class HrSessionTimeseriesResponse(BaseModel):
    session_id: str
    buckets: List[HrBucketResponse]
