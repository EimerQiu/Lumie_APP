"""Service for managing user rest days."""
from datetime import datetime
from typing import Optional
from motor.motor_asyncio import AsyncIOMotorDatabase

from ..core.database import get_database


class RestDaysService:
    """Service for managing user rest days."""

    def __init__(self, db: Optional[AsyncIOMotorDatabase] = None):
        """Initialize the rest days service."""
        self.db = db or get_database()

    async def is_rest_day(self, user_id: str, date: datetime) -> bool:
        """
        Check if a specific date is a rest day for the user.

        Args:
            user_id: The user's ID
            date: The date to check

        Returns:
            True if the date is a rest day, False otherwise
        """
        profile = await self.db.profiles.find_one({"user_id": user_id})
        if not profile or not profile.get('rest_days'):
            return False

        rest_days = profile['rest_days']

        # Check weekly recurring rest days (0=Monday, 6=Sunday)
        weekday = date.weekday()
        if weekday in rest_days.get('weekly_rest_days', []):
            return True

        # Check specific dates
        date_str = date.date().isoformat()
        if date_str in rest_days.get('specific_dates', []):
            return True

        return False

    async def _get_latest_sleep(self, user_id: str) -> Optional[dict]:
        """
        Get the latest sleep session for a user.

        Args:
            user_id: The user's ID

        Returns:
            Latest sleep session data or None
        """
        # Query the sleep collection for the most recent sleep session
        sleep_session = await self.db.sleep.find_one(
            {"user_id": user_id},
            sort=[("wake_time", -1)]  # Sort by wake_time descending
        )
        return sleep_session

    async def should_suggest_rest_day(self, user_id: str) -> tuple[bool, dict]:
        """
        Check if we should suggest a rest day based on sleep quality.

        Args:
            user_id: The user's ID

        Returns:
            Tuple of (should_suggest, suggestion_data)
            - should_suggest: Boolean indicating if suggestion should be shown
            - suggestion_data: Dict with reason, sleep_quality, message, etc.
        """
        # Get latest sleep session
        latest_sleep = await self._get_latest_sleep(user_id)

        if not latest_sleep:
            return False, {}

        quality_score = latest_sleep.get('sleep_quality_score', 100)

        # Poor sleep threshold: < 60
        if quality_score < 60:
            # Check if today is already a rest day
            today = datetime.utcnow()
            is_already_rest = await self.is_rest_day(user_id, today)

            if not is_already_rest:
                return True, {
                    'reason': 'poor_sleep',
                    'sleep_quality': quality_score,
                    'sleep_date': latest_sleep.get('wake_time'),
                    'message': f'Your sleep quality was {quality_score}%. Consider taking today as a rest day.'
                }

        return False, {}

    async def get_rest_days(self, user_id: str) -> Optional[dict]:
        """
        Get user's rest days configuration.

        Args:
            user_id: The user's ID

        Returns:
            Rest days settings dict or None
        """
        profile = await self.db.profiles.find_one({"user_id": user_id})
        if not profile:
            return None

        return profile.get('rest_days')

    async def update_rest_days(self, user_id: str, rest_days_data: dict) -> dict:
        """
        Update user's rest days configuration.

        Args:
            user_id: The user's ID
            rest_days_data: Rest days settings data

        Returns:
            Updated rest days settings
        """
        # Add updated_at timestamp
        rest_days_data['updated_at'] = datetime.utcnow()

        # Update in database
        result = await self.db.profiles.update_one(
            {"user_id": user_id},
            {"$set": {
                "rest_days": rest_days_data,
                "updated_at": datetime.utcnow()
            }}
        )

        if result.modified_count == 0:
            raise ValueError("Profile not found or no changes made")

        return rest_days_data

    async def add_today_as_rest_day(self, user_id: str) -> dict:
        """
        Add today to the user's specific rest dates.

        Args:
            user_id: The user's ID

        Returns:
            Updated rest days settings
        """
        today_str = datetime.utcnow().date().isoformat()

        # Get current rest days
        current_rest_days = await self.get_rest_days(user_id)

        if not current_rest_days:
            # Create new rest days settings with today
            current_rest_days = {
                'weekly_rest_days': [],
                'specific_dates': [today_str],
                'updated_at': datetime.utcnow()
            }
        else:
            # Add today to specific dates if not already present
            specific_dates = current_rest_days.get('specific_dates', [])
            if today_str not in specific_dates:
                specific_dates.append(today_str)
                specific_dates.sort()
                current_rest_days['specific_dates'] = specific_dates
            current_rest_days['updated_at'] = datetime.utcnow()

        # Update in database
        await self.update_rest_days(user_id, current_rest_days)

        return current_rest_days


# Singleton instance
rest_days_service = RestDaysService()
