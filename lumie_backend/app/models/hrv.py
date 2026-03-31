"""Pydantic models for HRV / stress / blood pressure sync."""
from datetime import datetime
from typing import List
from pydantic import BaseModel


class HrvDataPoint(BaseModel):
    timestamp: datetime
    hrv_ms: int
    heart_rate_bpm: int
    fatigue: int          # 0–100 stress/fatigue level from ring
    systolic_mmhg: int
    diastolic_mmhg: int


class HrvSyncRequest(BaseModel):
    readings: List[HrvDataPoint]


class HrvSyncResponse(BaseModel):
    inserted: int


class HrvReadingResponse(BaseModel):
    timestamp: datetime
    hrv_ms: int
    heart_rate_bpm: int
    fatigue: int
    systolic_mmhg: int
    diastolic_mmhg: int
    source: str


class HrvHistoryResponse(BaseModel):
    readings: List[HrvReadingResponse]
