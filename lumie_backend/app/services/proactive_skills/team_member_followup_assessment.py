"""Team-member follow-up assessment for proactive advisor."""
import math
from datetime import datetime, timedelta

from ...models.proactive import ProactiveSkillResult, ProactiveStatus

SKILL_ID = "proactive_team_member_followup"
DOMAIN = "team_followup"


async def assess(db, user_id: str, now_utc: datetime) -> ProactiveSkillResult:
    """Assess whether team members (for parent/admin users) need follow-up."""
    admin_memberships = await db.team_members.find(
        {"user_id": user_id, "role": "admin", "status": "member"},
        {"_id": 0, "team_id": 1},
    ).to_list(20)

    if not admin_memberships:
        return ProactiveSkillResult(
            skill_id=SKILL_ID,
            domain=DOMAIN,
            status=ProactiveStatus.MISSING,
            summary="No admin team scope for this user.",
            score=0.0,
            signals=["no_admin_team_scope"],
            evidence={
                "collections_used": ["team_members"],
                "record_counts": {"admin_memberships": 0, "managed_members": 0},
            },
        )

    team_ids = sorted({m.get("team_id") for m in admin_memberships if m.get("team_id")})
    member_docs = await db.team_members.find(
        {
            "team_id": {"$in": team_ids},
            "status": "member",
            "user_id": {"$ne": user_id},
        },
        {"_id": 0, "user_id": 1, "team_id": 1},
    ).to_list(200)

    member_ids = sorted({m.get("user_id") for m in member_docs if m.get("user_id")})
    if not member_ids:
        return ProactiveSkillResult(
            skill_id=SKILL_ID,
            domain=DOMAIN,
            status=ProactiveStatus.MISSING,
            summary="No managed team members found.",
            score=0.0,
            signals=["no_managed_team_members"],
            evidence={
                "collections_used": ["team_members"],
                "record_counts": {
                    "admin_memberships": len(admin_memberships),
                    "managed_members": 0,
                },
            },
        )

    now_str = now_utc.strftime("%Y-%m-%d %H:%M")
    three_days_ago = (now_utc - timedelta(days=3)).strftime("%Y-%m-%d %H:%M")
    sleep_cutoff = now_utc - timedelta(hours=36)

    sleep_docs = await db.sleep_sessions.find(
        {"user_id": {"$in": member_ids}, "wake_time": {"$gte": sleep_cutoff}},
        {"_id": 0, "user_id": 1},
    ).to_list(500)
    recent_sleep_user_ids = {d.get("user_id") for d in sleep_docs if d.get("user_id")}
    no_recent_sleep_count = max(0, len(member_ids) - len(recent_sleep_user_ids))

    overdue_tasks_count = await db.tasks.count_documents(
        {
            "user_id": {"$in": member_ids},
            "done": {"$exists": False},
            "close_datetime": {"$lt": now_str},
            "open_datetime": {"$gte": three_days_ago},
        }
    )

    latest_steps_docs = await db.daily_steps.find(
        {"user_id": {"$in": member_ids}},
        {"_id": 0, "user_id": 1, "date_str": 1, "steps": 1},
    ).sort("date_str", -1).to_list(500)
    latest_steps_by_user: dict[str, int] = {}
    for doc in latest_steps_docs:
        mid = doc.get("user_id")
        if not mid or mid in latest_steps_by_user:
            continue
        latest_steps_by_user[mid] = int(doc.get("steps") or 0)
    low_activity_count = sum(1 for steps in latest_steps_by_user.values() if steps < 2000)

    member_profiles = await db.profiles.find(
        {"user_id": {"$in": member_ids}},
        {"_id": 0, "user_id": 1, "name": 1},
    ).to_list(200)
    name_by_user = {p.get("user_id"): p.get("name") for p in member_profiles if p.get("user_id")}
    managed_member_names = [name_by_user.get(mid) or mid for mid in member_ids[:5]]

    signals: list[str] = []
    actions: list[str] = []
    score = 0.0
    managed_count = len(member_ids)
    concern_majority = math.ceil(managed_count * 0.5)

    if overdue_tasks_count >= 5:
        score = max(score, 0.85)
        signals.append(f"team_severe_overdue_{overdue_tasks_count}_tasks")
        actions.append("Multiple missed medication/task windows across team members")
    elif overdue_tasks_count >= 1:
        score = max(score, 0.55)
        signals.append(f"team_overdue_{overdue_tasks_count}_tasks")
        actions.append("Check in on missed medication/task windows")

    if no_recent_sleep_count >= max(1, concern_majority):
        score = max(score, 0.35)
        signals.append(f"team_no_recent_sleep_{no_recent_sleep_count}_members")
        actions.append("Confirm recent sleep sync and routines for team members")
    elif no_recent_sleep_count > 0:
        signals.append(f"team_partial_no_recent_sleep_{no_recent_sleep_count}_members")

    if low_activity_count >= max(1, concern_majority):
        score = max(score, 0.3)
        signals.append(f"team_low_activity_{low_activity_count}_members")
        actions.append("Encourage movement for lower-activity team members")
    elif low_activity_count > 0:
        signals.append(f"team_partial_low_activity_{low_activity_count}_members")

    status = ProactiveStatus.OK if score < 0.3 else ProactiveStatus.CONCERN
    summary = (
        f"Managed members: {managed_count}; "
        f"overdue tasks: {overdue_tasks_count}; "
        f"no recent sleep(36h): {no_recent_sleep_count}; "
        f"low latest steps(<2000): {low_activity_count}; "
        f"sample members: {', '.join(managed_member_names)}"
    )

    return ProactiveSkillResult(
        skill_id=SKILL_ID,
        domain=DOMAIN,
        status=status,
        summary=summary,
        score=round(score, 2),
        signals=signals,
        recommended_actions=actions,
        evidence={
            "collections_used": ["team_members", "sleep_sessions", "tasks", "daily_steps", "profiles"],
            "record_counts": {
                "admin_memberships": len(admin_memberships),
                "managed_members": managed_count,
                "recent_sleep_docs": len(sleep_docs),
                "overdue_tasks": overdue_tasks_count,
                "latest_steps_docs": len(latest_steps_by_user),
            },
            "managed_member_ids_sample": member_ids[:5],
        },
    )
