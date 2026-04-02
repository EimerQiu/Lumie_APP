"""Activity domain assessment for proactive advisor."""
import logging
from datetime import datetime, timedelta

from ...models.proactive import ProactiveSkillResult, ProactiveStatus

logger = logging.getLogger(__name__)

SKILL_ID = "proactive_activity_assessment"
DOMAIN = "activity"


async def assess(db, user_id: str, now_utc: datetime) -> ProactiveSkillResult:
    """Assess recent activity and step data."""
    three_days_ago_iso = (now_utc - timedelta(days=3)).isoformat()
    step_cutoff = (now_utc - timedelta(days=3)).strftime("%Y-%m-%d")

    activities = await db.activities.find({
        "user_id": user_id,
        "start_time": {"$gte": three_days_ago_iso},
    }).sort("start_time", -1).to_list(10)

    daily_steps = await db.daily_steps.find({
        "user_id": user_id,
        "date_str": {"$gte": step_cutoff},
    }).sort("date_str", -1).to_list(4)

    has_activities = bool(activities)
    has_steps = bool(daily_steps)

    if not has_activities and not has_steps:
        return ProactiveSkillResult(
            skill_id=SKILL_ID,
            domain=DOMAIN,
            status=ProactiveStatus.MISSING,
            summary="No activity or step data in the last 3 days.",
            score=0.0,
            signals=["no_recent_activity_data", "no_recent_step_data"],
            evidence={
                "collections_used": ["activities", "daily_steps"],
                "record_counts": {"activities": 0, "daily_steps": 0},
            },
        )

    signals: list[str] = []
    actions: list[str] = []
    score = 0.0

    # Activity analysis
    if not has_activities:
        # No logged activities but check if steps show movement
        if has_steps and daily_steps[0].get("steps", 0) > 500:
            signals.append("no_logged_activities_but_steps_present")
            score = max(score, 0.1)
        else:
            signals.append("no_activity_3_days")
            score = max(score, 0.5)
            actions.append("Consider a short walk or light exercise")
    else:
        activity_count = len(activities)
        signals.append(f"activities_last_3d_{activity_count}")
        # Check for recent inactivity: last activity > 48h ago
        latest_start = activities[0].get("start_time")
        if latest_start:
            try:
                latest_dt = datetime.fromisoformat(str(latest_start))
                if latest_dt.tzinfo is None:
                    from datetime import timezone
                    latest_dt = latest_dt.replace(tzinfo=timezone.utc)
                hours_since = (now_utc - latest_dt).total_seconds() / 3600
                if hours_since > 48:
                    score = max(score, 0.35)
                    signals.append(f"last_activity_{hours_since:.0f}h_ago")
            except (ValueError, TypeError):
                pass

    # Step analysis
    if has_steps:
        latest_steps = daily_steps[0].get("steps", 0)
        latest_date = daily_steps[0].get("date_str", "?")
        signals.append(f"latest_steps_{latest_steps}_on_{latest_date}")
        if latest_steps < 1000:
            score = max(score, 0.3)
            signals.append("very_low_steps")
        elif latest_steps < 3000:
            score = max(score, 0.15)
            signals.append("low_steps")

    status = ProactiveStatus.OK if score < 0.3 else ProactiveStatus.CONCERN

    # Build summary
    parts: list[str] = []
    if has_activities:
        parts.append(f"{len(activities)} activities in last 3 days")
        a = activities[0]
        parts.append(
            f"latest: {a.get('activity_type_name', 'activity')} "
            f"{a.get('duration_minutes', 0)}min, "
            f"intensity {a.get('intensity', '?')}"
        )
    else:
        parts.append("No logged activities in last 3 days")
    if has_steps:
        d = daily_steps[0]
        parts.append(f"latest steps: {d.get('steps', 0)} on {d.get('date_str', '?')}")

    return ProactiveSkillResult(
        skill_id=SKILL_ID,
        domain=DOMAIN,
        status=status,
        summary="; ".join(parts),
        score=round(score, 2),
        signals=signals,
        recommended_actions=actions,
        evidence={
            "collections_used": ["activities", "daily_steps"],
            "record_counts": {"activities": len(activities), "daily_steps": len(daily_steps)},
            "latest_timestamps": {
                "activity_start": activities[0].get("start_time") if activities else None,
                "step_date": daily_steps[0].get("date_str") if daily_steps else None,
            },
        },
    )
