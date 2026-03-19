"""Dayprint service — daily action log.

Records:
  - task_completed events (from task route)
  - advisor_chat events (from advisor route, LLM-summarised with topic continuity logic)
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

import anthropic

from ..core.config import settings
from ..core.database import get_database

logger = logging.getLogger(__name__)

_MODEL = "claude-haiku-4-5-20251001"
_client: Optional[anthropic.AsyncAnthropic] = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        _client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


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
            "timestamp": datetime.now(timezone.utc).isoformat(),
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
) -> None:
    """Summarise an advisor exchange and update today's dayprint.

    Claude Haiku decides:
    - A 1-sentence summary of the exchange
    - Whether it continues the same topic as the last advisor_chat entry
      (replace it) or is a new topic (add a new line).
    """
    try:
        db = get_database()
        date = _today_utc_str()
        await _upsert_dayprint(db, user_id, date)

        # Fetch existing advisor_chat entries for context
        doc = await db.dayprints.find_one({"user_id": user_id, "date": date})
        existing_chat_entries = [
            e for e in (doc.get("events") or []) if e.get("type") == "advisor_chat"
        ]

        # Build context of existing summaries
        if existing_chat_entries:
            previous_summaries = "\n".join(
                f"- {e['data'].get('summary', '')}" for e in existing_chat_entries
            )
        else:
            previous_summaries = "(none)"

        name = user_name or "The user"

        prompt = (
            f"You are logging a user's conversation with their AI health advisor.\n\n"
            f"User's name: {name}\n\n"
            f"Previous advisor log entries today (most recent last):\n{previous_summaries}\n\n"
            f"Latest exchange:\n"
            f"User: {user_message[:400]}\n"
            f"Advisor: {reply[:400]}\n\n"
            f"Tasks:\n"
            f"1. Write a 1-sentence 3rd-person log summary of what this exchange is about. "
            f"Use the user's name. Example: \"{name} is seeking advice about muscle building.\"\n"
            f"2. Does this exchange continue the SAME topic as the LAST log entry above? "
            f"If YES → replace_last = true. If NO (new topic, or no previous entries) → replace_last = false.\n\n"
            f"Respond ONLY with valid JSON, no other text:\n"
            f"{{\"summary\": \"...\", \"replace_last\": true}}"
        )

        import json as _json
        client = _get_client()
        response = await client.messages.create(
            model=_MODEL,
            max_tokens=200,
            temperature=0,
            messages=[{"role": "user", "content": prompt}],
        )

        raw = response.content[0].text.strip()
        # Strip markdown fences if present
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

        parsed = _json.loads(raw)
        summary = parsed.get("summary", f"{name} chatted with the advisor.")
        replace_last = bool(parsed.get("replace_last", False))

        new_event = {
            "event_id": str(uuid.uuid4()),
            "type": "advisor_chat",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "data": {"summary": summary},
        }

        if replace_last and existing_chat_entries:
            last_entry = existing_chat_entries[-1]
            last_event_id = last_entry.get("event_id")
            # Remove the last advisor_chat entry by event_id, then push the new one
            await db.dayprints.update_one(
                {"user_id": user_id, "date": date},
                {"$pull": {"events": {"event_id": last_event_id}}},
            )

        await db.dayprints.update_one(
            {"user_id": user_id, "date": date},
            {"$push": {"events": new_event}},
        )
        logger.info(f"Dayprint advisor_chat logged for {user_id} (replace_last={replace_last})")

    except Exception as e:
        logger.warning(f"Dayprint log_advisor_chat failed for {user_id}: {e}")


async def get_dayprint(user_id: str, date: Optional[str] = None) -> Optional[dict]:
    """Get a dayprint document. Defaults to today (UTC date)."""
    db = get_database()
    target_date = date or _today_utc_str()
    doc = await db.dayprints.find_one(
        {"user_id": user_id, "date": target_date},
        {"_id": 0},
    )
    return doc
