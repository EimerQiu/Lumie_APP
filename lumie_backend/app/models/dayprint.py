"""Dayprint — daily action log."""
from typing import Any, Optional
from pydantic import BaseModel


class DayprintEvent(BaseModel):
    type: str           # "task_completed" | "advisor_chat"
    timestamp: str      # ISO datetime (UTC)
    data: dict[str, Any]


class DayprintResponse(BaseModel):
    user_id: str
    date: str           # local date "YYYY-MM-DD"
    events: list[DayprintEvent] = []
