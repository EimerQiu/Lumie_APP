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
    doc = {
        "user_id": user_id,
        "session_id": session_id,
        "role": role,
        "content": content,
        "metadata": metadata or {},
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    await db.chat_messages.insert_one(doc)


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
    docs = [
        {
            "user_id": user_id,
            "session_id": session_id,
            "role": "user",
            "content": user_message,
            "metadata": {},
            "created_at": (now - timedelta(milliseconds=1)).isoformat(),
        },
        {
            "user_id": user_id,
            "session_id": session_id,
            "role": "assistant",
            "content": assistant_reply,
            "metadata": metadata or {},
            "created_at": now.isoformat(),
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


async def ensure_indexes() -> None:
    """Create indexes if they don't exist. Call on app startup."""
    db = get_database()
    await db.chat_messages.create_index([("user_id", 1), ("created_at", -1)])
    await db.chat_messages.create_index([("user_id", 1), ("session_id", 1)])
