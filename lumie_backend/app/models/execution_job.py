"""Pydantic models for unified execution jobs."""
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from enum import Enum


class ExecutionJobStatus(str, Enum):
    PENDING = "pending"
    GENERATING = "generating"
    RUNNING = "running"
    RETRYING = "retrying"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"


class ExecutionJobResponse(BaseModel):
    job_id: str
    status: ExecutionJobStatus
    skill_id: Optional[str] = None
    capability_id: Optional[str] = None
    runtime_type: Optional[str] = None
    prompt: str = ""
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    created_at: str
    started_at: Optional[str] = None
    finished_at: Optional[str] = None


class AdvisorChatV2Request(BaseModel):
    message: str = Field(..., min_length=1)
    history: list[dict] = []
    session_id: Optional[str] = None
    target_user_id: Optional[str] = None
    team_id: Optional[str] = None


class AdvisorChatV2Response(BaseModel):
    type: str  # "direct" | "execution" | "guidance"
    reply: str
    reply_class: Optional[str] = None  # clarification_needed | planned | executed | failed
    is_write_operation_task: Optional[bool] = None
    job_id: Optional[str] = None
    skill_id: Optional[str] = None
    status: Optional[str] = None
    nav_hint: Optional[str] = None
