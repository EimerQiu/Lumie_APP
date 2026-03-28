"""Sleep data service — MongoDB persistence and aggregation."""
import logging
from datetime import datetime
from typing import Optional

from ..core.database import get_database
from ..models.sleep import (
    SleepSessionSync,
    SleepSessionResponse,
    SleepStageData,
    SleepSummaryResponse,
    SleepTargetResponse,
)

logger = logging.getLogger(__name__)


class SleepService:
    async def sync_sessions(self, user_id: str, sessions: list[SleepSessionSync]) -> None:
        """Upsert sleep sessions uploaded from the ring."""
        db = get_database()
        for s in sessions:
            await db.sleep_sessions.update_one(
                {"user_id": user_id, "session_id": s.session_id},
                {
                    "$set": {
                        "user_id": user_id,
                        "session_id": s.session_id,
                        "bedtime": s.bedtime,
                        "wake_time": s.wake_time,
                        "total_sleep_minutes": s.total_sleep_minutes,
                        "time_awake_minutes": s.time_awake_minutes,
                        "stages": [stage.model_dump() for stage in s.stages],
                        "resting_heart_rate": s.resting_heart_rate,
                        "sleep_quality_score": s.sleep_quality_score,
                        "source": s.source,
                        "created_at": s.wake_time,
                    }
                },
                upsert=True,
            )
        logger.info("[sleep] synced %d session(s) for user %s", len(sessions), user_id)

    async def get_latest(self, user_id: str) -> Optional[SleepSessionResponse]:
        """Return the most recent sleep session for the user."""
        db = get_database()
        doc = await db.sleep_sessions.find_one(
            {"user_id": user_id},
            sort=[("bedtime", -1)],
        )
        return self._doc_to_response(doc) if doc else None

    async def get_history(
        self, user_id: str, start: datetime, end: datetime
    ) -> list[SleepSessionResponse]:
        """Return sleep sessions in the given date range, newest first."""
        db = get_database()
        cursor = db.sleep_sessions.find(
            {"user_id": user_id, "bedtime": {"$gte": start, "$lte": end}},
            sort=[("bedtime", -1)],
        )
        return [self._doc_to_response(doc) async for doc in cursor]

    async def get_summary(
        self, user_id: str, start: datetime, end: datetime
    ) -> SleepSummaryResponse:
        """Aggregate sleep stats for the given date range."""
        sessions = await self.get_history(user_id, start, end)
        n = len(sessions)

        if n == 0:
            return SleepSummaryResponse(
                start_date=start,
                end_date=end,
                average_sleep_hours=0.0,
                average_resting_hr=0.0,
                average_sleep_quality=0.0,
                sleep_consistency=0.0,
                average_stage_percentages={},
            )

        avg_sleep_hours = sum(s.total_sleep_minutes for s in sessions) / n / 60
        avg_resting_hr = sum(s.resting_heart_rate for s in sessions) / n
        avg_quality = sum(s.sleep_quality_score for s in sessions) / n

        # Average stage percentages across sessions
        stage_sums: dict[str, float] = {}
        for s in sessions:
            for stage in s.stages:
                stage_sums[stage.stage] = stage_sums.get(stage.stage, 0.0) + stage.percentage
        avg_stages = {k: round(v / n, 1) for k, v in stage_sums.items()}

        # Sleep consistency: how similar are bedtimes?
        # Expressed as 0–1 where 1 = perfectly consistent
        if n > 1:
            bedtime_minutes = [s.bedtime.hour * 60 + s.bedtime.minute for s in sessions]
            mean_bt = sum(bedtime_minutes) / n
            variance = sum((bt - mean_bt) ** 2 for bt in bedtime_minutes) / n
            std_dev = variance ** 0.5  # minutes
            # Map std_dev=0 → 1.0, std_dev=60 → 0.0
            consistency = round(max(0.0, 1.0 - std_dev / 60.0), 2)
        else:
            consistency = 1.0

        return SleepSummaryResponse(
            start_date=start,
            end_date=end,
            average_sleep_hours=round(avg_sleep_hours, 2),
            average_resting_hr=round(avg_resting_hr, 1),
            average_sleep_quality=round(avg_quality, 1),
            sleep_consistency=consistency,
            average_stage_percentages=avg_stages,
        )

    async def get_target(self, user_id: str) -> SleepTargetResponse:
        """Return age-appropriate sleep target (CDC recommendations)."""
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id})
        age: int = ((profile or {}).get("age") or 16)

        # CDC: teens 13-18 need 8-10h; adults 18+ need 7-9h
        if age < 18:
            return SleepTargetResponse(
                min_duration_minutes=8 * 60,
                max_duration_minutes=10 * 60,
                target_duration_minutes=9 * 60,
                target_stage_percentages={"light": 45.0, "deep": 25.0, "rem": 25.0},
            )
        else:
            return SleepTargetResponse(
                min_duration_minutes=7 * 60,
                max_duration_minutes=9 * 60,
                target_duration_minutes=8 * 60,
                target_stage_percentages={"light": 45.0, "deep": 25.0, "rem": 25.0},
            )

    def _doc_to_response(self, doc: dict) -> SleepSessionResponse:
        return SleepSessionResponse(
            session_id=doc["session_id"],
            user_id=doc["user_id"],
            bedtime=doc["bedtime"],
            wake_time=doc["wake_time"],
            total_sleep_minutes=doc["total_sleep_minutes"],
            time_awake_minutes=doc["time_awake_minutes"],
            stages=[SleepStageData(**s) for s in doc["stages"]],
            resting_heart_rate=doc.get("resting_heart_rate", 0),
            sleep_quality_score=doc["sleep_quality_score"],
            created_at=doc["created_at"],
            source=doc.get("source", "ring"),  # default for records before this field existed
        )


sleep_service = SleepService()
