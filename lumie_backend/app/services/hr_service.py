"""Heart Rate sync service — stores ring HR readings in MongoDB."""
import logging
from typing import List

from ..core.database import get_database
from ..models.hr import HrDataPoint, HrSyncResponse

logger = logging.getLogger(__name__)


class HrService:
    async def sync_readings(
        self, user_id: str, readings: List[HrDataPoint]
    ) -> HrSyncResponse:
        """Upsert HR readings. Each (user_id, timestamp) pair is unique."""
        db = get_database()
        inserted = 0

        for point in readings:
            result = await db.hr_readings.update_one(
                {"user_id": user_id, "timestamp": point.timestamp},
                {
                    "$set": {"bpm": point.bpm},
                    "$setOnInsert": {
                        "user_id": user_id,
                        "timestamp": point.timestamp,
                    },
                },
                upsert=True,
            )
            if result.upserted_id is not None:
                inserted += 1

        return HrSyncResponse(inserted=inserted)


hr_service = HrService()
