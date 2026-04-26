"""Chat history service — persists advisor conversation messages.

Stores every user↔advisor exchange in the ``chat_messages`` collection
so the frontend can reload history across app restarts, and the data is
available server-side for future analytics / context features.

Collection schema::

    {
        "user_id": str,
        "session_id": str,          # groups messages into conversations
        "role": "user" | "assistant",
        "content": str,
        "metadata": {               # optional per-message extras
            "type": "direct" | "analysis",
            "job_id": str | None,
            "nav_hint": str | None,
        },
        "created_at": str (ISO UTC),
    }

Indexes (create once at startup or via migration):
    - (user_id, created_at)   — fast paginated fetch
    - (user_id, session_id)   — fast session-scoped fetch
"""

import logging
from datetime import datetime, timezone
from typing import Optional

from ..core.database import get_database
from ..core.datetime_utils import format_utc_datetime, format_utc_datetime_with_ms

logger = logging.getLogger(__name__)


async def save_message(
    user_id: str,
    session_id: str,
    role: str,
    content: str,
    metadata: Optional[dict] = None,
) -> None:
    """Persist a single chat message."""
    db = get_database()
    effective_metadata = metadata or {}
    doc = {
        "user_id": user_id,
        "session_id": session_id or "default",
        "role": role,
        "content": content,
        "metadata": effective_metadata,
        "created_at": format_utc_datetime(datetime.now(timezone.utc)),
    }
    await db.chat_messages.insert_one(doc)

    message_type = effective_metadata.get("type")
    if role == "assistant" and message_type in {"execution", "proactive"}:
        logger.info(
            "Advisor outbound message: type=%s user=%s session=%s content=%r",
            message_type,
            user_id,
            session_id or "default",
            content,
        )


async def save_exchange(
    user_id: str,
    session_id: str,
    user_message: str,
    assistant_reply: str,
    metadata: Optional[dict] = None,
) -> None:
    """Persist a user→assistant exchange (two messages) in one call."""
    from datetime import timedelta

    db = get_database()
    now = datetime.now(timezone.utc)
    effective_session_id = session_id or "default"
    docs = [
        {
            "user_id": user_id,
            "session_id": effective_session_id,
            "role": "user",
            "content": user_message,
            "metadata": {},
            "created_at": (now - timedelta(milliseconds=1)).isoformat(),
        },
        {
            "user_id": user_id,
            "session_id": effective_session_id,
            "role": "assistant",
            "content": assistant_reply,
            "metadata": metadata or {},
            "created_at": format_utc_datetime(now),
        },
    ]
    await db.chat_messages.insert_many(docs)


async def get_history(
    user_id: str,
    limit: int = 100,
    before: Optional[str] = None,
) -> list[dict]:
    """Fetch chat messages for a user, newest-first, with cursor pagination.

    Args:
        user_id: the user whose history to fetch.
        limit: max messages to return (default 100).
        before: ISO timestamp cursor — only return messages older than this.

    Returns:
        List of message dicts (newest first).  The caller should reverse
        for chronological display.
    """
    db = get_database()
    query: dict = {"user_id": user_id}
    if before:
        query["created_at"] = {"$lt": before}

    cursor = db.chat_messages.find(
        query,
        {"_id": 0},
    ).sort("created_at", -1).limit(limit)

    messages = await cursor.to_list(length=limit)
    return messages


async def get_session_messages(
    user_id: str,
    session_id: str,
) -> list[dict]:
    """Fetch all messages for a specific session, in chronological order."""
    db = get_database()
    cursor = db.chat_messages.find(
        {"user_id": user_id, "session_id": session_id},
        {"_id": 0},
    ).sort("created_at", 1)
    return await cursor.to_list(length=500)


async def get_sessions(user_id: str, limit: int = 50) -> list[dict]:
    """Fetch distinct sessions for a user, ordered by most recent activity.

    Returns one entry per session:
        session_id, started_at, last_message_at, preview (latest message), message_count
    """
    db = get_database()
    pipeline = [
        {"$match": {"user_id": user_id, "session_id": {"$nin": [None, ""]}}},
        {"$sort": {"created_at": 1}},
        {
            "$group": {
                "_id": "$session_id",
                "started_at": {"$first": "$created_at"},
                "last_message_at": {"$last": "$created_at"},
                "preview": {"$last": "$content"},
                "message_count": {"$sum": 1},
            }
        },
        {"$sort": {"last_message_at": -1}},
        {"$limit": limit},
        {
            "$project": {
                "_id": 0,
                "session_id": "$_id",
                "started_at": 1,
                "last_message_at": 1,
                "preview": 1,
                "message_count": 1,
            }
        },
    ]
    return await db.chat_messages.aggregate(pipeline).to_list(length=limit)


async def ensure_indexes() -> None:
    """Create indexes if they don't exist. Call on app startup."""
    db = get_database()
    await db.chat_messages.create_index([("user_id", 1), ("created_at", -1)])
    await db.chat_messages.create_index([("user_id", 1), ("session_id", 1)])
