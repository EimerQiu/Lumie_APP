"""SpO2 (blood oxygen) sync service — stores ring 0x66 readings in MongoDB."""
import logging
from datetime import datetime, timedelta
from typing import List

from ..core.database import get_database
from ..models.spo2 import (
    Spo2DataPoint,
    Spo2SyncResponse,
    Spo2ReadingResponse,
)

logger = logging.getLogger(__name__)


class Spo2Service:
    async def sync_readings(
        self, user_id: str, readings: List[Spo2DataPoint]
    ) -> Spo2SyncResponse:
        """Upsert SpO2 readings. Each (user_id, timestamp) pair is unique."""
        db = get_database()
        inserted = 0
        for point in readings:
            result = await db.spo2_readings.update_one(
                {"user_id": user_id, "timestamp": point.timestamp},
                {
                    "$set": {"spo2_percent": point.spo2_percent},
                    "$setOnInsert": {
                        "user_id": user_id,
                        "timestamp": point.timestamp,
                    },
                },
                upsert=True,
            )
            if result.upserted_id is not None:
                inserted += 1
        logger.info("[spo2] synced %d reading(s) for user %s", len(readings), user_id)
        return Spo2SyncResponse(inserted=inserted)

    async def get_history(
        self, user_id: str, days: int = 7
    ) -> List[Spo2ReadingResponse]:
        db = get_database()
        since = datetime.utcnow() - timedelta(days=days)
        cursor = db.spo2_readings.find(
            {"user_id": user_id, "timestamp": {"$gte": since}},
            sort=[("timestamp", -1)],
        )
        results = []
        async for doc in cursor:
            results.append(Spo2ReadingResponse(
                timestamp=doc["timestamp"],
                spo2_percent=doc["spo2_percent"],
            ))
        return results


spo2_service = Spo2Service()
