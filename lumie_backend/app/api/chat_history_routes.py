"""Chat history API routes — retrieve persisted advisor conversations."""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from ..services.auth_service import get_current_user_id
from ..services.chat_history_service import get_history, get_session_messages, get_sessions

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/advisor", tags=["advisor"])


class ChatMessageResponse(BaseModel):
    session_id: str
    role: str
    content: str
    metadata: dict = {}
    created_at: str


class ChatHistoryResponse(BaseModel):
    messages: list[ChatMessageResponse]
    has_more: bool


class SessionSummaryResponse(BaseModel):
    session_id: str
    started_at: str
    last_message_at: str
    preview: str
    message_count: int
    # Advisor cross-user collab thread metadata (§13.2). Defaults preserve
    # backwards compatibility for legacy/normal sessions.
    channel: str = "advisor_user"
    readonly: bool = False
    thread_id: Optional[str] = None
    collab_status: Optional[str] = None
    peer_user_id: Optional[str] = None


class SessionListResponse(BaseModel):
    sessions: list[SessionSummaryResponse]


class SessionMessagesResponse(BaseModel):
    messages: list[ChatMessageResponse]


@router.get("/sessions", response_model=SessionListResponse)
async def list_sessions(
    user_id: str = Depends(get_current_user_id),
    limit: int = Query(default=50, ge=1, le=200),
):
    """List all chat sessions for the user, newest first."""
    sessions = await get_sessions(user_id, limit=limit)
    return SessionListResponse(
        sessions=[
            SessionSummaryResponse(
                session_id=s["session_id"],
                started_at=s["started_at"],
                last_message_at=s.get("last_message_at", s["started_at"]),
                preview=s["preview"],
                message_count=s["message_count"],
                channel=s.get("channel") or "advisor_user",
                readonly=bool(s.get("readonly", False)),
                thread_id=s.get("thread_id"),
                collab_status=s.get("collab_status"),
                peer_user_id=s.get("peer_user_id"),
            )
            for s in sessions
        ]
    )


@router.get("/sessions/{session_id}/messages", response_model=SessionMessagesResponse)
async def get_session(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Fetch all messages for a specific session in chronological order."""
    messages = await get_session_messages(user_id, session_id)
    return SessionMessagesResponse(
        messages=[
            ChatMessageResponse(
                session_id=m.get("session_id", ""),
                role=m["role"],
                content=m["content"],
                metadata=m.get("metadata", {}),
                created_at=m["created_at"],
            )
            for m in messages
        ]
    )


@router.get("/history", response_model=ChatHistoryResponse)
async def get_chat_history(
    user_id: str = Depends(get_current_user_id),
    limit: int = Query(default=50, ge=1, le=200),
    before: Optional[str] = Query(default=None),
):
    """Fetch the user's advisor chat history, paginated newest-first.

    Query params:
        limit:  max messages to return (default 50, max 200).
        before: ISO timestamp cursor — returns messages older than this
                (for infinite scroll / load-more).

    Returns messages in **reverse chronological** order.  The frontend
    should reverse them for display.
    """
    # Fetch one extra to know if there are more
    messages = await get_history(user_id, limit=limit + 1, before=before)
    has_more = len(messages) > limit
    if has_more:
        messages = messages[:limit]

    return ChatHistoryResponse(
        messages=[
            ChatMessageResponse(
                session_id=m.get("session_id", ""),
                role=m["role"],
                content=m["content"],
                metadata=m.get("metadata", {}),
                created_at=m["created_at"],
            )
            for m in messages
        ],
        has_more=has_more,
    )
