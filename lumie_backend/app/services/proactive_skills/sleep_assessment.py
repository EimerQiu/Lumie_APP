"""Sleep domain assessment for proactive advisor."""
import logging
from datetime import datetime, timedelta

from ...models.proactive import ProactiveSkillResult, ProactiveStatus

logger = logging.getLogger(__name__)

SKILL_ID = "proactive_sleep_assessment"
DOMAIN = "sleep"


async def assess(db, user_id: str, now_utc: datetime) -> ProactiveSkillResult:
    """Assess recent sleep data and return a structured result."""
    sleep_cutoff_utc = now_utc - timedelta(hours=36)
    sleep = await db.sleep_sessions.find_one(
        {"user_id": user_id, "wake_time": {"$gte": sleep_cutoff_utc}},
        sort=[("wake_time", -1)],
    )

    if not sleep:
        return ProactiveSkillResult(
            skill_id=SKILL_ID,
            domain=DOMAIN,
            status=ProactiveStatus.MISSING,
            summary="No completed sleep session in the last 36 hours.",
            score=0.0,
            signals=["no_recent_sleep_data"],
            evidence={"collections_used": ["sleep_sessions"], "record_counts": {"sleep_sessions": 0}},
        )

    total_min = sleep.get("total_sleep_minutes") or 0
    quality = sleep.get("sleep_quality_score")
    rhr = sleep.get("resting_heart_rate")
    bedtime = sleep.get("bedtime")
    wake_time = sleep.get("wake_time")
    stages = sleep.get("stages") or []

    signals: list[str] = []
    actions: list[str] = []
    score = 0.0

    # Duration scoring
    if total_min < 300:  # < 5 hours
        score = max(score, 0.7)
        signals.append(f"very_short_sleep_{total_min}min")
        actions.append("Consider earlier bedtime tonight")
    elif total_min < 360:  # < 6 hours
        score = max(score, 0.45)
        signals.append(f"short_sleep_{total_min}min")
    elif total_min < 420:  # < 7 hours
        score = max(score, 0.2)
        signals.append(f"slightly_short_sleep_{total_min}min")

    # Quality scoring
    if quality is not None:
        if quality < 50:
            score = max(score, 0.6)
            signals.append(f"poor_quality_{quality}")
            actions.append("Check sleep environment and pre-bed routine")
        elif quality < 70:
            score = max(score, 0.3)
            signals.append(f"fair_quality_{quality}")

    # Elevated resting HR during sleep
    if rhr and rhr > 90:
        score = max(score, 0.4)
        signals.append(f"elevated_resting_hr_{rhr}bpm")

    status = ProactiveStatus.OK if score < 0.3 else ProactiveStatus.CONCERN

    # Build summary
    parts = [f"Last sleep: {total_min // 60}h {total_min % 60}m"]
    if bedtime and wake_time:
        parts.append(f"bedtime {_iso(bedtime)} → wake {_iso(wake_time)}")
    if quality is not None:
        parts.append(f"quality {quality:.0f}/100")
    if rhr:
        parts.append(f"resting HR {rhr} bpm")
    if stages:
        stage_str = ", ".join(f"{s['stage']} {s.get('duration_minutes', 0)}min" for s in stages)
        parts.append(f"stages: {stage_str}")

    return ProactiveSkillResult(
        skill_id=SKILL_ID,
        domain=DOMAIN,
        status=status,
        summary=", ".join(parts),
        score=round(score, 2),
        signals=signals,
        recommended_actions=actions,
        evidence={
            "collections_used": ["sleep_sessions"],
            "record_counts": {"sleep_sessions": 1},
            "latest_timestamps": {"wake_time": _iso(wake_time)},
        },
    )


def _iso(value) -> str | None:
    if isinstance(value, datetime):
        return value.isoformat()
    return value
