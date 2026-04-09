"""Heart Rate service — sync ring readings and save manual measurement sessions."""
import logging
from datetime import datetime, timedelta
from typing import List

from bson import ObjectId

from ..core.database import get_database
from ..models.hr import HrDataPoint, HrSyncResponse
from ..models.hr_session import (
    HrSessionCreate,
    HrSessionSaveResponse,
    HrSessionSummary,
    HrBucketReading,
    HrBucketResponse,
    HrSessionTimeseriesResponse,
)

logger = logging.getLogger(__name__)

# Each bucket covers this many seconds of the session timeline.
# 5 minutes → ≤300 readings/bucket at 1 Hz, 18 buckets for a 90-min session.
_BUCKET_SECONDS = 5 * 60


class HrService:
    # ── Ring background sync (existing) ──────────────────────────────────────

    async def sync_readings(
        self, user_id: str, readings: List[HrDataPoint]
    ) -> HrSyncResponse:
        """Upsert periodic HR readings fetched from the ring. (user_id, timestamp) is unique."""
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

    # ── Manual measurement sessions ───────────────────────────────────────────

    async def save_session(
        self, user_id: str, data: HrSessionCreate
    ) -> HrSessionSaveResponse:
        """
        Persist a completed HR measurement session.

        Two documents are written:
          • hr_sessions  — one summary record (avg/min/max, duration, count)
          • hr_timeseries — N bucket documents, each covering _BUCKET_SECONDS of
                            the session timeline, containing the raw readings as
                            compact {t, bpm} pairs (t = seconds from bucket_start).

        Bucket alignment: buckets are indexed from session start, not from
        midnight, so bucket 0 always starts at started_at.
        """
        db = get_database()
        now = datetime.utcnow()

        duration = max(0, int((data.ended_at - data.started_at).total_seconds()))

        # 1. Insert session summary
        session_doc = {
            "user_id": user_id,
            "started_at": data.started_at,
            "ended_at": data.ended_at,
            "duration_seconds": duration,
            "avg_bpm": data.avg_bpm,
            "min_bpm": data.min_bpm,
            "max_bpm": data.max_bpm,
            "reading_count": len(data.readings),
            "created_at": now,
        }
        result = await db.hr_sessions.insert_one(session_doc)
        session_id = str(result.inserted_id)

        if not data.readings:
            return HrSessionSaveResponse(
                session_id=session_id, inserted_buckets=0, reading_count=0
            )

        # 2. Distribute readings into buckets keyed by bucket index
        #    bucket_index = floor(offset_from_start / BUCKET_SECONDS)
        bucket_map: dict[int, list[dict]] = {}
        for r in data.readings:
            offset = max(
                0, int((r.timestamp - data.started_at).total_seconds())
            )
            idx = offset // _BUCKET_SECONDS
            t = offset - idx * _BUCKET_SECONDS  # offset inside the bucket
            bucket_map.setdefault(idx, []).append({"t": t, "bpm": r.bpm})

        # 3. Build bucket documents (sorted by index so they insert in order)
        bucket_docs = []
        for idx in sorted(bucket_map.keys()):
            readings = bucket_map[idx]
            bucket_start = data.started_at + timedelta(seconds=idx * _BUCKET_SECONDS)
            bucket_end = min(
                bucket_start + timedelta(seconds=_BUCKET_SECONDS),
                data.ended_at,
            )
            bpms = [r["bpm"] for r in readings]
            # Sort readings within the bucket by time offset for clean retrieval
            readings.sort(key=lambda r: r["t"])
            bucket_docs.append(
                {
                    "session_id": session_id,
                    "user_id": user_id,
                    "bucket_start": bucket_start,
                    "bucket_end": bucket_end,
                    "readings": readings,
                    "count": len(readings),
                    "sum_bpm": sum(bpms),
                    "min_bpm": min(bpms),
                    "max_bpm": max(bpms),
                }
            )

        if bucket_docs:
            await db.hr_timeseries.insert_many(bucket_docs)

        return HrSessionSaveResponse(
            session_id=session_id,
            inserted_buckets=len(bucket_docs),
            reading_count=len(data.readings),
        )

    async def list_sessions(
        self, user_id: str, limit: int = 20
    ) -> List[HrSessionSummary]:
        """Return the most recent HR sessions for a user, newest first."""
        db = get_database()
        cursor = (
            db.hr_sessions.find({"user_id": user_id})
            .sort("started_at", -1)
            .limit(limit)
        )
        sessions = []
        async for doc in cursor:
            sessions.append(
                HrSessionSummary(
                    session_id=str(doc["_id"]),
                    started_at=doc["started_at"],
                    ended_at=doc["ended_at"],
                    duration_seconds=doc["duration_seconds"],
                    avg_bpm=doc["avg_bpm"],
                    min_bpm=doc["min_bpm"],
                    max_bpm=doc["max_bpm"],
                    reading_count=doc["reading_count"],
                    created_at=doc["created_at"],
                )
            )
        return sessions

    async def get_session_timeseries(
        self, user_id: str, session_id: str
    ) -> HrSessionTimeseriesResponse:
        """
        Return all buckets for a session, in chronological order.

        Each bucket contains pre-computed stats (avg/min/max) AND the full
        list of {t, bpm} readings so callers can reconstruct the exact
        time-series (timestamp = bucket_start + t seconds).
        """
        db = get_database()

        try:
            oid = ObjectId(session_id)
        except Exception:
            return HrSessionTimeseriesResponse(session_id=session_id, buckets=[])

        # Verify ownership
        session = await db.hr_sessions.find_one({"_id": oid, "user_id": user_id})
        if session is None:
            return HrSessionTimeseriesResponse(session_id=session_id, buckets=[])

        cursor = db.hr_timeseries.find(
            {"session_id": session_id, "user_id": user_id}
        ).sort("bucket_start", 1)

        buckets = []
        async for doc in cursor:
            count = doc["count"]
            avg_bpm = doc["sum_bpm"] / count if count > 0 else None
            buckets.append(
                HrBucketResponse(
                    bucket_start=doc["bucket_start"],
                    bucket_end=doc["bucket_end"],
                    count=count,
                    avg_bpm=round(avg_bpm, 1) if avg_bpm is not None else None,
                    min_bpm=doc["min_bpm"],
                    max_bpm=doc["max_bpm"],
                    readings=[
                        HrBucketReading(t=r["t"], bpm=r["bpm"])
                        for r in doc.get("readings", [])
                    ],
                )
            )

        return HrSessionTimeseriesResponse(session_id=session_id, buckets=buckets)


hr_service = HrService()
