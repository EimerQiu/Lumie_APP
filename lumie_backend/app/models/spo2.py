"""Pydantic models for SpO2 (blood oxygen) sync."""
from datetime import datetime
from typing import List
from pydantic import BaseModel


class Spo2DataPoint(BaseModel):
    timestamp: datetime
    spo2_percent: int   # Oxygen saturation 0–100


class Spo2SyncRequest(BaseModel):
    readings: List[Spo2DataPoint]


class Spo2SyncResponse(BaseModel):
    inserted: int


class Spo2ReadingResponse(BaseModel):
    timestamp: datetime
    spo2_percent: int


class Spo2HistoryResponse(BaseModel):
    readings: List[Spo2ReadingResponse]
