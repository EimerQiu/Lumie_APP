"""Daily step count service — syncs ring data and computes adaptive goals."""
import logging
from datetime import datetime, timedelta
from typing import Optional

from ..core.database import get_database
from ..models.steps import (
    DailyStepRecord,
    DailyStepResponse,
    StepGoalResponse,
    GoalSettingsResponse,
)

logger = logging.getLogger(__name__)

# ─── Conversion constant ──────────────────────────────────────────────────────
# 8 000 steps ≈ 60 active minutes (standard population average)
_STEPS_PER_MINUTE = 8000 / 60  # ≈ 133.3 steps/min


def _steps_to_minutes(steps: int) -> int:
    return round(steps * 60 / 8000)


def _minutes_to_steps(minutes: int) -> int:
    return round(minutes * 8000 / 60)


# ─── ICD-10 condition group → step baseline ───────────────────────────────────
# Maps ICD-10 code *prefixes* to a safe starting step goal.  The user may
# always override with a custom_goal.  Lookup is first-match by prefix length
# (longer / more-specific prefixes are tried before shorter ones).
#
# Tier 1 — severe fatigue, serious cardiac, genetic severe
_TIER1_CODES = {"G93.32", "M79.7", "R53.83", "I42", "I49.9", "Q20", "Q21", "Q24.9"}
_TIER1_STEPS = 4000  # 30 min

# Tier 2 — haematologic, genetic pulmonary
_TIER2_CODES = {"D57", "D57.1", "E84", "E84.0"}
_TIER2_STEPS = 3000  # ~23 min

# Tier 3 — respiratory, autoimmune, digestive IBD
_TIER3_CODES = {"J45", "J45.20", "J45.30", "J45.40", "J45.50",
                "M32", "M05", "K50", "K51"}
_TIER3_STEPS = 5000  # ~38 min

# Tier 4 — mild cardiac, mental health, neurological
_TIER4_CODES = {"I10", "I25", "F32", "F33", "F41.1", "F90", "G40", "G40.909", "G43", "M79.7"}
_TIER4_STEPS = 6000  # 45 min

# Tier 5 — diabetes, other endocrine — slight restriction
_TIER5_CODES = {"E10", "E10.9", "E11", "E11.9", "E05", "E06.3", "E66", "E66.01",
                "N18", "N18.3", "Z85", "Z85.3", "Z85.5"}
_TIER5_STEPS = 7000  # ~53 min

# Default (no condition or unlisted code)
_DEFAULT_STEPS = 8000  # 60 min

_BASE_WEEKDAY_MINUTES = 60
_BASE_WEEKEND_MINUTES = 45
_MIN_GOAL_MINUTES = 20
_MIN_GOAL_STEPS = _minutes_to_steps(_MIN_GOAL_MINUTES)


def _condition_step_baseline(icd10_code: Optional[str]) -> tuple[int, bool]:
    """Return (step_baseline, condition_adjusted) for the given ICD-10 code."""
    if not icd10_code:
        return _DEFAULT_STEPS, False
    code = icd10_code.strip()
    if code in _TIER2_CODES:
        return _TIER2_STEPS, True
    if code in _TIER1_CODES:
        return _TIER1_STEPS, True
    if code in _TIER3_CODES:
        return _TIER3_STEPS, True
    if code in _TIER4_CODES:
        return _TIER4_STEPS, True
    if code in _TIER5_CODES:
        return _TIER5_STEPS, True
    # Prefix match (e.g. "J45.9" → tier 3 because starts with "J45")
    for prefix, steps in [
        ("G93", _TIER1_STEPS), ("M79", _TIER1_STEPS), ("R53", _TIER1_STEPS),
        ("I42", _TIER1_STEPS), ("I49", _TIER1_STEPS), ("Q2", _TIER1_STEPS),
        ("D57", _TIER2_STEPS), ("E84", _TIER2_STEPS),
        ("J45", _TIER3_STEPS), ("M32", _TIER3_STEPS), ("M05", _TIER3_STEPS),
        ("K50", _TIER3_STEPS), ("K51", _TIER3_STEPS),
        ("I10", _TIER4_STEPS), ("I25", _TIER4_STEPS),
        ("F3", _TIER4_STEPS), ("F41", _TIER4_STEPS), ("F90", _TIER4_STEPS),
        ("G40", _TIER4_STEPS), ("G43", _TIER4_STEPS),
        ("E10", _TIER5_STEPS), ("E11", _TIER5_STEPS), ("E05", _TIER5_STEPS),
        ("E66", _TIER5_STEPS), ("N18", _TIER5_STEPS),
        ("Z85", _TIER5_STEPS),
    ]:
        if code.startswith(prefix):
            return steps, True
    return _DEFAULT_STEPS, False


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
                goal_steps=goal.goal_steps,
                goal_reason=goal.reason,
                goal_is_reduced=goal.is_reduced,
                goal_type=goal.goal_type,
            ))
        return results

    async def get_goal(self, user_id: str, date: datetime) -> StepGoalResponse:
        return await self._compute_goal(user_id, date)

    # ─── Goal settings ────────────────────────────────────────────────────────

    async def get_goal_settings(self, user_id: str) -> GoalSettingsResponse:
        """Return the user's goal-type preference and condition-adjusted defaults."""
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id})
        icd10_code = profile.get("icd10_code") if profile else None
        default_steps, condition_adjusted = _condition_step_baseline(icd10_code)
        default_minutes = _steps_to_minutes(default_steps)

        goal_settings = (profile or {}).get("goal_settings", {})
        return GoalSettingsResponse(
            goal_type=goal_settings.get("goal_type", "minutes"),
            custom_goal=goal_settings.get("custom_goal"),
            default_steps=default_steps,
            default_minutes=default_minutes,
            condition_adjusted=condition_adjusted,
        )

    async def update_goal_settings(
        self, user_id: str, goal_type: str, custom_goal: Optional[int]
    ) -> GoalSettingsResponse:
        db = get_database()
        await db.profiles.update_one(
            {"user_id": user_id},
            {"$set": {
                "goal_settings.goal_type": goal_type,
                "goal_settings.custom_goal": custom_goal,
                "updated_at": datetime.utcnow(),
            }},
            upsert=False,
        )
        return await self.get_goal_settings(user_id)

    # ─── Goal computation ────────────────────────────────────────────────────

    async def _compute_goal(self, user_id: str, date: datetime) -> StepGoalResponse:
        """Adaptive goal: condition-adjusted baseline, further modified by last
        night's sleep quality.  Honours the user's goal_type preference and any
        manual custom_goal override.
        """
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id})
        icd10_code = profile.get("icd10_code") if profile else None
        goal_settings = (profile or {}).get("goal_settings", {})
        goal_type = goal_settings.get("goal_type", "minutes")
        custom_goal = goal_settings.get("custom_goal")  # in the unit matching goal_type

        default_steps, condition_adjusted = _condition_step_baseline(icd10_code)

        # ── If user has a manual override, apply it directly ──────────────────
        if custom_goal is not None and custom_goal > 0:
            if goal_type == "steps":
                base_steps = custom_goal
                base_minutes = _steps_to_minutes(custom_goal)
            else:
                base_minutes = custom_goal
                base_steps = _minutes_to_steps(custom_goal)
        else:
            # Derive base from condition + weekday/weekend
            weekend_factor = _BASE_WEEKEND_MINUTES / _BASE_WEEKDAY_MINUTES  # 0.75
            if date.weekday() >= 5:
                base_steps = round(default_steps * weekend_factor)
                base_minutes = round(_steps_to_minutes(default_steps) * weekend_factor)
            else:
                base_steps = default_steps
                base_minutes = _steps_to_minutes(default_steps)

        # ── Sleep-quality reduction ───────────────────────────────────────────
        reduction_steps = 0
        reduction_minutes = 0
        reason_parts = []
        is_reduced = False

        prev_morning = (date - timedelta(days=1)).replace(
            hour=6, minute=0, second=0, microsecond=0
        )
        this_noon = date.replace(hour=13, minute=0, second=0, microsecond=0)
        sleep_doc = await db.sleep_sessions.find_one(
            {"user_id": user_id, "wake_time": {"$gte": prev_morning, "$lte": this_noon}},
            sort=[("wake_time", -1)],
        )

        if sleep_doc:
            quality = sleep_doc.get("sleep_quality_score", 0)
            if quality < 50:
                reduction_steps = _minutes_to_steps(15)
                reduction_minutes = 15
                reason_parts.append("poor sleep last night")
                is_reduced = True
            elif quality < 70:
                reduction_steps = _minutes_to_steps(5)
                reduction_minutes = 5
                reason_parts.append("fair sleep last night")
                is_reduced = True
            else:
                reason_parts.append("good sleep last night")
        else:
            reason_parts.append("no sleep data")

        if date.weekday() >= 5 and custom_goal is None:
            reason_parts.append("weekend")
            is_reduced = True

        if condition_adjusted and custom_goal is None:
            reason_parts.append("adjusted for your condition")

        goal_steps = max(_MIN_GOAL_STEPS, base_steps - reduction_steps)
        goal_minutes = max(_MIN_GOAL_MINUTES, base_minutes - reduction_minutes)

        if is_reduced or condition_adjusted:
            reason = f"Goal adjusted — {', '.join(reason_parts)}"
        else:
            reason = "Baseline goal"

        return StepGoalResponse(
            goal_minutes=goal_minutes,
            goal_steps=goal_steps,
            reason=reason,
            is_reduced=is_reduced,
            goal_type=goal_type,
            condition_adjusted=condition_adjusted,
        )


steps_service = StepsService()
