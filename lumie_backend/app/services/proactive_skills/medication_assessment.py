"""Medication / task adherence assessment for proactive advisor."""
import logging
from datetime import datetime, timedelta

from ...models.proactive import ProactiveSkillResult, ProactiveStatus

logger = logging.getLogger(__name__)

SKILL_ID = "proactive_medication_assessment"
DOMAIN = "medication"


async def assess(db, user_id: str, now_utc: datetime) -> ProactiveSkillResult:
    """Assess medication task adherence."""
    now_str = now_utc.strftime("%Y-%m-%d %H:%M")
    three_days_ago = (now_utc - timedelta(days=3)).strftime("%Y-%m-%d %H:%M")
    two_hours_ahead = (now_utc + timedelta(hours=2)).strftime("%Y-%m-%d %H:%M")

    overdue = await db.tasks.find({
        "user_id": user_id,
        "done": {"$exists": False},
        "close_datetime": {"$lt": now_str},
        "open_datetime": {"$gte": three_days_ago},
    }).to_list(20)

    active = await db.tasks.find({
        "user_id": user_id,
        "done": {"$exists": False},
        "open_datetime": {"$lte": now_str},
        "close_datetime": {"$gte": now_str},
    }).to_list(10)

    upcoming = await db.tasks.find({
        "user_id": user_id,
        "done": {"$exists": False},
        "open_datetime": {"$gt": now_str, "$lte": two_hours_ahead},
    }).to_list(10)

    total = len(overdue) + len(active) + len(upcoming)
    if total == 0:
        return ProactiveSkillResult(
            skill_id=SKILL_ID,
            domain=DOMAIN,
            status=ProactiveStatus.MISSING,
            summary="No medication tasks in the recent window.",
            score=0.0,
            signals=["no_recent_tasks"],
            evidence={
                "collections_used": ["tasks"],
                "record_counts": {"overdue": 0, "active": 0, "upcoming": 0},
            },
        )

    signals: list[str] = []
    actions: list[str] = []
    score = 0.0

    # Overdue scoring — most important
    if len(overdue) >= 3:
        score = max(score, 0.85)
        signals.append(f"severe_overdue_{len(overdue)}_tasks")
        actions.append("Multiple missed medication windows — check in with user")
    elif len(overdue) >= 1:
        score = max(score, 0.55)
        signals.append(f"overdue_{len(overdue)}_tasks")
        actions.append("Remind about missed medication window")

    # Active window
    if active:
        signals.append(f"active_window_{len(active)}_tasks")
        # If there are active tasks, a gentle reminder might help
        if not overdue:
            score = max(score, 0.25)
            actions.append("Current medication window is open")

    # Upcoming
    if upcoming:
        signals.append(f"upcoming_{len(upcoming)}_tasks_within_2h")

    status = ProactiveStatus.OK if score < 0.3 else ProactiveStatus.CONCERN

    # Build summary
    def _task_name(t: dict) -> str:
        name = t.get("task_name", "Task")
        if " - " in name:
            name = name.split(" - ", 1)[1]
        return f"{name} [{t.get('task_type', '')}] {t.get('open_datetime', '')}–{t.get('close_datetime', '')}"

    parts: list[str] = []
    if overdue:
        parts.append(f"{len(overdue)} overdue: " + ", ".join(_task_name(t) for t in overdue[:3]))
    if active:
        parts.append(f"{len(active)} active now: " + ", ".join(_task_name(t) for t in active[:2]))
    if upcoming:
        parts.append(f"{len(upcoming)} upcoming within 2h")

    return ProactiveSkillResult(
        skill_id=SKILL_ID,
        domain=DOMAIN,
        status=status,
        summary="; ".join(parts),
        score=round(score, 2),
        signals=signals,
        recommended_actions=actions,
        evidence={
            "collections_used": ["tasks"],
            "record_counts": {"overdue": len(overdue), "active": len(active), "upcoming": len(upcoming)},
        },
    )
