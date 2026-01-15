"""Activity data models for Lumie API."""
from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


class ActivityIntensity(str, Enum):
    """Activity intensity levels - teen-safe categorical scale only."""
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"


class ActivitySource(str, Enum):
    """Source of activity data."""
    RING = "ring"
    MANUAL = "manual"


class RingStatus(str, Enum):
    """Lumie Ring connection status."""
    CONNECTED = "connected"
    DISCONNECTED = "disconnected"
    SYNCING = "syncing"


class ActivityType(BaseModel):
    """Predefined activity type."""
    id: str
    name: str
    icon: str
    category: str


class ActivityRecord(BaseModel):
    """Single activity record."""
    id: str
    activity_type_id: str
    start_time: datetime
    end_time: datetime
    duration_minutes: int = Field(..., ge=1)
    intensity: Optional[ActivityIntensity] = None
    source: ActivitySource
    is_estimated: bool = False
    heart_rate_avg: Optional[int] = Field(None, ge=30, le=220)
    heart_rate_max: Optional[int] = Field(None, ge=30, le=220)
    notes: Optional[str] = None


class ActivityRecordCreate(BaseModel):
    """Request model for creating an activity record."""
    activity_type_id: str
    start_time: datetime
    end_time: datetime
    intensity: Optional[ActivityIntensity] = None
    source: ActivitySource
    is_estimated: bool = False
    heart_rate_avg: Optional[int] = Field(None, ge=30, le=220)
    heart_rate_max: Optional[int] = Field(None, ge=30, le=220)
    notes: Optional[str] = None


class DailyActivitySummary(BaseModel):
    """Daily activity summary."""
    date: datetime
    total_active_minutes: int = Field(..., ge=0)
    goal_minutes: int = Field(..., ge=0)
    dominant_intensity: ActivityIntensity
    activities: list[ActivityRecord] = []
    ring_tracked_minutes: int = Field(..., ge=0)
    manual_minutes: int = Field(..., ge=0)


class AdaptiveGoal(BaseModel):
    """Adaptive activity goal for a specific day."""
    date: datetime
    recommended_minutes: int = Field(..., ge=0)
    reason: str
    factors: list[str] = []
    is_reduced: bool = False


class WalkTestResult(BaseModel):
    """Six-minute walk test result."""
    id: str
    date: datetime
    distance_meters: float = Field(..., ge=0)
    duration_seconds: int = Field(..., ge=0)
    avg_heart_rate: Optional[int] = Field(None, ge=30, le=220)
    max_heart_rate: Optional[int] = Field(None, ge=30, le=220)
    recovery_heart_rate: Optional[int] = Field(None, ge=30, le=220)
    notes: Optional[str] = None


class WalkTestResultCreate(BaseModel):
    """Request model for creating a walk test result."""
    distance_meters: float = Field(..., ge=0)
    duration_seconds: int = Field(..., ge=0)
    avg_heart_rate: Optional[int] = Field(None, ge=30, le=220)
    max_heart_rate: Optional[int] = Field(None, ge=30, le=220)
    recovery_heart_rate: Optional[int] = Field(None, ge=30, le=220)
    notes: Optional[str] = None


class RingDetectedActivity(BaseModel):
    """Activity detected by the Lumie Ring."""
    start_time: datetime
    end_time: datetime
    duration_minutes: int = Field(..., ge=1)
    suggested_activity_type_id: str
    confidence: float = Field(..., ge=0, le=1)
    heart_rate_avg: Optional[int] = Field(None, ge=30, le=220)
    heart_rate_max: Optional[int] = Field(None, ge=30, le=220)
    measured_intensity: Optional[ActivityIntensity] = None


class RingInfo(BaseModel):
    """Lumie Ring information."""
    status: RingStatus
    battery_level: Optional[int] = Field(None, ge=0, le=100)
    last_sync: Optional[datetime] = None
    firmware_version: Optional[str] = None


class UserActivityProfile(BaseModel):
    """User's activity profile for adaptive goals."""
    user_id: str
    baseline_activity_minutes: int = Field(default=45, ge=0)
    sleep_quality_score: Optional[float] = Field(None, ge=0, le=1)
    fatigue_level: Optional[float] = Field(None, ge=0, le=1)
    recent_activity_trend: Optional[str] = None


# Predefined activity types
ACTIVITY_TYPES = [
    ActivityType(id="walking", name="Walking", icon="🚶", category="Movement"),
    ActivityType(id="running", name="Running", icon="🏃", category="Movement"),
    ActivityType(id="cycling", name="Cycling", icon="🚴", category="Movement"),
    ActivityType(id="swimming", name="Swimming", icon="🏊", category="Movement"),
    ActivityType(id="yoga", name="Yoga", icon="🧘", category="Wellness"),
    ActivityType(id="stretching", name="Stretching", icon="🤸", category="Wellness"),
    ActivityType(id="dancing", name="Dancing", icon="💃", category="Movement"),
    ActivityType(id="basketball", name="Basketball", icon="🏀", category="Sports"),
    ActivityType(id="soccer", name="Soccer", icon="⚽", category="Sports"),
    ActivityType(id="tennis", name="Tennis", icon="🎾", category="Sports"),
    ActivityType(id="hiking", name="Hiking", icon="🥾", category="Outdoor"),
    ActivityType(id="gym", name="Gym Workout", icon="💪", category="Fitness"),
    ActivityType(id="other", name="Other", icon="⭐", category="Other"),
]
