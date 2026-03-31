"""Pydantic models for ring live command round-trip."""
from datetime import datetime
from typing import Any, Dict, List, Optional
from pydantic import BaseModel


class RingCommandRequest(BaseModel):
    """Stored in ring_command_requests when the advisor wants a live reading."""
    command_type: str          # "hr_measure" | "temperature"
    duration_seconds: int = 10 # for hr_measure
    user_id: str


class RingCommandPendingResponse(BaseModel):
    """Returned to the Flutter app when there is a pending command."""
    request_id: str
    command_type: str
    duration_seconds: int


class RingCommandResultRequest(BaseModel):
    """Posted by Flutter after executing the BLE command."""
    success: bool
    data: Dict[str, Any]   # command-type-specific result fields
    error: Optional[str] = None


class RingCommandResultResponse(BaseModel):
    """Confirmation from backend after result is stored."""
    request_id: str
    stored: bool
