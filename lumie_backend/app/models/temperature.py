"""Pydantic models for temperature sync."""
from datetime import datetime
from typing import List
from pydantic import BaseModel


class TemperatureDataPoint(BaseModel):
    timestamp: datetime
    temp1_c: float   # First sensor reading
    temp2_c: float   # Second sensor reading
    temp3_c: float   # Third sensor reading


class TemperatureSyncRequest(BaseModel):
    readings: List[TemperatureDataPoint]


class TemperatureSyncResponse(BaseModel):
    inserted: int


class TemperatureReadingResponse(BaseModel):
    timestamp: datetime
    temp1_c: float
    temp2_c: float
    temp3_c: float


class TemperatureHistoryResponse(BaseModel):
    readings: List[TemperatureReadingResponse]
