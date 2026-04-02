"""Dayprint follow-up assessment for proactive advisor."""
import logging
from datetime import datetime, timedelta

from ...models.proactive import ProactiveSkillResult, ProactiveStatus

logger = logging.getLogger(__name__)

SKILL_ID = "proactive_dayprint_followup"
DOMAIN = "followup"


async def assess(db, user_id: str, now_utc: datetime) -> ProactiveSkillResult:
    """Assess recent dayprints for follow-up opportunities."""
    since_date = (now_utc - timedelta(days=5)).strftime("%Y-%m-%d")
    docs = await db.dayprints.find(
        {"user_id": user_id, "date": {"$gte": since_date}},
        {"_id": 0, "date": 1, "events": 1},
    ).sort("date", -1).to_list(5)

    if not docs:
        return ProactiveSkillResult(
            skill_id=SKILL_ID,
            domain=DOMAIN,
            status=ProactiveStatus.MISSING,
            summary="No recent dayprint memory.",
            score=0.0,
            signals=["no_recent_dayprints"],
            evidence={
                "collections_used": ["dayprints"],
                "record_counts": {"dayprints": 0},
            },
        )

    signals: list[str] = []
    actions: list[str] = []
    score = 0.0
    summary_lines: list[str] = []
    followup_candidates: list[str] = []

    for doc in docs:
        date = doc.get("date", "unknown")
        events = doc.get("events") or []
        important = [e for e in events if e.get("type") == "important_insight"]
        chats = [e for e in events if e.get("type") == "advisor_chat"]
        completed = [e for e in events if e.get("type") == "task_completed"]

        day_items: list[str] = []

        for event in important[-3:]:
            data = event.get("data") or {}
            summary = data.get("summary")
            category = data.get("category", "other")
            if summary:
                day_items.append(f"insight [{category}]: {summary}")
                # Health-related insights are stronger follow-up candidates
                if category in ("health", "medication", "sleep", "activity", "mood"):
                    score = max(score, 0.4)
                    followup_candidates.append(summary)
                    signals.append(f"health_insight_{date}")
                else:
                    score = max(score, 0.2)
                    signals.append(f"insight_{date}")

        for event in chats[-3:]:
            data = event.get("data") or {}
            summary = data.get("summary")
            if summary:
                day_items.append(f"chat: {summary}")
                # Recent advisor chats may warrant follow-up
                score = max(score, 0.3)
                followup_candidates.append(summary)
                signals.append(f"advisor_chat_{date}")

        if completed:
            names = []
            for event in completed[-3:]:
                task_name = (event.get("data") or {}).get("task_name")
                if task_name:
                    names.append(task_name)
            if names:
                day_items.append(f"completed: {', '.join(names)}")

        if day_items:
            summary_lines.append(f"{date}: " + "; ".join(day_items))

    if followup_candidates:
        actions.append("Follow up on: " + followup_candidates[0])

    status = ProactiveStatus.OK if score < 0.3 else ProactiveStatus.CONCERN

    return ProactiveSkillResult(
        skill_id=SKILL_ID,
        domain=DOMAIN,
        status=status,
        summary=" | ".join(summary_lines[:3]) if summary_lines else "Dayprints present but no strong follow-up candidate.",
        score=round(score, 2),
        signals=signals,
        recommended_actions=actions,
        evidence={
            "collections_used": ["dayprints"],
            "record_counts": {"dayprints": len(docs)},
            "followup_candidates": followup_candidates[:3],
        },
    )
