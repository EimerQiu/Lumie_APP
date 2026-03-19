"""Pydantic models for the AI data analysis system."""
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from enum import Enum


class AnalysisJobStatus(str, Enum):
    PENDING = "pending"
    GENERATING = "generating"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"


class AnalysisJobCreate(BaseModel):
    prompt: str = Field(..., min_length=2, max_length=500)
    target_user_id: Optional[str] = None
    team_id: Optional[str] = None
    timeout: int = Field(default=30, ge=10, le=60)


class AnalysisResult(BaseModel):
    summary: str
    data: Optional[Dict[str, Any]] = None
    chart_base64: Optional[str] = None
    nav_hint: Optional[str] = None  # "task_list" | "task_dashboard" | None


class AnalysisJobResponse(BaseModel):
    job_id: str
    status: AnalysisJobStatus
    prompt: str
    result: Optional[AnalysisResult] = None
    error: Optional[str] = None
    created_at: str
    started_at: Optional[str] = None
    finished_at: Optional[str] = None


class AnalysisJobListResponse(BaseModel):
    jobs: list[AnalysisJobResponse]
    has_more: bool
