"""Temperature sync service — stores ring 0x62 readings in MongoDB."""
import logging
from datetime import datetime, timedelta
from typing import List

from ..core.database import get_database
from ..models.temperature import (
    TemperatureDataPoint,
    TemperatureSyncResponse,
    TemperatureReadingResponse,
)

logger = logging.getLogger(__name__)


class TemperatureService:
    async def sync_readings(
        self, user_id: str, readings: List[TemperatureDataPoint]
    ) -> TemperatureSyncResponse:
        """Upsert temperature readings. Each (user_id, timestamp) pair is unique."""
        db = get_database()
        inserted = 0
        for point in readings:
            result = await db.temperature_readings.update_one(
                {"user_id": user_id, "timestamp": point.timestamp},
                {
                    "$set": {
                        "temp1_c": point.temp1_c,
                        "temp2_c": point.temp2_c,
                        "temp3_c": point.temp3_c,
                    },
                    "$setOnInsert": {
                        "user_id": user_id,
                        "timestamp": point.timestamp,
                    },
                },
                upsert=True,
            )
            if result.upserted_id is not None:
                inserted += 1
        logger.info("[temperature] synced %d reading(s) for user %s", len(readings), user_id)
        return TemperatureSyncResponse(inserted=inserted)

    async def get_history(
        self, user_id: str, days: int = 7
    ) -> List[TemperatureReadingResponse]:
        db = get_database()
        since = datetime.utcnow() - timedelta(days=days)
        cursor = db.temperature_readings.find(
            {"user_id": user_id, "timestamp": {"$gte": since}},
            sort=[("timestamp", -1)],
        )
        results = []
        async for doc in cursor:
            results.append(TemperatureReadingResponse(
                timestamp=doc["timestamp"],
                temp1_c=doc["temp1_c"],
                temp2_c=doc["temp2_c"],
                temp3_c=doc["temp3_c"],
            ))
        return results


temperature_service = TemperatureService()
