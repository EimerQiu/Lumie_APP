"""API routes for Lumie Activity feature."""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException, Query

from ..models.activity import (
    ActivityRecordCreate,
    ActivityRecord,
    ActivityType,
    AdaptiveGoal,
    DailyActivitySummary,
    RingDetectedActivity,
    RingInfo,
    WalkTestResult,
    WalkTestResultCreate,
    ACTIVITY_TYPES,
)
from ..services.activity_service import activity_service


router = APIRouter()


# Activity Types
@router.get("/activity-types", response_model=list[ActivityType])
async def get_activity_types():
    """Get all predefined activity types."""
    return ACTIVITY_TYPES


# Daily Summary
@router.get("/activity/daily", response_model=DailyActivitySummary)
async def get_daily_summary(
    date: Optional[datetime] = Query(None, description="Date to get summary for (defaults to today)")
):
    """Get activity summary for a specific day."""
    target_date = date or datetime.now()
    return activity_service.get_daily_summary(target_date)


# Weekly Summary
@router.get("/activity/weekly", response_model=list[DailyActivitySummary])
async def get_weekly_summary(
    end_date: Optional[datetime] = Query(None, description="End date for 7-day summary")
):
    """Get activity summaries for the past 7 days."""
    target_date = end_date or datetime.now()
    return activity_service.get_weekly_summary(target_date)


# Adaptive Goals
@router.get("/activity/goal", response_model=AdaptiveGoal)
async def get_adaptive_goal(
    date: Optional[datetime] = Query(None, description="Date to get goal for")
):
    """Get adaptive activity goal for a specific day."""
    target_date = date or datetime.now()
    return activity_service.get_adaptive_goal(target_date)


# Activity Records
@router.post("/activity", response_model=ActivityRecord)
async def create_activity(data: ActivityRecordCreate):
    """Create a new activity record (manual entry)."""
    if data.end_time <= data.start_time:
        raise HTTPException(
            status_code=400,
            detail="End time must be after start time"
        )

    # Validate activity type
    valid_types = [t.id for t in ACTIVITY_TYPES]
    if data.activity_type_id not in valid_types:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid activity type. Must be one of: {valid_types}"
        )

    return activity_service.create_activity(data)


# Ring Status
@router.get("/ring/status", response_model=RingInfo)
async def get_ring_status():
    """Get current Lumie Ring status and information."""
    return activity_service.get_ring_info()


# Ring Detected Activities
@router.get("/ring/detected", response_model=list[RingDetectedActivity])
async def get_detected_activities():
    """Get activities detected by the ring but not yet confirmed."""
    return activity_service.get_detected_activities()


# Six-Minute Walk Test
@router.get("/walk-test/history", response_model=list[WalkTestResult])
async def get_walk_test_history(
    limit: int = Query(10, ge=1, le=50, description="Number of results to return")
):
    """Get walk test history."""
    return activity_service.get_walk_tests(limit)


@router.post("/walk-test", response_model=WalkTestResult)
async def create_walk_test(data: WalkTestResultCreate):
    """Save a new walk test result."""
    return activity_service.create_walk_test(data)


@router.get("/walk-test/best", response_model=Optional[WalkTestResult])
async def get_best_walk_test():
    """Get the user's best walk test result for comparison."""
    tests = activity_service.get_walk_tests(limit=100)
    if not tests:
        return None
    return max(tests, key=lambda x: x.distance_meters)


# Health check
@router.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "service": "lumie-activity-api",
        "version": "1.0.0",
    }
