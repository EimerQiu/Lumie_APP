"""HRV / stress / blood pressure sync service."""
import logging
from datetime import datetime, timedelta
from typing import List

from ..core.database import get_database
from ..models.hrv import HrvDataPoint, HrvSyncResponse, HrvReadingResponse

logger = logging.getLogger(__name__)


class HrvService:
    async def sync_readings(
        self, user_id: str, readings: List[HrvDataPoint]
    ) -> HrvSyncResponse:
        """Upsert HRV readings. Each (user_id, timestamp) pair is unique."""
        db = get_database()
        inserted = 0

        for pt in readings:
            result = await db.hrv_readings.update_one(
                {"user_id": user_id, "timestamp": pt.timestamp},
                {
                    "$set": {
                        "hrv_ms": pt.hrv_ms,
                        "heart_rate_bpm": pt.heart_rate_bpm,
                        "fatigue": pt.fatigue,
                        "systolic_mmhg": pt.systolic_mmhg,
                        "diastolic_mmhg": pt.diastolic_mmhg,
                    },
                    "$setOnInsert": {
                        "user_id": user_id,
                        "timestamp": pt.timestamp,
                        "source": "ring",
                        "created_at": datetime.utcnow(),
                    },
                },
                upsert=True,
            )
            if result.upserted_id is not None:
                inserted += 1

        logger.info(f"HRV sync: user={user_id} inserted={inserted}/{len(readings)}")
        return HrvSyncResponse(inserted=inserted)

    async def get_history(
        self,
        user_id: str,
        days: int = 7,
    ) -> List[HrvReadingResponse]:
        """Return HRV readings for the past N days, newest first."""
        db = get_database()
        since = datetime.utcnow() - timedelta(days=days)

        cursor = db.hrv_readings.find(
            {"user_id": user_id, "timestamp": {"$gte": since}},
            {"_id": 0},
        ).sort("timestamp", -1)

        results = []
        async for doc in cursor:
            results.append(HrvReadingResponse(
                timestamp=doc["timestamp"],
                hrv_ms=doc.get("hrv_ms", 0),
                heart_rate_bpm=doc.get("heart_rate_bpm", 0),
                fatigue=doc.get("fatigue", 0),
                systolic_mmhg=doc.get("systolic_mmhg", 0),
                diastolic_mmhg=doc.get("diastolic_mmhg", 0),
                source=doc.get("source", "ring"),
            ))
        return results


hrv_service = HrvService()
