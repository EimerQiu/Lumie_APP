"""Daily step count service — syncs ring data and computes adaptive goals."""
import logging
from datetime import datetime, timedelta

from ..core.database import get_database
from ..models.steps import DailyStepRecord, DailyStepResponse, StepGoalResponse

logger = logging.getLogger(__name__)

_BASELINE_WEEKDAY = 60   # minutes
_BASELINE_WEEKEND = 45
_MIN_GOAL = 30


def _base_goal(date: datetime) -> int:
    return _BASELINE_WEEKEND if date.weekday() >= 5 else _BASELINE_WEEKDAY


class StepsService:
    async def sync_records(self, user_id: str, records: list[DailyStepRecord]) -> None:
        """Upsert daily step records keyed by (user_id, date_str)."""
        db = get_database()
        for rec in records:
            await db.daily_steps.update_one(
                {"user_id": user_id, "date_str": rec.date_str},
                {"$set": {
                    "user_id": user_id,
                    "date_str": rec.date_str,
                    "steps": rec.steps,
                    "exercise_time_seconds": rec.exercise_time_seconds,
                    "distance_km": rec.distance_km,
                    "synced_at": datetime.utcnow(),
                }},
                upsert=True,
            )
        logger.info("[steps] synced %d day(s) for user %s", len(records), user_id)

    async def get_history(
        self, user_id: str, start: datetime, end: datetime
    ) -> list[DailyStepResponse]:
        """Return step records in range [start, end], newest first."""
        db = get_database()
        start_str = start.strftime("%Y-%m-%d")
        end_str = end.strftime("%Y-%m-%d")
        cursor = db.daily_steps.find(
            {"user_id": user_id, "date_str": {"$gte": start_str, "$lte": end_str}},
            sort=[("date_str", -1)],
        )
        results = []
        async for doc in cursor:
            date = datetime.strptime(doc["date_str"], "%Y-%m-%d")
            goal = await self._compute_goal(user_id, date)
            results.append(DailyStepResponse(
                date_str=doc["date_str"],
                steps=doc["steps"],
                active_minutes=doc["exercise_time_seconds"] // 60,
                distance_km=doc["distance_km"],
                goal_minutes=goal.goal_minutes,
                goal_reason=goal.reason,
                goal_is_reduced=goal.is_reduced,
            ))
        return results

    async def get_goal(self, user_id: str, date: datetime) -> StepGoalResponse:
        return await self._compute_goal(user_id, date)

    async def _compute_goal(self, user_id: str, date: datetime) -> StepGoalResponse:
        """Adaptive goal: baseline adjusted by last night's sleep quality.

        Looks for a sleep session where the user woke up between yesterday
        6 AM and today 1 PM (covers the previous night's sleep).  If no sleep
        data is found the baseline is used unchanged.
        """
        base = _base_goal(date)
        reduction = 0
        reason_parts = []
        is_reduced = False

        db = get_database()
        prev_morning = (date - timedelta(days=1)).replace(
            hour=6, minute=0, second=0, microsecond=0
        )
        this_noon = date.replace(hour=13, minute=0, second=0, microsecond=0)

        sleep_doc = await db.sleep_sessions.find_one(
            {
                "user_id": user_id,
                "wake_time": {"$gte": prev_morning, "$lte": this_noon},
            },
            sort=[("wake_time", -1)],
        )

        if sleep_doc:
            quality = sleep_doc.get("sleep_quality_score", 0)
            if quality < 50:
                reduction = 15
                reason_parts.append("poor sleep last night")
                is_reduced = True
            elif quality < 70:
                reduction = 5
                reason_parts.append("fair sleep last night")
                is_reduced = True
            else:
                reason_parts.append("good sleep last night")
        else:
            reason_parts.append("no sleep data")

        if date.weekday() >= 5:
            reason_parts.append("weekend")
            is_reduced = True

        goal = max(_MIN_GOAL, base - reduction)
        if is_reduced:
            reason = f"Goal adjusted — {', '.join(reason_parts)}"
        else:
            reason = "Baseline goal"

        return StepGoalResponse(goal_minutes=goal, reason=reason, is_reduced=is_reduced)


steps_service = StepsService()
