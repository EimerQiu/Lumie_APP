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
    await db.dayprints.update_one(
        {"user_id": user_id, "date": date},
        {"$setOnInsert": {
            "user_id": user_id,
            "date": date,
            "events": [],
        }},
        upsert=True,
    )


_NUTRITION_TASK_TYPES = {"Nutrition", "nutrition"}


def canonical_event_source_key(
    *,
    user_id: str,
    event_type: Optional[str],
    source_task_id: Optional[str],
    task_type: Optional[str] = None,
    source_type: Optional[str] = None,
    meal_id: Optional[str] = None,
) -> Optional[str]:
    """Single stable identity per logical occurrence in a user's day.

    Every event tied to a Nutrition task — meal_logged from the bridge,
    task_completed from the route, even legacy events written before this
    scheme — collapses to one key:

        nutrition_task:<user_id>:<source_task_id>

    so the dayprint dedupe pass treats them as the same row no matter how
    many code paths fired. Manual meals key on `meal:<meal_id>`. Non-
    nutrition task_completed events use a separate `task:<user>:<task>` key
    so they keep their own slot in the timeline.
    """
    is_nutrition = (
        (source_type or "").startswith("nutrition_task")
        or (task_type in _NUTRITION_TASK_TYPES if task_type else False)
    )
    if source_task_id and (is_nutrition or event_type == "meal_logged"):
        return f"nutrition_task:{user_id}:{source_task_id}"
    if event_type == "meal_logged" and meal_id:
        return f"meal:{meal_id}"
    if event_type == "task_completed" and source_task_id:
        return f"task:{user_id}:{source_task_id}"
    return None


def _dayprint_event_source_key(event: dict, *, user_id: str = "") -> Optional[str]:
    """Re-derive the canonical source_key from event payload.

    Deliberately ignores any `data.source_key` already stored on legacy events
    — those used a non-unified scheme (`meal_logged:meal:<id>`,
    `meal_logged:nutrition_task_meal:<task>:<id>`, `task_completed:task:<id>`)
    that prevented related events from collapsing. Re-derivation lets one
    canonical key win on the read path without mutating historical docs.
    """
    data = event.get("data") or {}
    canonical = canonical_event_source_key(
        user_id=user_id,
        event_type=event.get("type"),
        source_task_id=data.get("source_task_id"),
        task_type=data.get("task_type"),
        source_type=data.get("source_type"),
        meal_id=data.get("meal_id"),
    )
    if canonical:
        return canonical
    # Pre-canonical events that have nothing identity-stable to key on still
    # fall back to the stored source_key (best effort — they cannot dedupe
    # against re-derived keys).
    if data.get("source_key"):
        return str(data["source_key"])
    return None


def _is_nutrition_task_event(event: dict) -> bool:
    """Any dayprint event tied to a Nutrition task — `meal_logged` written by
    the bridge, or a legacy `task_completed` from before the route stopped
    emitting them. Identified by either source_type starting with
    `nutrition_task` or task_type ∈ {Nutrition, nutrition}."""
    data = event.get("data") or {}
    source_type = data.get("source_type") or ""
    task_type = data.get("task_type")
    return (
        source_type.startswith("nutrition_task")
        or task_type in _NUTRITION_TASK_TYPES
    )


def _dedupe_dayprint_events(
    events: list[dict],
    *,
    user_id: str = "",
) -> list[dict]:
    """Strict "Nutrition Task = Meal" enforcement on the read path.

    Two passes:

    1. **Filter** — drop every `task_completed` event tied to a Nutrition
       task. The bridged `meal_logged` event is the ONLY representation of
       a Nutrition task in the dayprint, so a `task_completed` row is
       always wrong (it's either legacy data or a bug). Filtered even when
       it's the ONLY event for that source_key — a stale orphan must not
       leak through just because the meal_logged hasn't been written yet.

    2. **Dedupe** — collapse remaining events by canonical source key.
       When two events share a key (e.g. duplicate bridge writes from
       legacy data with different meal_ids), keep the earliest emitted.
       `meal_logged` wins over any other type on tie — defence in depth
       against future legacy variants.
    """
    # Pass 1: filter.
    filtered: list[dict] = []
    for event in events or []:
        if event.get("type") == "task_completed" and _is_nutrition_task_event(event):
            continue
        filtered.append(event)

    # Pass 2: dedupe.
    by_key: dict[str, dict] = {}
    for event in filtered:
        key = _dayprint_event_source_key(event, user_id=user_id)
        if not key:
            continue
        existing = by_key.get(key)
        if existing is None:
            by_key[key] = event
            continue
        if (
            existing.get("type") != "meal_logged"
            and event.get("type") == "meal_logged"
        ):
            by_key[key] = event

    seen: set[str] = set()
    out: list[dict] = []
    for event in filtered:
        key = _dayprint_event_source_key(event, user_id=user_id)
        if not key:
            out.append(event)
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append(by_key[key])
    return out


async def log_task_completed(
    user_id: str,
    task_name: str,
    task_type: str,
    *,
    source_task_id: Optional[str] = None,
) -> None:
    """Append a task_completed event to today's dayprint.

    Nutrition tasks are skipped — the bridge already writes a meal_logged
    event for the same task, and that single event represents both "user
    completed the task" and "this meal happened" in the UI. Writing a
    parallel task_completed entry produces a duplicate visible row.
    """
    # Suppress for nutrition tasks: the bridge's meal_logged subsumes this.
    str_task_type = (
        task_type.value if hasattr(task_type, "value") else str(task_type or "")
    )
    if str_task_type in _NUTRITION_TASK_TYPES:
        return
    try:
        db = get_database()
        date = _today_utc_str()
        await _upsert_dayprint(db, user_id, date)

        data = {"task_name": task_name, "task_type": str_task_type}
        source_key: Optional[str] = None
        if source_task_id:
            source_key = canonical_event_source_key(
                user_id=user_id,
                event_type="task_completed",
                source_task_id=source_task_id,
                task_type=str_task_type,
            )
            data["source_task_id"] = source_task_id
            data["source_type"] = "task"
            if source_key:
                data["source_key"] = source_key

        event = {
            "event_id": str(uuid.uuid4()),
            "type": "task_completed",
            "timestamp": format_utc_datetime(datetime.now(timezone.utc)),
            "data": data,
        }
        query: dict = {"user_id": user_id, "date": date}
        if source_key:
            query["events"] = {
                "$not": {"$elemMatch": {"data.source_key": source_key}}
            }
        await db.dayprints.update_one(
            query,
            {"$push": {"events": event}},
        )
    except Exception as e:
        logger.warning(f"Dayprint log_task_completed failed for {user_id}: {e}")


async def log_meal_logged(
    user_id: str,
    meal_id: str,
    food_preview: str,
    *,
    image_url: Optional[str] = None,
    visibility: str = "private",
    team_id: Optional[str] = None,
    source_type: str = "meal",
    source_task_id: Optional[str] = None,
) -> None:
    """Upsert a meal_logged event in today's dayprint by canonical source_key.

    Idempotent: every Nutrition-task lifecycle trigger (create/updateNote/
    uploadAttachments/completeTask) collapses to a single event keyed on
    `nutrition_task:<user>:<task>`, and a re-bridge after re-analysis
    refreshes the event's display data (food_preview, image, etc.) instead
    of pushing a duplicate row.

    Manual meals key on `meal:<meal_id>` so the same row is reused on
    re-saves.
    """
    try:
        db = get_database()
        date = _today_utc_str()
        await _upsert_dayprint(db, user_id, date)

        source_key = canonical_event_source_key(
            user_id=user_id,
            event_type="meal_logged",
            source_task_id=source_task_id,
            source_type=source_type,
            meal_id=meal_id,
        )
        if not source_key:
            return  # nothing identity-stable to key on; skip rather than spam

        now_iso = format_utc_datetime(datetime.now(timezone.utc))
        data = {
            "meal_id": meal_id,
            "food_preview": food_preview,
            "image_url": image_url,
            "visibility": visibility,
            "team_id": team_id,
            "source_type": source_type,
            "source_task_id": source_task_id,
            "source_key": source_key,
        }

        # Upsert pass 1 — refresh an event that already exists for this key.
        result = await db.dayprints.update_one(
            {
                "user_id": user_id,
                "date": date,
                "events": {
                    "$elemMatch": {"data.source_key": source_key}
                },
            },
            {"$set": {
                "events.$[evt].data": data,
                "events.$[evt].type": "meal_logged",
            }},
            array_filters=[{"evt.data.source_key": source_key}],
        )
        if getattr(result, "modified_count", 0):
            return

        # Pass 2 — no event yet, push a new one. The `$not` guard makes this
        # safe under concurrent triggers: a racing pass that sneaks in between
        # our two writes is rejected here.
        event = {
            "event_id": str(uuid.uuid4()),
            "type": "meal_logged",
            "timestamp": now_iso,
            "data": data,
        }
        await db.dayprints.update_one(
            {
                "user_id": user_id,
                "date": date,
                "events": {
                    "$not": {"$elemMatch": {"data.source_key": source_key}}
                },
            },
            {"$push": {"events": event}},
        )
    except Exception as e:
        logger.warning(f"Dayprint log_meal_logged failed for {user_id}: {e}")


async def log_hr_logged(
    user_id: str,
    *,
    session_id: str,
    avg_bpm: int,
    min_bpm: int,
    max_bpm: int,
    duration_seconds: int,
    reading_count: int,
) -> None:
    """Upsert today's hr_logged event for one HR session.

    Mirrors meal logging's idempotent source-key upsert pattern so retries do
    not create duplicate dayprint rows.
    """
    try:
        db = get_database()
        date = _today_utc_str()
        await _upsert_dayprint(db, user_id, date)

        source_key = f"hr_session:{session_id}"
        now_iso = format_utc_datetime(datetime.now(timezone.utc))
        data = {
            "session_id": session_id,
            "avg_bpm": avg_bpm,
            "min_bpm": min_bpm,
            "max_bpm": max_bpm,
            "duration_seconds": duration_seconds,
            "reading_count": reading_count,
            "source_key": source_key,
        }

        result = await db.dayprints.update_one(
            {
                "user_id": user_id,
                "date": date,
                "events": {"$elemMatch": {"data.source_key": source_key}},
            },
            {"$set": {
                "events.$[evt].data": data,
                "events.$[evt].type": "hr_logged",
            }},
            array_filters=[{"evt.data.source_key": source_key}],
        )
        if getattr(result, "modified_count", 0):
            return

        event = {
            "event_id": str(uuid.uuid4()),
            "type": "hr_logged",
            "timestamp": now_iso,
            "data": data,
        }
        await db.dayprints.update_one(
            {
                "user_id": user_id,
                "date": date,
                "events": {
                    "$not": {"$elemMatch": {"data.source_key": source_key}}
                },
            },
            {"$push": {"events": event}},
        )
    except Exception as e:
        logger.warning(f"Dayprint log_hr_logged failed for {user_id}: {e}")


async def refresh_dayprint_event_for_meal(
    user_id: str,
    *,
    meal_id: str,
    food_preview: str,
    image_url: Optional[str],
    visibility: str,
    team_id: Optional[str],
    source_type: str = "meal",
    source_task_id: Optional[str] = None,
) -> None:
    """Refresh the dayprint event payload for an existing Meal in place.

    Called after every successful `update_meal` so the dayprint never
    renders stale data (old food_preview, deleted image, etc.). Looks up
    the dayprint document by canonical source_key — does NOT create a new
    event if none exists, because an `update_meal` against a meal that was
    never written to dayprint should not retroactively add it.

    The lookup spans the user's recent dayprints so it correctly targets
    the original day a meal was logged on, not "today" — important for
    edits made after midnight.
    """
    try:
        source_key = canonical_event_source_key(
            user_id=user_id,
            event_type="meal_logged",
            source_task_id=source_task_id,
            source_type=source_type,
            meal_id=meal_id,
        )
        if not source_key:
            return

        db = get_database()
        doc = await db.dayprints.find_one(
            {"user_id": user_id, "events.data.source_key": source_key},
            {"date": 1, "user_id": 1},
        )
        if not doc:
            return  # nothing to refresh

        new_data = {
            "meal_id": meal_id,
            "food_preview": food_preview,
            "image_url": image_url,
            "visibility": visibility,
            "team_id": team_id,
            "source_type": source_type,
            "source_task_id": source_task_id,
            "source_key": source_key,
        }
        await db.dayprints.update_one(
            {
                "user_id": user_id,
                "date": doc["date"],
                "events.data.source_key": source_key,
            },
            {"$set": {
                "events.$[evt].data": new_data,
                "events.$[evt].type": "meal_logged",
            }},
            array_filters=[{"evt.data.source_key": source_key}],
        )
    except Exception as e:
        logger.warning(
            f"Dayprint refresh_dayprint_event_for_meal failed for {user_id}: {e}"
        )


async def attach_graph_to_hr_logged_event(
    user_id: str,
    *,
    session_id: str,
    image_url: str,
) -> None:
    """Attach/update graph image URL on an existing hr_logged dayprint event."""
    try:
        source_key = f"hr_session:{session_id}"
        db = get_database()
        doc = await db.dayprints.find_one(
            {"user_id": user_id, "events.data.source_key": source_key},
            {"date": 1, "events": 1},
        )
        if not doc:
            return

        target_event = None
        for evt in doc.get("events", []):
            data = evt.get("data") or {}
            if data.get("source_key") == source_key:
                target_event = evt
                break
        if not target_event:
            return

        new_data = dict(target_event.get("data") or {})
        new_data["image_url"] = image_url

        await db.dayprints.update_one(
            {
                "user_id": user_id,
                "date": doc["date"],
                "events.data.source_key": source_key,
            },
            {"$set": {
                "events.$[evt].data": new_data,
                "events.$[evt].type": "hr_logged",
            }},
            array_filters=[{"evt.data.source_key": source_key}],
        )
    except Exception as e:
        logger.warning(
            "Dayprint attach_graph_to_hr_logged_event failed for %s: %s",
            user_id,
            e,
        )


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
            f"3. Is this exchange about FAMILY? Decide using meaning, not keyword matching. "
            f"Set is_family_topic = true if the user is talking about a family member or family relationship — "
            f"for example a parent, sibling, child, spouse/partner, grandparent, in-law, or any relative; "
            f"family dynamics, conflict, caregiving, or a family member's health, mood, or behavior. "
            f"Casual mentions that are not the subject of the message do not count. "
            f"A passing word like 'family' in an idiom or unrelated context does not count. "
            f"If it is about family, also set category = \"family\" in task 4 unless a more specific medical category clearly fits better.\n"
            f"4. Is there something IMPORTANT in this exchange that warrants proactive follow-up? "
            f"IMPORTANT topics include:\n"
            f"  - Physical health: new/worsening symptom, pain or discomfort, feeling unwell, sickness, fever\n"
            f"  - Medication concerns: missed dose, side effect, medication not helping\n"
            f"  - Emotional/mental health: feeling very bad, anxious, overwhelmed, depressed, crying, distressed\n"
            f"  - Family/social: family conflict, family health concerns, family stress, worry about a relative\n"
            f"  - Urgent signals: anything the user seems concerned about\n"
            f"Any exchange where is_family_topic = true and the user expresses concern, worry, conflict, or a problem "
            f"involving the family member should be treated as important. "
            f"NOT important = greetings, general health questions, routine progress check-ins, encouragement, casual chat. "
            f"If important → set important = true, write a brief important_summary (1 sentence, 3rd person, use the user's name), "
            f"and set category to one of: symptom, medication, emotional, health_concern, family, urgent, other. "
            f"Also set important_replace_last = true ONLY if this important insight continues the SAME topic as the 'Last flagged important insight from this session' shown above, "
            f"or false if it is a new/different concern, a new session, or there was no previous insight.\n\n"
            f"Respond ONLY with valid JSON, no other text:\n"
            f"{{\"summary\": \"...\", \"replace_last\": true, \"is_family_topic\": false, \"important\": false, \"important_summary\": \"\", \"category\": \"\", \"important_replace_last\": false}}"
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
        is_family_topic = bool(parsed.get("is_family_topic", False))
        is_important = bool(parsed.get("important", False))
        important_summary = parsed.get("important_summary", "")
        category = parsed.get("category", "other")
        important_replace_last = bool(parsed.get("important_replace_last", False))

        # Family detection comes from the LLM (see is_family_topic in the prompt above);
        # ensure category is consistent when family is the subject of the exchange.
        if is_family_topic and category in ("", "other"):
            category = "family"

        # ── Keyword-based fallback: catch emotional/sickness patterns the LLM might miss ──
        combined_text = f"{user_message} {reply}".lower()

        emotional_keywords = {"sad", "depressed", "anxious", "stressed", "overwhelmed", "crying", "scared", "worried", "upset", "frustrated", "angry"}
        sickness_keywords = {"sick", "unwell", "fever", "flu", "cold", "vomit", "nausea", "headache", "ache", "pain", "sore"}

        has_emotional_topic = any(kw in combined_text for kw in emotional_keywords)
        has_sickness_topic = any(kw in combined_text for kw in sickness_keywords)

        if not is_important:
            if has_emotional_topic:
                is_important = True
                category = "emotional"
                important_summary = f"{name} expressed emotional distress or worry."
            elif has_sickness_topic:
                is_important = True
                category = "symptom"
                important_summary = f"{name} mentioned feeling unwell or being sick."

        elif is_important and category == "other":
            if is_family_topic:
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


def _log_raw_events(label: str, user_id: str, date: str, events: list[dict]) -> None:
    """Per-event INFO trace, one line per dayprint event the API is about to
    process. Production traces can use this to prove that every Nutrition-
    task event collapses to one canonical row — and to spot the legacy
    cross-key duplicates this fix targets.
    """
    for event in events:
        data = event.get("data") or {}
        logger.info(
            "DayprintAPI %s user=%s date=%s event_id=%s type=%s "
            "meal_id=%s source_key=%s source_type=%s source_task_id=%s "
            "task_type=%s timestamp=%s",
            label,
            user_id,
            date,
            event.get("event_id"),
            event.get("type"),
            data.get("meal_id"),
            data.get("source_key"),
            data.get("source_type"),
            data.get("source_task_id"),
            data.get("task_type"),
            event.get("timestamp"),
        )


def _meal_age_key_for_hydration(meal: dict):
    """Mirror MealService._meal_age_key without importing it (avoids cycle)."""
    created = meal.get("created_at")
    return (created is None, created or datetime.max)


def _food_preview_from_meal(meal: dict) -> Optional[str]:
    food_items = meal.get("food_items") or []
    names = [
        fi.get("name") for fi in food_items
        if isinstance(fi, dict) and fi.get("name")
    ]
    if not names:
        return None
    preview = " · ".join(names[:3])
    if len(names) > 3:
        preview += f" · +{len(names) - 3}"
    return preview


def _image_url_from_meal(meal: dict) -> Optional[str]:
    images = meal.get("images") or []
    if images and isinstance(images[0], dict):
        return images[0].get("url") or images[0].get("image_url")
    return None


async def _hydrate_events_with_meal_source(db, events: list[dict]) -> list[dict]:
    """Heal legacy dayprint mess at read time by resolving every
    `meal_logged` event to its CANONICAL meal — not just looking up the
    meal_id the event happens to point at.

    The bug this fixes — observed in production with cards rendering as
    "one with picture, one without":
        • Manual `POST /meals` with `linked_task_id` wrote meal row M_A and
          a dayprint event keyed `meal:<M_A>` (no source_task_id, no image).
        • Bridge later wrote meal row M_B and a dayprint event keyed
          `nutrition_task:<u>:<t>` (with image).
        • Two meal rows, two dayprint events, two different canonical
          identities → dedupe couldn't collapse them.

    Hydration approach:
        1. Look up every event's `meal_id` to discover whether it's
           task-linked (via `source_task_id` OR `linked_task_id`).
        2. For each task-linked event, find the CANONICAL meal for that
           task (oldest `created_at` among all meals sharing that task) —
           this is the row the Meals API will keep, the row with the
           freshest aggregated image + food data.
        3. Rewrite the event's `data` in memory: `source_task_id`,
           `source_type`, `meal_id`, `image_url`, `food_preview` all come
           from the canonical meal. Subsequent dedupe collapses cross-key
           duplicates AND every survivor renders with the picture and food
           data of the canonical meal.

    The mutation is in-memory only — storage is untouched.
    """
    candidates = [
        e for e in events
        if e.get("type") == "meal_logged"
        and (e.get("data") or {}).get("meal_id")
    ]
    if not candidates:
        return events

    meal_ids = list({e["data"]["meal_id"] for e in candidates})
    try:
        cursor = db.meals.find(
            {"meal_id": {"$in": meal_ids}},
            {
                "_id": 0,
                "meal_id": 1,
                "user_id": 1,
                "source_type": 1,
                "source_task_id": 1,
                "linked_task_id": 1,
                "images": 1,
                "food_items": 1,
                "created_at": 1,
            },
        )
        rows = await cursor.to_list(length=len(meal_ids))
    except Exception as exc:
        logger.warning("Dayprint meal hydration failed (event meals): %s", exc)
        return events

    by_id = {r["meal_id"]: r for r in rows if r.get("meal_id")}

    # Collect every (user_id, task_id) the events resolve to, then look up
    # ALL meals that belong to those tasks so we can pick the canonical row
    # per task. This is one extra batched find; cheap.
    task_keys: set[tuple[str, str]] = set()
    for event in candidates:
        meal = by_id.get(event["data"]["meal_id"])
        if not meal:
            continue
        tid = meal.get("source_task_id") or meal.get("linked_task_id")
        uid = meal.get("user_id")
        if tid and uid:
            task_keys.add((uid, tid))

    canonical_by_task: dict[tuple[str, str], dict] = {}
    if task_keys:
        try:
            uids = list({k[0] for k in task_keys})
            tids = list({k[1] for k in task_keys})
            task_cursor = db.meals.find(
                {
                    "user_id": {"$in": uids},
                    "$or": [
                        {"source_task_id": {"$in": tids}},
                        {"linked_task_id": {"$in": tids}},
                    ],
                },
                {
                    "_id": 0,
                    "meal_id": 1,
                    "user_id": 1,
                    "source_type": 1,
                    "source_task_id": 1,
                    "linked_task_id": 1,
                    "images": 1,
                    "food_items": 1,
                    "created_at": 1,
                },
            )
            task_rows = await task_cursor.to_list(length=None)
        except Exception as exc:
            logger.warning("Dayprint meal hydration failed (task meals): %s", exc)
            task_rows = []

        # Group ALL meals per task so we can pick a canonical AND merge any
        # photo / food data the canonical row happens to be missing.
        task_groups: dict[tuple[str, str], list[dict]] = {}
        for m in task_rows:
            uid = m.get("user_id")
            tid = m.get("source_task_id") or m.get("linked_task_id")
            if not (uid and tid):
                continue
            key = (uid, tid)
            if key not in task_keys:
                continue
            task_groups.setdefault(key, []).append(m)

        for key, group in task_groups.items():
            ordered = sorted(group, key=_meal_age_key_for_hydration)
            canonical = ordered[0]  # oldest created_at — preserves logged-at
            # Pick the "display source" — the row whose visible payload the
            # user should see. Prefer a row that actually has a picture
            # (that's the bridged row with the freshest task-derived data);
            # otherwise fall back to canonical.
            display = next((m for m in ordered if m.get("images")), canonical)
            merged = dict(canonical)
            # Lift visible payload from display row regardless of whether
            # canonical already has its own. The bridge row's data is the
            # latest task-synced state — preferring it fixes the "card shows
            # picture but tap-to-detail shows old food" inconsistency.
            if display.get("images"):
                merged["images"] = display["images"]
            if display.get("food_items"):
                merged["food_items"] = display["food_items"]
            canonical_by_task[key] = merged

    for event in candidates:
        original_meal_id = event["data"]["meal_id"]
        meal = by_id.get(original_meal_id)
        if not meal:
            continue
        tid = meal.get("source_task_id") or meal.get("linked_task_id")
        uid = meal.get("user_id")
        if not (tid and uid):
            continue
        canonical = canonical_by_task.get((uid, tid), meal)

        event["data"]["source_task_id"] = tid
        event["data"]["source_type"] = (
            canonical.get("source_type") or "nutrition_task"
        )
        # Rewrite meal_id to the canonical row so Dayprint cards link to the
        # surviving meal, not the duplicate the migration is about to drop.
        event["data"]["meal_id"] = canonical.get("meal_id") or original_meal_id

        canonical_image = _image_url_from_meal(canonical)
        if canonical_image:
            event["data"]["image_url"] = canonical_image
        canonical_preview = _food_preview_from_meal(canonical)
        if canonical_preview:
            event["data"]["food_preview"] = canonical_preview

        logger.info(
            "DayprintAPI hydrated event_id=%s original_meal_id=%s "
            "→ canonical_meal_id=%s task=%s image=%s",
            event.get("event_id"),
            original_meal_id,
            event["data"]["meal_id"],
            tid,
            "yes" if canonical_image else "no",
        )

    return events


async def _process_dayprint_doc(db, doc: dict, *, label: str) -> dict:
    """Hydrate, log raw events, then strict-filter + dedupe."""
    user_id = doc.get("user_id", "")
    date = doc.get("date", "")
    events = doc.get("events", [])
    # Detach event references via shallow-copy so in-memory hydration never
    # leaks back into anything caller-side that might still hold the doc.
    events = [dict(e, data=dict(e.get("data") or {})) for e in events]
    events = await _hydrate_events_with_meal_source(db, events)
    _log_raw_events(label, user_id, date, events)
    doc["events"] = _dedupe_dayprint_events(events, user_id=user_id)
    return doc


async def get_dayprint(user_id: str, date: Optional[str] = None) -> Optional[dict]:
    """Get a dayprint document. Defaults to today (UTC date)."""
    db = get_database()
    target_date = date or _today_utc_str()
    doc = await db.dayprints.find_one(
        {"user_id": user_id, "date": target_date},
        {"_id": 0},
    )
    if doc:
        doc = await _process_dayprint_doc(db, doc, label="get_dayprint")
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

    for doc in docs:
        await _process_dayprint_doc(db, doc, label="get_dayprint_history")

    next_before_date = docs[-1]["date"] if docs else None
    return docs, has_more, next_before_date
