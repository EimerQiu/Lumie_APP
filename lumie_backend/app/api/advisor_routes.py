"""Advisor API routes — AI chat endpoint."""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..services.auth_service import get_current_user_id
from ..services.advisor_service import get_advisor_reply

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/advisor", tags=["advisor"])


# ── Request / Response models ─────────────────────────────────────────────────

class HistoryMessage(BaseModel):
    role: str     # "user" or "assistant"
    content: str


class AdvisorChatRequest(BaseModel):
    message: str
    history: list[HistoryMessage] = []


class AdvisorChatResponse(BaseModel):
    reply: str


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/chat", response_model=AdvisorChatResponse)
async def advisor_chat(
    body: AdvisorChatRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Send a message to the Lumie AI Advisor and receive a reply.

    - **message**: The user's latest message.
    - **history**: Prior conversation turns (oldest first), each with a `role`
      ("user" or "assistant") and `content` field.

    The advisor is personalised using the authenticated user's profile
    (condition, age, advisor name).
    """
    if not body.message.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Message cannot be empty.",
        )

    try:
        history = [{"role": m.role, "content": m.content} for m in body.history]
        reply = await get_advisor_reply(
            user_id=user_id,
            message=body.message,
            history=history,
        )
        return AdvisorChatResponse(reply=reply)
    except RuntimeError as e:
        # ANTHROPIC_API_KEY not configured
        logger.error(f"Advisor config error: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Advisor service is not configured. Please contact support.",
        )
    except Exception as e:
        logger.error(f"Advisor chat error for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not reach the advisor service. Please try again.",
        )
