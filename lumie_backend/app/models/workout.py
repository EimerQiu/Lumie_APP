"""Workout models — exercise library, templates, sessions, and personal records."""
from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


# ── Enums ──────────────────────────────────────────────────────────────────────

class MuscleGroup(str, Enum):
    CHEST = "chest"
    BACK = "back"
    SHOULDERS = "shoulders"
    BICEPS = "biceps"
    TRICEPS = "triceps"
    LEGS = "legs"
    GLUTES = "glutes"
    CORE = "core"
    FULL_BODY = "full_body"
    FOREARMS = "forearms"
    HAMSTRINGS = "hamstrings"
    QUADRICEPS = "quadriceps"
    CALVES = "calves"
    TRAPS = "traps"
    LOWER_BACK = "lower_back"
    LATS = "lats"
    RHOMBOIDS = "rhomboids"


class EquipmentType(str, Enum):
    BODYWEIGHT = "bodyweight"
    DUMBBELL = "dumbbell"
    BARBELL = "barbell"
    MACHINE = "machine"
    CABLE = "cable"
    BAND = "band"


class MovementType(str, Enum):
    PUSH = "push"
    PULL = "pull"
    HINGE = "hinge"
    SQUAT = "squat"
    CARRY = "carry"
    ISOLATION = "isolation"
    COMPOUND = "compound"


class SetType(str, Enum):
    STRAIGHT = "straight"
    SUPERSET = "superset"
    CIRCUIT = "circuit"
    DROP_SET = "drop_set"
    FAILURE = "failure"


class SplitType(str, Enum):
    FULL_BODY = "full_body"
    UPPER_LOWER = "upper_lower"
    PUSH_PULL_LEGS = "push_pull_legs"
    BODY_PART = "body_part"
    AB_BLOCK = "ab_block"
    CUSTOM = "custom"


class SetCompletionStatus(str, Enum):
    COMPLETED = "completed"
    FAILED = "failed"
    PR = "pr"
    SKIPPED = "skipped"


class PrType(str, Enum):
    MAX_WEIGHT = "max_weight"
    MAX_REPS = "max_reps"
    MAX_VOLUME = "max_volume"


class WorkoutSource(str, Enum):
    USER_MANUAL = "user_manual"
    ADVISOR_ADDED = "advisor_added"
    AUTO_DETECTED = "auto_detected"
    MERGED = "merged"


class SessionCreatedBy(str, Enum):
    USER = "user"
    ADVISOR = "advisor"


# ── Exercise Library ───────────────────────────────────────────────────────────

class ExerciseDefinition(BaseModel):
    """An exercise in the library (system-provided or user-created)."""
    exercise_id: str
    name: str
    description: str = ""
    primary_muscles: list[str] = Field(default_factory=list)
    secondary_muscles: list[str] = Field(default_factory=list)
    equipment_type: str  # EquipmentType value
    movement_type: str  # MovementType value
    pose_type: Optional[str] = None  # Maps to PoseType for camera exercises
    recommended_orientation: Optional[str] = None  # "front" or "side"
    form_description: str = ""
    is_system: bool = True
    created_by: Optional[str] = None  # user_id if custom
    icd10_caution_codes: list[str] = Field(default_factory=list)
    is_active: bool = True
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class ExerciseCreate(BaseModel):
    """Request model for creating a custom exercise."""
    name: str = Field(..., min_length=1, max_length=100)
    description: str = ""
    primary_muscles: list[str] = Field(default_factory=list)
    secondary_muscles: list[str] = Field(default_factory=list)
    equipment_type: str
    movement_type: str = "isolation"
    form_description: str = ""


class ExerciseUpdate(BaseModel):
    """Request model for updating a custom exercise."""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None
    primary_muscles: Optional[list[str]] = None
    secondary_muscles: Optional[list[str]] = None
    equipment_type: Optional[str] = None
    movement_type: Optional[str] = None
    form_description: Optional[str] = None


# ── Workout Templates ──────────────────────────────────────────────────────────

class TemplateExercise(BaseModel):
    """An exercise entry within a workout template block."""
    exercise_id: str
    exercise_name: str = ""  # Denormalized for display
    equipment_type: str = ""  # Denormalized for camera routing
    pose_type: Optional[str] = None  # Denormalized
    order: int = 0
    default_sets: int = 3
    default_reps: int = 10
    default_weight: Optional[float] = None
    default_rest_seconds: int = 60
    set_type: str = "straight"  # SetType value
    group_id: Optional[str] = None  # Links exercises in superset/circuit
    notes: Optional[str] = None


class WorkoutBlock(BaseModel):
    """A named block/section within a workout template."""
    block_id: str
    name: str  # e.g. "Block A — Main Lift"
    order: int = 0
    exercises: list[TemplateExercise] = Field(default_factory=list)


class WorkoutTemplate(BaseModel):
    """A saved workout template (one day in a split)."""
    template_id: str
    user_id: str
    name: str
    emoji: str = "💪"
    split_type: str = "full_body"  # SplitType value
    split_day_label: Optional[str] = None  # e.g. "Push Day"
    split_group_id: Optional[str] = None  # Groups templates in the same split
    blocks: list[WorkoutBlock] = Field(default_factory=list)
    rest_duration_seconds: int = 60
    is_system_default: bool = False
    is_active: bool = True
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class TemplateCreate(BaseModel):
    """Request model for creating a workout template."""
    name: str = Field(..., min_length=1, max_length=100)
    emoji: str = "💪"
    split_type: str = "full_body"
    split_day_label: Optional[str] = None
    split_group_id: Optional[str] = None
    blocks: list[WorkoutBlock] = Field(default_factory=list)
    rest_duration_seconds: int = 60


class TemplateUpdate(BaseModel):
    """Request model for updating a workout template."""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    emoji: Optional[str] = None
    split_type: Optional[str] = None
    split_day_label: Optional[str] = None
    blocks: Optional[list[WorkoutBlock]] = None
    rest_duration_seconds: Optional[int] = None


# ── Workout Sessions (Completed Logs) ─────────────────────────────────────────

class CompletedSet(BaseModel):
    """A single logged set within a session exercise."""
    set_index: int
    target_reps: int = 0
    target_weight: Optional[float] = None
    actual_reps: int = 0
    actual_weight: Optional[float] = None
    status: str = "completed"  # SetCompletionStatus value
    is_pr: bool = False
    rpe: Optional[int] = None  # Rated perceived exertion 1-10
    notes: Optional[str] = None
    was_camera_tracked: bool = False


class CompletedExercise(BaseModel):
    """A completed exercise within a session."""
    exercise_id: str
    exercise_name: str
    equipment_type: str = ""
    pose_type: Optional[str] = None
    set_type: str = "straight"
    group_id: Optional[str] = None
    block_name: Optional[str] = None
    sets: list[CompletedSet] = Field(default_factory=list)


class WorkoutSession(BaseModel):
    """A completed workout session."""
    session_id: str
    user_id: str
    template_id: Optional[str] = None
    template_name: str = ""
    started_at: datetime
    ended_at: datetime
    duration_seconds: int = 0
    exercises: list[CompletedExercise] = Field(default_factory=list)
    total_sets: int = 0
    total_reps: int = 0
    total_volume: float = 0.0  # sum(weight * reps) across all sets
    prs: list[dict] = Field(default_factory=list)
    heart_rate_avg: Optional[int] = None
    heart_rate_max: Optional[int] = None
    notes: Optional[str] = None
    # Attribution fields
    source: str = WorkoutSource.USER_MANUAL  # WorkoutSource value
    created_by: str = SessionCreatedBy.USER  # "user" or "advisor"
    creator_id: Optional[str] = None  # user_id of whoever created this
    advisor_notes: Optional[str] = None  # advisor-only annotation
    created_at: datetime = Field(default_factory=datetime.utcnow)


class SessionCreate(BaseModel):
    """Request model for saving a completed workout session."""
    template_id: Optional[str] = None
    template_name: str = ""
    started_at: str  # ISO datetime string
    ended_at: str
    duration_seconds: int = 0
    exercises: list[CompletedExercise] = Field(default_factory=list)
    heart_rate_avg: Optional[int] = None
    heart_rate_max: Optional[int] = None
    notes: Optional[str] = None
    source: str = WorkoutSource.USER_MANUAL


class AdvisorSessionCreate(BaseModel):
    """Request model for an advisor logging a session on behalf of a user."""
    template_id: Optional[str] = None
    template_name: str = ""
    started_at: str  # ISO datetime string
    ended_at: str
    duration_seconds: int = 0
    exercises: list[CompletedExercise] = Field(default_factory=list)
    notes: Optional[str] = None
    advisor_notes: Optional[str] = None


class SessionUpdate(BaseModel):
    """Request model for editing a session (post-workout corrections)."""
    exercises: Optional[list[CompletedExercise]] = None
    notes: Optional[str] = None
    advisor_notes: Optional[str] = None


# ── Personal Records ───────────────────────────────────────────────────────────

class PersonalRecord(BaseModel):
    """A personal record for an exercise."""
    pr_id: str
    user_id: str
    exercise_id: str
    exercise_name: str = ""
    pr_type: str  # PrType value
    value: float
    previous_value: Optional[float] = None
    session_id: str
    achieved_at: datetime = Field(default_factory=datetime.utcnow)


# ── Overload Advice ────────────────────────────────────────────────────────────

class OverloadSuggestion(BaseModel):
    """A progressive overload suggestion for an exercise."""
    exercise_id: str
    exercise_name: str
    suggestion_type: str  # "increase_weight", "increase_reps", "adjust_rest", "adjust_volume"
    current_value: float
    suggested_value: float
    reasoning: str
