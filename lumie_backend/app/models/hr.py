"""Pydantic models for Heart Rate history sync."""
from datetime import datetime
from typing import List
from pydantic import BaseModel


class HrDataPoint(BaseModel):
    timestamp: datetime
    bpm: int


class HrSyncRequest(BaseModel):
    readings: List[HrDataPoint]


class HrSyncResponse(BaseModel):
    inserted: int
