"""Proactive Advisor Service — skill-driven design.

Instead of hardcoding what data means, this service:
  1. Loads the full .md guidance for every enabled skill.
  2. Fetches raw data from MongoDB (structural, per capability).
  3. Passes skill guidance + raw data + last-nudge context to Claude Haiku.
  4. Haiku decides whether to nudge using the skill files as its knowledge base.

Updating a skill .md automatically changes how the advisor interprets data —
no changes to this service needed.

Capability → collections mapping (structural, rarely changes):
  lumie_internal_data → tasks, sleep_sessions, activities
  email_read / browser_portal_access / web_read → noted in prompt, data not
  fetched here (requires execution infrastructure).
"""

import json
import logging
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import anthropic

from ..core.config import settings
from ..core.database import get_database
from ..services.capability_service import get_user_enabled_capability_ids
from ..services.skill_registry_service import skill_registry
from ..services.notification_service import queue_checkin_notification
from ..services.chat_history_service import save_message

logger = logging.getLogger(__name__)

_HAIKU_MODEL = "claude-haiku-4-5-20251001"

# Capabilities whose data we can fetch directly from MongoDB
_INTERNAL_CAP_ID = "lumie_internal_data"

# Capabilities that require execution infrastructure — we note them in the prompt
# so Haiku is aware, but we don't fetch data for them in proactive runs.
_EXECUTION_CAPS = {
    "email_read": "Email (enabled, data not available in proactive mode)",
    "browser_portal_access": "Web portal (enabled, data not available in proactive mode)",
    "web_read": "Web read (enabled, data not available in proactive mode)",
}


# ── Raw data fetchers (structural, no interpretation embedded) ────────────────

async def _fetch_lumie_internal_data(db, user_id: str, now_utc: datetime, now_str: str) -> str:
    """Fetch raw tasks, sleep, and activity data. Returns a text block."""
    lines: list[str] = []

    # Tasks: overdue (last 3 days), currently active, upcoming (next 2 hours)
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

    def _task_str(t: dict) -> str:
        name = t.get("task_name", "Task")
        if " - " in name:
            name = name.split(" - ", 1)[1]
        return f"{name} [{t.get('task_type', '')}] window {t.get('open_datetime', '')}–{t.get('close_datetime', '')}"

    if overdue:
        lines.append("Overdue tasks (last 3 days):")
        lines.extend(f"  - {_task_str(t)}" for t in overdue)
    else:
        lines.append("No overdue tasks in the last 3 days.")

    if active:
        lines.append("Currently active tasks:")
        lines.extend(f"  - {_task_str(t)}" for t in active)
    else:
        lines.append("No tasks currently active.")

    if upcoming:
        lines.append("Upcoming tasks (next 2 hours):")
        lines.extend(f"  - {_task_str(t)}" for t in upcoming)

    # Sleep: most recent session
    yesterday_utc = now_utc - timedelta(days=1)
    sleep = await db.sleep_sessions.find_one(
        {"user_id": user_id, "bedtime": {"$gte": yesterday_utc}},
        sort=[("bedtime", -1)],
    )
    if sleep:
        mins = sleep.get("total_sleep_minutes") or 0
        score = sleep.get("sleep_quality_score")
        rhr = sleep.get("resting_heart_rate")
        parts = [f"Last sleep: {mins // 60}h {mins % 60}m"]
        if score is not None:
            parts.append(f"quality {score:.0f}/100")
        if rhr:
            parts.append(f"resting HR {rhr} bpm")
        stages = sleep.get("stages") or []
        if stages:
            stage_str = ", ".join(
                f"{s['stage']} {s.get('duration_minutes', 0)}min"
                for s in stages
            )
            parts.append(f"stages: {stage_str}")
        lines.append(", ".join(parts))
    else:
        lines.append("No sleep data in the last 24 hours.")

    # Activities: last 3 days
    three_days_ago_iso = (now_utc - timedelta(days=3)).isoformat()
    activities = await db.activities.find({
        "user_id": user_id,
        "start_time": {"$gte": three_days_ago_iso},
    }).sort("start_time", -1).to_list(10)

    if activities:
        lines.append(f"Activities in the last 3 days ({len(activities)} records):")
        for a in activities[:5]:
            lines.append(
                f"  - {a.get('activity_type_name', 'activity')} "
                f"{a.get('duration_minutes', 0)}min, "
                f"intensity {a.get('intensity', '?')}, "
                f"avg HR {a.get('avg_heart_rate', '?')} bpm"
            )
    else:
        lines.append("No activity recorded in the last 3 days.")

    return "\n".join(lines)


# ── Main entry point ──────────────────────────────────────────────────────────

async def run_proactive_check(user_id: str) -> dict:
    """Run a proactive advisor check for a single user.

    Returns::

        {
            "nudged": bool,
            "message": str | None,
            "reason": str,
        }
    """
    db = get_database()

    # ── 1. User profile ──────────────────────────────────────────────────────
    profile = await db.profiles.find_one({"user_id": user_id}, {"_id": 0})
    if not profile:
        return {"nudged": False, "message": None, "reason": "no_profile"}

    user_name = profile.get("name", "the user")
    user_timezone = profile.get("timezone", "UTC")
    icd10 = profile.get("icd10_code", "")
    role = profile.get("role", "teen")

    try:
        local_tz = ZoneInfo(user_timezone)
    except Exception:
        local_tz = ZoneInfo("UTC")

    now_utc = datetime.now(timezone.utc)
    now_local = datetime.now(local_tz)
    now_str = now_utc.strftime("%Y-%m-%d %H:%M")

    # ── 2. Enabled capabilities + skill texts ────────────────────────────────
    enabled_cap_ids = await get_user_enabled_capability_ids(user_id)
    if not enabled_cap_ids:
        logger.info("Proactive[%s]: no enabled capabilities — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_enabled_capabilities"}

    logger.info("Proactive[%s]: enabled capabilities: %s", user_id, sorted(enabled_cap_ids))

    skill_text_blocks: list[str] = []
    loaded_skill_ids: list[str] = []
    for cap_id in enabled_cap_ids:
        for skill in skill_registry.get_skills_by_capability(cap_id):
            full_text = skill_registry.load_skill_full_text(skill.skill_id)
            if full_text:
                skill_text_blocks.append(
                    f"=== SKILL: {skill.title} ===\n{full_text}\n=== END SKILL ==="
                )
                loaded_skill_ids.append(skill.skill_id)

    if not skill_text_blocks:
        logger.warning("Proactive[%s]: no skill guidance loaded — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_skill_guidance"}

    logger.info("Proactive[%s]: loaded %d skills: %s", user_id, len(loaded_skill_ids), loaded_skill_ids)

    # ── 3. Fetch raw data per capability ─────────────────────────────────────
    data_blocks: list[str] = []

    if _INTERNAL_CAP_ID in enabled_cap_ids:
        logger.info("Proactive[%s]: fetching lumie_internal_data", user_id)
        internal_data = await _fetch_lumie_internal_data(db, user_id, now_utc, now_str)
        data_blocks.append(f"[Lumie Internal Data]\n{internal_data}")
        logger.info("Proactive[%s]: internal data fetched (%d chars)", user_id, len(internal_data))

    # Note execution-only capabilities so Haiku is aware
    for cap_id, label in _EXECUTION_CAPS.items():
        if cap_id in enabled_cap_ids:
            data_blocks.append(f"[{label}]")

    if not data_blocks:
        logger.warning("Proactive[%s]: no data available — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_data_available"}

    # ── 4. Last nudge context ────────────────────────────────────────────────
    checkin_doc = await db.advisor_checkins.find_one({"user_id": user_id})
    last_nudge = (checkin_doc or {}).get("last_nudge")
    if last_nudge:
        nudged_at_raw = last_nudge.get("nudged_at", "")
        try:
            nudged_at_dt = datetime.fromisoformat(nudged_at_raw)
            if nudged_at_dt.tzinfo is None:
                nudged_at_dt = nudged_at_dt.replace(tzinfo=timezone.utc)
            minutes_ago = int((now_utc - nudged_at_dt).total_seconds() / 60)
            last_nudge_str = (
                f"Last nudge sent {minutes_ago} minutes ago. "
                f"Reason: \"{last_nudge.get('reason', '')}\". "
                "Only nudge again for the same concern if the situation has materially changed."
            )
        except Exception:
            last_nudge_str = ""
    else:
        last_nudge_str = "No nudge has been sent yet."

    # ── 5. Build prompt ───────────────────────────────────────────────────────
    skills_block = "\n\n".join(skill_text_blocks)
    data_block = "\n\n".join(data_blocks)
    local_time_str = now_local.strftime("%A, %B %d, %I:%M %p")
    condition_str = f" with condition code {icd10}" if icd10 else ""

    system_prompt = (
        f"You are a proactive health advisor for {user_name}, a {role}{condition_str}.\n"
        f"Current local time: {local_time_str}.\n\n"
        "You are in PROACTIVE MODE. You are autonomously reviewing the user's data to decide "
        "whether to send a nudge notification right now. You are NOT executing queries or "
        "responding to a user message.\n\n"
        "The following are your active skill guidelines. Use them to understand and interpret "
        "the user's data — particularly the 'When To Use', 'Output Guidance', and domain "
        "knowledge sections:\n\n"
        f"{skills_block}\n\n"
        "Based on these skill guidelines and the user's current data, decide whether to send "
        "a nudge. Only nudge if there is something genuinely worth addressing right now. "
        "Avoid nudging for minor, speculative, or future concerns.\n\n"
        f"Nudge history: {last_nudge_str}\n\n"
        "Respond with valid JSON only — no markdown, no explanation:\n"
        '{"should_nudge": true|false, "message": "<friendly nudge message ≤120 chars, or null>", '
        '"reason": "<brief internal reason, e.g. overdue_medication / no_activity_3_days / fine>"}'
    )

    user_message = (
        f"Here is {user_name}'s current data:\n\n{data_block}\n\nShould I reach out?"
    )

    logger.info(
        "Proactive[%s]: calling Haiku (last_nudge=%s)",
        user_id,
        last_nudge_str.split(".")[0] if last_nudge_str else "none",
    )

    # ── 6. Call Claude Haiku ─────────────────────────────────────────────────
    try:
        client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)
        response = client.messages.create(
            model=_HAIKU_MODEL,
            max_tokens=200,
            temperature=0,
            system=system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )
        raw = response.content[0].text.strip()
        if raw.startswith("```"):
            raw_lines = raw.split("\n")
            raw = "\n".join(raw_lines[1:-1]) if len(raw_lines) > 2 else raw
        result = json.loads(raw)
    except Exception as e:
        logger.error(f"Proactive Haiku call failed for user={user_id}: {e}")
        return {"nudged": False, "message": None, "reason": f"llm_error: {e}"}

    should_nudge: bool = bool(result.get("should_nudge", False))
    message: str | None = result.get("message") or None
    reason: str = result.get("reason", "")

    # ── 7. Save message to chat history + queue notification ─────────────────
    if should_nudge and message:
        # Save advisor message first — this is the source of truth the user sees
        # when they open the Advisor tab. The push notification is just delivery.
        await save_message(
            user_id=user_id,
            session_id="proactive",
            role="assistant",
            content=message,
            metadata={"type": "proactive", "reason": reason},
        )
        logger.info("Proactive[%s]: message saved to chat history (session=proactive)", user_id)

        # Push notification — only needed when app is in background
        await queue_checkin_notification(user_id, message)

        await db.advisor_checkins.update_one(
            {"user_id": user_id},
            {"$set": {"last_nudge": {"reason": reason, "nudged_at": now_utc.isoformat()}}},
        )
        logger.info("Proactive nudge queued for user=%s: %s", user_id, reason)
    else:
        logger.info("Proactive: no nudge for user=%s: %s", user_id, reason)

    return {"nudged": should_nudge, "message": message, "reason": reason}
