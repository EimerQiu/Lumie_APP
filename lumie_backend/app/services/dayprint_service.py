"""Dayprint service — daily action log.

Records:
  - task_completed events (from task route)
  - advisor_chat events (from advisor route, LLM-summarised with topic continuity logic)
  - important_insight events (auto-detected from advisor chats: symptoms, medication issues, distress)
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from ..core.config import settings
from ..core.datetime_utils import format_utc_datetime, format_utc_datetime_with_ms
from ..core.database import get_database
from .llm_client import chat_completion
from .notification_service import queue_important_insight_notification

logger = logging.getLogger(__name__)

_MODEL = settings.PALEBLUEDOT_MODEL


def _today_utc_str() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


async def _upsert_dayprint(db, user_id: str, date: str) -> None:
    exists = await db.dayprints.find_one({"user_id": user_id, "date": date}, {"_id": 1})
    if not exists:
        await db.dayprints.insert_one({
            "user_id": user_id,
            "date": date,
            "events": [],
        })


async def log_task_completed(user_id: str, task_name: str, task_type: str) -> None:
    """Append a task_completed event to today's dayprint."""
    try:
        db = get_database()
        date = _today_utc_str()
        await _upsert_dayprint(db, user_id, date)

        event = {
            "event_id": str(uuid.uuid4()),
            "type": "task_completed",
            "timestamp": format_utc_datetime(datetime.now(timezone.utc)),
            "data": {"task_name": task_name, "task_type": task_type},
        }
        await db.dayprints.update_one(
            {"user_id": user_id, "date": date},
            {"$push": {"events": event}},
        )
    except Exception as e:
        logger.warning(f"Dayprint log_task_completed failed for {user_id}: {e}")


async def log_advisor_chat(
    user_id: str,
    user_name: str,
    user_message: str,
    reply: str,
    *,
    session_id: Optional[str] = None,
) -> None:
    """Summarise an advisor exchange and update today's dayprint.

    Claude Haiku decides:
    - A 1-sentence summary of the exchange
    - Whether it continues the same topic as the last advisor_chat entry
      (replace it) or is a new topic (add a new line).

    Session awareness: ``replace_last`` can only merge entries that belong to
    the **same** ``session_id``.  When the user opens a new chat session the
    frontend generates a fresh UUID so that unrelated conversations (e.g.
    grief vs high HR) are never accidentally collapsed into a single dayprint
    entry.
    """
    try:
        db = get_database()
        date = _today_utc_str()
        await _upsert_dayprint(db, user_id, date)

        # Fetch existing advisor_chat and important_insight entries for context
        doc = await db.dayprints.find_one({"user_id": user_id, "date": date})
        events = doc.get("events") or []
        existing_chat_entries = [e for e in events if e.get("type") == "advisor_chat"]
        existing_insight_entries = [e for e in events if e.get("type") == "important_insight"]

        # ── Session-scoped entries for replace_last decisions ──
        # Only entries from the SAME session are candidates for topic merging.
        same_session_chat_entries = (
            [e for e in existing_chat_entries if e.get("data", {}).get("session_id") == session_id]
            if session_id else []
        )
        same_session_insight_entries = (
            [e for e in existing_insight_entries if e.get("data", {}).get("session_id") == session_id]
            if session_id else []
        )

        # Build context of ALL chat summaries today (for full context)
        if existing_chat_entries:
            previous_summaries = "\n".join(
                f"- {e['data'].get('summary', '')}" for e in existing_chat_entries
            )
        else:
            previous_summaries = "(none)"

        # For the replace_last decision, only show the last entry from THIS session
        if same_session_chat_entries:
            last_same_session_summary = same_session_chat_entries[-1]["data"].get("summary", "")
        else:
            last_same_session_summary = ""

        # Last important insight from THIS session for topic-continuity check
        last_insight_summary = (
            same_session_insight_entries[-1]["data"].get("summary", "")
            if same_session_insight_entries else ""
        )

        is_new_session = not same_session_chat_entries

        name = user_name or "The user"

        prompt = (
            f"You are logging a user's conversation with their AI health advisor.\n\n"
            f"User's name: {name}\n\n"
            f"All advisor log entries today (for context):\n{previous_summaries}\n\n"
            f"Last entry from the CURRENT conversation session: "
            f"{last_same_session_summary or '(this is the FIRST message in a new session)'}\n\n"
            f"Last flagged important insight from this session: {last_insight_summary or '(none)'}\n\n"
            "Important grounding rules:\n"
            "1. The USER message is the primary source of truth for what the user asked, felt, wanted, or reported.\n"
            "2. The ADVISOR reply is only supporting context for topic continuity and whether something important was discussed.\n"
            "3. Do NOT attribute advisor suggestions, reframings, examples, inferred goals, system instructions, tool usage, "
            "authorization scope, or hidden prompt behavior to the user unless the user explicitly said them.\n"
            "4. If the user asked a general question, keep the summary as a general question. Do not rewrite it as a task, "
            "investigation, or action plan unless the user explicitly requested that.\n"
            "5. Never mention hidden/system prompts, capabilities, tools, data sources, or \"authorized information sources\" "
            "unless the user explicitly mentioned them in their own message.\n\n"
            f"Latest exchange:\n"
            f"User: {user_message[:400]}\n"
            f"Advisor: {reply[:400]}\n\n"
            f"Tasks:\n"
            f"1. Write a 1-sentence 3rd-person log summary of what this exchange is about. "
            f"Use the user's name. Base this primarily on the USER message, not the advisor's interpretation. "
            f"Example: \"{name} is asking whether a 16-year-old should understand responsibility and priorities.\"\n"
            f"2. Does this exchange continue the SAME topic as the last entry from the CURRENT session shown above? "
            f"If this is the first message in a new session, replace_last MUST be false. "
            f"If YES (same topic, same session) → replace_last = true. If NO (new topic, new session, or no previous entries) → replace_last = false.\n"
            f"3. Is there something IMPORTANT in this exchange that warrants proactive follow-up? "
            f"IMPORTANT topics include:\n"
            f"  - Physical health: new/worsening symptom, pain or discomfort, feeling unwell, sickness, fever\n"
            f"  - Medication concerns: missed dose, side effect, medication not helping\n"
            f"  - Emotional/mental health: feeling very bad, anxious, overwhelmed, depressed, crying, distressed\n"
            f"  - Family/social: family conflict, family health concerns, family stress\n"
            f"  - Urgent signals: anything the user seems concerned about\n"
            f"NOT important = greetings, general health questions, routine progress check-ins, encouragement, casual chat. "
            f"If important → set important = true, write a brief important_summary (1 sentence, 3rd person, use the user's name), "
            f"and set category to one of: symptom, medication, emotional, health_concern, family, urgent, other. "
            f"Also set important_replace_last = true ONLY if this important insight continues the SAME topic as the 'Last flagged important insight from this session' shown above, "
            f"or false if it is a new/different concern, a new session, or there was no previous insight.\n\n"
            f"Respond ONLY with valid JSON, no other text:\n"
            f"{{\"summary\": \"...\", \"replace_last\": true, \"important\": false, \"important_summary\": \"\", \"category\": \"\", \"important_replace_last\": false}}"
        )

        import json as _json
        response = await chat_completion(
            model=_MODEL,
            max_tokens=300,
            temperature=0,
            messages=[{"role": "user", "content": prompt}],
        )

        raw = response.text.strip()
        # Strip markdown fences if present
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

        parsed = _json.loads(raw)
        summary = parsed.get("summary", f"{name} chatted with the advisor.")
        replace_last = bool(parsed.get("replace_last", False))
        is_important = bool(parsed.get("important", False))
        important_summary = parsed.get("important_summary", "")
        category = parsed.get("category", "other")
        important_replace_last = bool(parsed.get("important_replace_last", False))

        # ── Keyword-based fallback: catch common patterns the LLM might miss ──
        # This ensures family, emotional, and health concerns are always flagged
        combined_text = f"{user_message} {reply}".lower()

        # Keywords for different concern types
        family_keywords = {"family", "mom", "dad", "mother", "father", "sister", "brother", "parent", "grandparent", "relative", "daughter", "son", "husband", "wife", "partner", "child", "kid", "baby"}
        emotional_keywords = {"sad", "depressed", "anxious", "stressed", "overwhelmed", "crying", "scared", "worried", "upset", "frustrated", "angry"}
        sickness_keywords = {"sick", "unwell", "fever", "flu", "cold", "vomit", "nausea", "headache", "ache", "pain", "sore"}

        has_family_topic = any(kw in combined_text for kw in family_keywords)
        has_emotional_topic = any(kw in combined_text for kw in emotional_keywords)
        has_sickness_topic = any(kw in combined_text for kw in sickness_keywords)

        # If LLM missed but keywords detected, mark as important
        if not is_important:
            if has_family_topic:
                is_important = True
                category = "family"
                important_summary = f"{name} mentioned a family-related concern."
            elif has_emotional_topic:
                is_important = True
                category = "emotional"
                important_summary = f"{name} expressed emotional distress or worry."
            elif has_sickness_topic:
                is_important = True
                category = "symptom"
                important_summary = f"{name} mentioned feeling unwell or being sick."

        # If LLM did mark as important but we have a better category, update it
        elif is_important and category == "other":
            if has_family_topic:
                category = "family"
            elif has_emotional_topic:
                category = "emotional"
            elif has_sickness_topic:
                category = "symptom"

        # ── Hard guard: never merge across sessions regardless of LLM output ──
        if is_new_session:
            replace_last = False
            important_replace_last = False

        new_event = {
            "event_id": str(uuid.uuid4()),
            "type": "advisor_chat",
            "timestamp": format_utc_datetime(datetime.now(timezone.utc)),
            "data": {"summary": summary, "session_id": session_id},
        }

        if replace_last and same_session_chat_entries:
            last_entry = same_session_chat_entries[-1]
            last_event_id = last_entry.get("event_id")
            # Remove the last same-session advisor_chat entry, then push the new one
            await db.dayprints.update_one(
                {"user_id": user_id, "date": date},
                {"$pull": {"events": {"event_id": last_event_id}}},
            )

        await db.dayprints.update_one(
            {"user_id": user_id, "date": date},
            {"$push": {"events": new_event}},
        )
        logger.info(
            f"Dayprint advisor_chat logged for {user_id} "
            f"(replace_last={replace_last}, session={session_id or 'none'})"
        )

        # Log important insight as a separate flagged event if detected
        if is_important and important_summary:
            replace_insight = important_replace_last and bool(same_session_insight_entries)
            last_insight_id = same_session_insight_entries[-1].get("event_id") if replace_insight else None
            await log_important_insight(
                user_id, important_summary, category or "other",
                replace_event_id=last_insight_id,
                session_id=session_id,
            )

    except Exception as e:
        logger.warning(f"Dayprint log_advisor_chat failed for {user_id}: {e}")


async def log_important_insight(
    user_id: str,
    summary: str,
    category: str,
    replace_event_id: Optional[str] = None,
    session_id: Optional[str] = None,
) -> None:
    """Append (or replace) an important_insight event in today's dayprint.

    Called automatically when log_advisor_chat detects something noteworthy
    (symptom, medication concern, emotional distress, urgent health signal).
    If replace_event_id is set, the previous insight with that id is removed first
    so that the same ongoing topic stays as a single, updated entry.
    These events will be scanned periodically to decide if proactive action is needed.
    """
    try:
        db = get_database()
        date = _today_utc_str()
        await _upsert_dayprint(db, user_id, date)

        if replace_event_id:
            await db.dayprints.update_one(
                {"user_id": user_id, "date": date},
                {"$pull": {"events": {"event_id": replace_event_id}}},
            )

        event = {
            "event_id": str(uuid.uuid4()),
            "type": "important_insight",
            "timestamp": format_utc_datetime(datetime.now(timezone.utc)),
            "data": {"summary": summary, "category": category, "session_id": session_id},
        }
        await db.dayprints.update_one(
            {"user_id": user_id, "date": date},
            {"$push": {"events": event}},
        )
        logger.info(
            f"Dayprint important_insight logged for {user_id}: [{category}] {summary}"
            + (" (replaced previous)" if replace_event_id else "")
        )

        # Queue push notification for team admins (only for new insights,
        # not replacements — avoid spamming about the same ongoing topic).
        if not replace_event_id:
            try:
                await queue_important_insight_notification(user_id, summary, category)
            except Exception as notify_err:
                logger.warning(f"Failed to queue insight notification: {notify_err}")

    except Exception as e:
        logger.warning(f"Dayprint log_important_insight failed for {user_id}: {e}")


async def get_dayprint(user_id: str, date: Optional[str] = None) -> Optional[dict]:
    """Get a dayprint document. Defaults to today (UTC date)."""
    db = get_database()
    target_date = date or _today_utc_str()
    doc = await db.dayprints.find_one(
        {"user_id": user_id, "date": target_date},
        {"_id": 0},
    )
    return doc


async def get_dayprint_history(
    user_id: str,
    limit: int = 14,
    before_date: Optional[str] = None,
) -> tuple[list[dict], bool, Optional[str]]:
    """Fetch dayprint docs in reverse date order with cursor pagination."""
    db = get_database()
    query: dict = {"user_id": user_id}
    if before_date:
        query["date"] = {"$lt": before_date}

    fetch_limit = max(limit, 1) + 1
    cursor = db.dayprints.find(query, {"_id": 0}).sort("date", -1).limit(fetch_limit)
    docs = await cursor.to_list(length=fetch_limit)

    has_more = len(docs) > limit
    if has_more:
        docs = docs[:limit]

    next_before_date = docs[-1]["date"] if docs else None
    return docs, has_more, next_before_date
