"""
Task and Template Models for Med-Reminder Feature
"""

from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field, model_validator
from enum import Enum


class TaskType(str, Enum):
    """Task type categories"""
    MEDICINE = "Medicine"
    STUDY = "Study"
    EXERCISE = "Exercise"
    NUTRITION = "Nutrition"
    WORK = "Work"
    HOBBIES = "Hobbies"
    SOCIAL = "Social"
    LIFE = "Life"


class TaskStatus(str, Enum):
    """Task completion status"""
    PENDING = "pending"
    COMPLETED = "completed"
    EXPIRED = "expired"


class TaskAssociationTarget(str, Enum):
    """Generic link target for task-related behavior records."""
    MEAL = "meal"
    ACTIVE = "active"
    OTHER = "other"


class TaskAssociation(BaseModel):
    """A behavior record associated with this task completion."""
    target_type: TaskAssociationTarget
    target_id: str = Field(..., min_length=1, max_length=200)
    relation: Optional[str] = Field(
        None,
        max_length=100,
        description="Optional semantic relation label (e.g. completed_via).",
    )


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


class TaskUpdate(BaseModel):
    """Request model for editing an existing task (all fields optional).

    Fields present in the request body (including explicit null) are updated;
    fields absent from the body are left unchanged. Use model_fields_set to
    distinguish 'not sent' from 'sent as null'.
    """
    task_name: Optional[str] = Field(None, min_length=1, max_length=200)
    task_type: Optional[TaskType] = None
    open_datetime: Optional[str] = Field(None, description="yyyy-MM-dd HH:mm in user's local timezone")
    close_datetime: Optional[str] = Field(None, description="yyyy-MM-dd HH:mm in user's local timezone")
    timezone: str = Field(default="UTC", description="User's timezone for time conversion")
    task_info: Optional[str] = Field(None, max_length=500)
    # null = make personal; a team_id = assign to that team
    team_id: Optional[str] = Field(None, description="null to make private, team_id to move to a team")
    # null = assign to self; a user_id = assign to that member (admin only)
    user_id: Optional[str] = Field(None, description="Assigned user; null = self")


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
    task_info: Optional[str] = None
    note: Optional[str] = None
    attachments: List[dict] = Field(default_factory=list)
    associations: List[TaskAssociation] = Field(default_factory=list)
    completed_at: Optional[str] = None
    extension_count: int = 0
    created_at: str
    updated_at: str


class TaskListResponse(BaseModel):
    """Response for GET /tasks"""
    tasks: List[TaskResponse]
    total: int


class TaskCompleteRequest(BaseModel):
    """Optional payload for completion-time associations."""
    associations: List[TaskAssociation] = Field(default_factory=list)
    suppress_dayprint: bool = Field(
        default=False,
        description="When true, completion will not emit dayprint events.",
    )


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
    min_interval: int = Field(
        default=60,
        ge=0,
        description=(
            "Minimum allowed gap (minutes) between a completed task and the next "
            "task opening in the same template series. Used by postpone logic; "
            "NOT the template generation cadence."
        ),
    )
    time_window_list: List[TimeWindow] = Field(..., min_length=1)


class TemplateUpdate(BaseModel):
    """Request model for updating a template (all fields optional)"""
    template_name: Optional[str] = Field(None, min_length=1, max_length=200)
    template_type: Optional[TaskType] = None
    description: Optional[str] = Field(None, max_length=500)
    min_interval: Optional[int] = Field(
        None,
        ge=0,
        description=(
            "Minimum allowed gap (minutes) between completion and next open in the "
            "same series (postpone safety rule). NOT generation cadence."
        ),
    )
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
    frequency_minutes: int = Field(
        default=1440,
        ge=1,
        description=(
            "Template generation cadence in minutes (anchor interval). Must be "
            "greater than the template's time span. This is separate from "
            "template.min_interval."
        ),
    )

    @model_validator(mode="before")
    @classmethod
    def normalize_frequency_aliases(cls, data):
        """Accept legacy/alternate key names from older clients."""
        if not isinstance(data, dict):
            return data
        if "frequency_minutes" in data:
            return data

        for key in ("frequencyMinutes", "repeat_frequency_minutes", "repeatFrequencyMinutes", "frequency"):
            if key in data:
                normalized = dict(data)
                normalized["frequency_minutes"] = data[key]
                return normalized
        return data


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
    rpttask_id: Optional[str] = None
    rpttask_name: str
    rpttask_info: Optional[str] = None
    note: Optional[str] = None
    attachments: List[dict] = Field(default_factory=list)
    associations: List[TaskAssociation] = Field(default_factory=list)
    completed_at: Optional[str] = None
    rpttask_type: str
    rpttask_list: List[RptTaskItem] = []
    small_task_id: Optional[str] = None
    min_interval: int = 0
    family_id: Optional[str] = None
    family_name: Optional[str] = None
    template_name: Optional[str] = None


class AdminTaskListResponse(BaseModel):
    """Response for admin task list"""
    previous_tasks: List[AdminTaskData]
    upcoming_tasks: List[AdminTaskData]


class AdminTaskCompleteRequest(BaseModel):
    """Request to complete a task as admin"""
    task_id: str
    time_zone: str = "UTC"
    completed_at: Optional[datetime] = None


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
