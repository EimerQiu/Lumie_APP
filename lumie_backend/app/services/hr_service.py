"""Heart Rate service — sync ring readings and save manual measurement sessions."""
import logging
import shutil
from datetime import datetime, timedelta
from pathlib import Path
from typing import List

from bson import ObjectId
from fastapi import HTTPException, UploadFile, status

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
from .dayprint_service import log_hr_logged, attach_graph_to_hr_logged_event

logger = logging.getLogger(__name__)

# Each bucket covers this many seconds of the session timeline.
# 5 minutes → ≤300 readings/bucket at 1 Hz, 18 buckets for a 90-min session.
_BUCKET_SECONDS = 5 * 60


class HrService:
    _upload_root = Path(__file__).resolve().parents[2] / "uploads" / "hr_sessions"
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

        await log_hr_logged(
            user_id,
            session_id=session_id,
            avg_bpm=data.avg_bpm,
            min_bpm=data.min_bpm,
            max_bpm=data.max_bpm,
            duration_seconds=duration,
            reading_count=len(data.readings),
        )

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

    async def attach_session_graph(
        self,
        user_id: str,
        session_id: str,
        graph_file: UploadFile,
    ) -> dict:
        """Persist an HR graph image and attach it to the session's dayprint event."""
        db = get_database()
        try:
            oid = ObjectId(session_id)
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Session not found",
            )

        session = await db.hr_sessions.find_one({"_id": oid, "user_id": user_id})
        if session is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Session not found",
            )

        content_type = (graph_file.content_type or "").lower()
        if not content_type.startswith("image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Graph file must be an image",
            )

        ext = Path(graph_file.filename or "").suffix.strip().lower() or ".jpg"
        if len(ext) > 10:
            ext = ".jpg"

        session_dir = self._upload_root / session_id
        session_dir.mkdir(parents=True, exist_ok=True)
        storage_name = f"graph{ext}"
        storage_path = session_dir / storage_name

        try:
            with storage_path.open("wb") as out:
                shutil.copyfileobj(graph_file.file, out)
        finally:
            await graph_file.close()

        relative_path = f"hr_sessions/{session_id}/{storage_name}"
        image_url = f"/api/v1/uploads/{relative_path}"

        await db.hr_sessions.update_one(
            {"_id": oid, "user_id": user_id},
            {"$set": {
                "graph_image_path": relative_path,
                "graph_image_url": image_url,
                "updated_at": datetime.utcnow(),
            }},
        )

        await attach_graph_to_hr_logged_event(
            user_id,
            session_id=session_id,
            image_url=image_url,
        )

        return {"session_id": session_id, "image_url": image_url}


hr_service = HrService()
