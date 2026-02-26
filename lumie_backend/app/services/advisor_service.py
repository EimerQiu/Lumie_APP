"""Advisor service — calls Claude to generate health guidance replies."""
import logging
from typing import Optional

import anthropic

from ..core.config import settings
from ..core.database import get_database

logger = logging.getLogger(__name__)

# Claude model to use
_MODEL = "claude-opus-4-6"

# One shared Anthropic client (initialised lazily so missing key doesn't crash startup)
_client: Optional[anthropic.Anthropic] = None


def _get_client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        if not settings.ANTHROPIC_API_KEY:
            raise RuntimeError("ANTHROPIC_API_KEY is not set in environment variables.")
        _client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


async def _get_user_context(user_id: str) -> dict:
    """Fetch profile fields needed to personalise the system prompt."""
    try:
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id})
        if not profile:
            return {}
        return {
            "name": profile.get("name"),
            "age": profile.get("age"),
            "icd10_code": profile.get("icd10_code"),
            "advisor_name": profile.get("advisor_name"),
        }
    except Exception as e:
        logger.warning(f"Could not fetch profile for advisor context: {e}")
        return {}


def _build_system_prompt(ctx: dict) -> str:
    name = ctx.get("name") or "the user"
    age = ctx.get("age")
    condition = ctx.get("icd10_code")
    advisor = ctx.get("advisor_name")

    age_line = f"Age: {age}." if age else ""
    condition_line = f"Medical condition (ICD-10): {condition}." if condition else "No condition on file."
    advisor_line = f"Their healthcare advisor/coach is {advisor}." if advisor else ""

    return f"""You are Lumie, a compassionate AI health advisor built into the Lumie app.
Lumie helps teens and young adults with chronic health conditions stay active safely.

User profile:
- Name: {name}
- {age_line}
- {condition_line}
- {advisor_line}

Guidelines:
- Keep replies concise: 2–4 sentences unless a detailed explanation is clearly needed.
- Always acknowledge the user's condition and energy levels.
- Encourage consistency over intensity.
- Never replace medical advice — remind the user to check with their care team for anything clinical.
- Use warm, supportive language. Avoid being preachy.
- If asked about data (sleep, steps, heart rate) you don't have access to, say so honestly and give general guidance instead."""


async def get_advisor_reply(
    user_id: str,
    message: str,
    history: list[dict],
) -> str:
    """
    Call Claude and return the assistant reply text.

    Args:
        user_id: Authenticated user's ID (used to personalise the system prompt).
        message: The user's latest message.
        history: Prior turns as [{"role": "user"|"assistant", "content": "..."}].
    """
    ctx = await _get_user_context(user_id)
    system_prompt = _build_system_prompt(ctx)

    # Build the messages list: history + current message
    messages = [*history, {"role": "user", "content": message}]

    client = _get_client()
    response = client.messages.create(
        model=_MODEL,
        max_tokens=400,
        system=system_prompt,
        messages=messages,
    )

    return response.content[0].text
