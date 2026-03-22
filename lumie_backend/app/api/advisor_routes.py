"""Advisor API routes — AI chat endpoint with intelligent routing."""
import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..core.database import get_database
from ..services.auth_service import get_current_user_id
from ..services.advisor_service import get_advisor_reply
from ..services.dayprint_service import log_advisor_chat
from ..services.chat_history_service import save_exchange

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/advisor", tags=["advisor"])


# ── Request / Response models ─────────────────────────────────────────────────

class HistoryMessage(BaseModel):
    role: str     # "user" or "assistant"
    content: str


class AdvisorChatRequest(BaseModel):
    message: str
    history: list[HistoryMessage] = []
    target_user_id: Optional[str] = None
    team_id: Optional[str] = None
    session_id: Optional[str] = None


class AdvisorChatResponse(BaseModel):
    type: str = "direct"        # "direct" or "analysis"
    reply: str
    job_id: Optional[str] = None
    nav_hint: Optional[str] = None  # "task_list" | "task_dashboard" | None


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/chat", response_model=AdvisorChatResponse)
async def advisor_chat(
    body: AdvisorChatRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Send a message to the Lumie AI Advisor and receive a reply.

    The advisor intelligently routes between:
    - **Direct reply** (fast path): general questions, greetings, health advice
    - **Data analysis** (slow path): questions requiring user data lookup

    Response includes a `type` field:
    - `"direct"`: read `reply` and display immediately
    - `"analysis"`: show `reply` as placeholder, use `job_id` to poll for results
    """
    if not body.message.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Message cannot be empty.",
        )

    try:
        history = [{"role": m.role, "content": m.content} for m in body.history]
        result = await get_advisor_reply(
            user_id=user_id,
            message=body.message,
            history=history,
            target_user_id=body.target_user_id,
            team_id=body.team_id,
        )
        # Persist chat messages + log to Dayprint in background
        session_id = body.session_id or ""
        resp_type = result.get("type", "direct")

        if resp_type == "direct":
            db = get_database()
            profile = await db.profiles.find_one({"user_id": user_id}, {"name": 1}) or {}
            user_name = profile.get("name", "")
            asyncio.create_task(
                log_advisor_chat(user_id, user_name, body.message, result["reply"], session_id=body.session_id)
            )
            # Save the full exchange to chat_messages for history
            asyncio.create_task(
                save_exchange(
                    user_id, session_id, body.message, result["reply"],
                    metadata={"type": "direct", "nav_hint": result.get("nav_hint")},
                )
            )
        else:
            # Analysis path: save user message now, assistant reply saved when job completes
            asyncio.create_task(
                save_exchange(
                    user_id, session_id, body.message, result["reply"],
                    metadata={"type": "analysis", "job_id": result.get("job_id")},
                )
            )

        return AdvisorChatResponse(
            type=result.get("type", "direct"),
            reply=result["reply"],
            job_id=result.get("job_id"),
            nav_hint=result.get("nav_hint"),
        )
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
