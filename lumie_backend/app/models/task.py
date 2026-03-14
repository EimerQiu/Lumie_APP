"""
Task and Template Models for Med-Reminder Feature
"""

from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field
from enum import Enum


class TaskType(str, Enum):
    """Task type categories"""
    MEDICINE = "Medicine"
    LIFE = "Life"
    STUDY = "Study"
    EXERCISE = "Exercise"
    WORK = "Work"
    MEDITATION = "Meditation"
    LOVE = "Love"


class TaskStatus(str, Enum):
    """Task completion status"""
    PENDING = "pending"
    COMPLETED = "completed"
    OVERDUE = "overdue"  # Legacy alias
    EXPIRED = "expired"


# ============ Task Models ============

class TaskCreate(BaseModel):
    """Request model for creating a single task"""
    task_name: str = Field(..., min_length=1, max_length=200)
    task_type: TaskType = Field(default=TaskType.MEDICINE)
    open_datetime: str = Field(..., description="yyyy-MM-dd HH:mm in user's local timezone")
    close_datetime: str = Field(..., description="yyyy-MM-dd HH:mm in user's local timezone")
    timezone: str = Field(default="UTC", description="User's timezone for time conversion (e.g., America/Los_Angeles)")
    user_id: Optional[str] = Field(None, description="For team tasks: assigned user")
    team_id: Optional[str] = Field(None, description="For team tasks: team ID")
    rpttask_id: Optional[str] = Field(None, description="Template reference")
    task_info: Optional[str] = Field(None, max_length=500)


class TaskResponse(BaseModel):
    """Response model for a single task"""
    task_id: str
    task_name: str
    task_type: TaskType
    open_datetime: str
    close_datetime: str
    user_id: str
    team_id: Optional[str] = None
    created_by: str
    rpttask_id: Optional[str] = None
    status: TaskStatus
    task_info: Optional[str] = None
    completed_at: Optional[str] = None
    created_at: str
    updated_at: str


class TaskListResponse(BaseModel):
    """Response for GET /tasks"""
    tasks: List[TaskResponse]
    total: int


# ============ Template Models ============

class TimeWindow(BaseModel):
    """Single time window within a template"""
    id: int = Field(..., description="Window index (0-based)")
    name: str = Field(..., min_length=1, max_length=100)
    open_time: str = Field(..., description="HH:mm format")
    close_time: str = Field(..., description="HH:mm format")
    is_next_day: bool = Field(default=False, description="Close time is next day")


class TemplateCreate(BaseModel):
    """Request model for creating a template"""
    template_name: str = Field(..., min_length=1, max_length=200)
    template_type: TaskType = Field(default=TaskType.MEDICINE)
    description: Optional[str] = Field(None, max_length=500)
    min_interval: int = Field(default=60, ge=0, description="Min interval in minutes")
    time_window_list: List[TimeWindow] = Field(..., min_length=1)


class TemplateUpdate(BaseModel):
    """Request model for updating a template (all fields optional)"""
    template_name: Optional[str] = Field(None, min_length=1, max_length=200)
    template_type: Optional[TaskType] = None
    description: Optional[str] = Field(None, max_length=500)
    min_interval: Optional[int] = Field(None, ge=0, description="Min interval in minutes")
    time_window_list: Optional[List[TimeWindow]] = Field(None, min_length=1)


class TemplateResponse(BaseModel):
    """Response model for a template"""
    id: str
    template_name: str
    template_type: TaskType
    description: Optional[str] = None
    time_windows: int
    min_interval: int
    time_window_list: List[TimeWindow]
    created_by: str
    created_at: str
    updated_at: str


class TemplateListResponse(BaseModel):
    """Response for GET /tasks/templates"""
    templates: List[TemplateResponse]
    total: int


# ============ Batch Generation Models ============

class BatchGenerateRequest(BaseModel):
    """Request model for generating tasks from a template"""
    template_id: str
    task_name: str = Field(..., min_length=1, max_length=200)
    start_date: str = Field(..., description="yyyy-MM-dd")
    end_date: str = Field(..., description="yyyy-MM-dd")
    team_id: Optional[str] = Field(None)
    user_id: Optional[str] = Field(None, description="For team tasks: assigned user")
    task_info: Optional[str] = Field(None, max_length=500)
    timezone: str = Field(default="UTC", description="User's timezone for time conversion (e.g., America/Los_Angeles)")


class BatchGenerateResponse(BaseModel):
    """Response for batch task generation"""
    created_count: int
    tasks: List[TaskResponse]


# ============ Admin Models ============

class RptTaskItem(BaseModel):
    """Time-window subtask from template"""
    id: int
    name: str
    open_time: int  # Minutes from midnight
    close_time: int  # Minutes from midnight


class AdminTaskData(BaseModel):
    """Admin view task with enriched data"""
    task_id: str
    user_id: str
    username: str
    task_type: str
    open_datetime: str
    close_datetime: str
    status: str
    rpttask_id: Optional[str] = None
    rpttask_name: str
    rpttask_info: Optional[str] = None
    rpttask_type: str
    rpttask_list: List[RptTaskItem] = []
    small_task_id: Optional[str] = None
    min_interval: int = 0
    family_id: Optional[str] = None
    family_name: Optional[str] = None


class AdminTaskListResponse(BaseModel):
    """Response for admin task list"""
    previous_tasks: List[AdminTaskData]
    upcoming_tasks: List[AdminTaskData]


class AdminTaskCompleteRequest(BaseModel):
    """Request to complete a task as admin"""
    task_id: str
    time_zone: str = "UTC"


# ============ AI Tips Models ============

class AiTipsRequest(BaseModel):
    """Request model for AI tips generation"""
    days_back: int = Field(default=30, ge=1, le=90, description="Analysis window in days")
    time_zone: str = Field(default="UTC", description="User's IANA timezone")


class TaskStats(BaseModel):
    total_tasks: int
    completed_tasks: int
    expired_tasks: int
    pending_tasks: int
    completion_rate: float


class AiTipsResponse(BaseModel):
    """Response model for AI tips"""
    tip: str
    task_stats: TaskStats
