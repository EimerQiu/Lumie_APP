"""Activity service with mock data generation for demo."""
import random
import uuid
from datetime import datetime, timedelta
from typing import Optional

from ..models.activity import (
    ActivityIntensity,
    ActivityRecord,
    ActivityRecordCreate,
    ActivitySource,
    AdaptiveGoal,
    DailyActivitySummary,
    RingDetectedActivity,
    RingInfo,
    RingStatus,
    WalkTestResult,
    WalkTestResultCreate,
    ACTIVITY_TYPES,
)


class ActivityService:
    """Service for managing activity data (mock implementation for demo)."""

    def __init__(self):
        self._activities: list[ActivityRecord] = []
        self._walk_tests: list[WalkTestResult] = []
        self._generate_mock_data()

    def _generate_mock_data(self):
        """Generate mock activity data for the past 7 days."""
        now = datetime.now()

        for days_ago in range(7):
            day = now - timedelta(days=days_ago)
            num_activities = random.randint(2, 5)

            for _ in range(num_activities):
                activity_type = random.choice(ACTIVITY_TYPES[:10])
                duration = random.randint(10, 45)
                is_manual = random.random() < 0.2

                hour = random.randint(6, 20)
                start_time = day.replace(hour=hour, minute=random.randint(0, 59))
                end_time = start_time + timedelta(minutes=duration)

                activity = ActivityRecord(
                    id=str(uuid.uuid4()),
                    activity_type_id=activity_type.id,
                    start_time=start_time,
                    end_time=end_time,
                    duration_minutes=duration,
                    intensity=random.choice(list(ActivityIntensity)),
                    source=ActivitySource.MANUAL if is_manual else ActivitySource.RING,
                    is_estimated=is_manual,
                    heart_rate_avg=random.randint(70, 120) if not is_manual else None,
                    heart_rate_max=random.randint(100, 160) if not is_manual else None,
                )
                self._activities.append(activity)

        # Generate some walk test results
        for i in range(3):
            test_date = now - timedelta(days=i * 14)
            test = WalkTestResult(
                id=str(uuid.uuid4()),
                date=test_date,
                distance_meters=350 + random.randint(0, 150),
                duration_seconds=360,
                avg_heart_rate=random.randint(85, 110),
                max_heart_rate=random.randint(110, 140),
                recovery_heart_rate=random.randint(70, 95),
            )
            self._walk_tests.append(test)

    def get_daily_summary(self, date: datetime) -> DailyActivitySummary:
        """Get activity summary for a specific day."""
        day_start = date.replace(hour=0, minute=0, second=0, microsecond=0)
        day_end = day_start + timedelta(days=1)

        day_activities = [
            a for a in self._activities
            if day_start <= a.start_time < day_end
        ]

        total_minutes = sum(a.duration_minutes for a in day_activities)
        ring_minutes = sum(
            a.duration_minutes for a in day_activities
            if a.source == ActivitySource.RING
        )
        manual_minutes = total_minutes - ring_minutes

        # Calculate dominant intensity
        intensity_counts = {i: 0 for i in ActivityIntensity}
        for a in day_activities:
            if a.intensity:
                intensity_counts[a.intensity] += a.duration_minutes

        dominant = max(intensity_counts, key=intensity_counts.get)

        # Adaptive goal based on time of week
        weekday = date.weekday()
        base_goal = 60 if weekday < 5 else 45

        return DailyActivitySummary(
            date=day_start,
            total_active_minutes=total_minutes,
            goal_minutes=base_goal,
            dominant_intensity=dominant,
            activities=day_activities,
            ring_tracked_minutes=ring_minutes,
            manual_minutes=manual_minutes,
        )

    def get_weekly_summary(self, end_date: datetime) -> list[DailyActivitySummary]:
        """Get activity summaries for the past 7 days."""
        summaries = []
        for i in range(7):
            day = end_date - timedelta(days=i)
            summaries.append(self.get_daily_summary(day))
        return summaries

    def get_adaptive_goal(self, date: datetime) -> AdaptiveGoal:
        """Calculate adaptive activity goal for a specific day."""
        # Get yesterday's data
        yesterday = date - timedelta(days=1)
        yesterday_summary = self.get_daily_summary(yesterday)

        # Base goal calculation
        base_goal = 60
        factors = []
        is_reduced = False

        # Adjust based on previous day activity
        if yesterday_summary.total_active_minutes > 90:
            base_goal -= 15
            factors.append("High activity yesterday")
            is_reduced = True
        elif yesterday_summary.total_active_minutes < 30:
            base_goal += 5
            factors.append("Low activity yesterday")
        else:
            factors.append("Moderate activity yesterday")

        # Weekend adjustment
        if date.weekday() >= 5:
            base_goal -= 10
            factors.append("Weekend rest day")
            is_reduced = True

        # Mock sleep quality factor
        sleep_quality = random.uniform(0.5, 1.0)
        if sleep_quality < 0.6:
            base_goal -= 15
            factors.append("Poor sleep quality")
            is_reduced = True
        elif sleep_quality > 0.8:
            factors.append("Good sleep last night")

        # Ensure minimum goal
        base_goal = max(30, base_goal)

        reason = "Based on your recent rest and activity patterns"
        if is_reduced:
            reason = "Today's goal is adjusted to help you recover"

        return AdaptiveGoal(
            date=date,
            recommended_minutes=base_goal,
            reason=reason,
            factors=factors,
            is_reduced=is_reduced,
        )

    def create_activity(self, data: ActivityRecordCreate) -> ActivityRecord:
        """Create a new activity record."""
        duration = int((data.end_time - data.start_time).total_seconds() / 60)

        activity = ActivityRecord(
            id=str(uuid.uuid4()),
            activity_type_id=data.activity_type_id,
            start_time=data.start_time,
            end_time=data.end_time,
            duration_minutes=duration,
            intensity=data.intensity,
            source=data.source,
            is_estimated=data.is_estimated,
            heart_rate_avg=data.heart_rate_avg,
            heart_rate_max=data.heart_rate_max,
            notes=data.notes,
        )

        self._activities.append(activity)
        return activity

    def get_detected_activities(self) -> list[RingDetectedActivity]:
        """Get activities detected by the ring but not yet confirmed."""
        # Generate mock detected activity
        now = datetime.now()
        return [
            RingDetectedActivity(
                start_time=now - timedelta(hours=2),
                end_time=now - timedelta(hours=1, minutes=35),
                duration_minutes=25,
                suggested_activity_type_id="walking",
                confidence=0.75,
                heart_rate_avg=88,
                heart_rate_max=105,
                measured_intensity=ActivityIntensity.MODERATE,
            )
        ]

    def get_ring_info(self) -> RingInfo:
        """Get current ring status and info."""
        return RingInfo(
            status=RingStatus.CONNECTED,
            battery_level=random.randint(60, 95),
            last_sync=datetime.now() - timedelta(minutes=random.randint(1, 30)),
            firmware_version="1.2.3",
        )

    def get_walk_tests(self, limit: int = 10) -> list[WalkTestResult]:
        """Get walk test history."""
        return sorted(
            self._walk_tests,
            key=lambda x: x.date,
            reverse=True
        )[:limit]

    def create_walk_test(self, data: WalkTestResultCreate) -> WalkTestResult:
        """Save a new walk test result."""
        test = WalkTestResult(
            id=str(uuid.uuid4()),
            date=datetime.now(),
            distance_meters=data.distance_meters,
            duration_seconds=data.duration_seconds,
            avg_heart_rate=data.avg_heart_rate,
            max_heart_rate=data.max_heart_rate,
            recovery_heart_rate=data.recovery_heart_rate,
            notes=data.notes,
        )
        self._walk_tests.append(test)
        return test

    def get_walk_test_comparison(self, current: WalkTestResult) -> Optional[WalkTestResult]:
        """Get the user's best walk test for comparison."""
        if not self._walk_tests:
            return None
        return max(self._walk_tests, key=lambda x: x.distance_meters)


# Singleton service instance
activity_service = ActivityService()
