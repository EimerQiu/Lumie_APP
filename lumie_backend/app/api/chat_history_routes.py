"""Chat history API routes — retrieve persisted advisor conversations."""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from ..services.auth_service import get_current_user_id
from ..services.chat_history_service import get_history

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
