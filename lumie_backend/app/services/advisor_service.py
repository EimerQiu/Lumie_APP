"""Advisor service — intelligent routing via Claude tool_use.

Layer 1: Routes user messages to either a direct reply (fast path) or
data analysis (slow path) using Claude's tool_use capability.
"""
import asyncio
import logging
from typing import Optional

import anthropic

from ..core.config import settings
from ..core.database import get_database
from .analysis_service import (
    check_analysis_quota,
    create_analysis_job,
    run_analysis_job,
    _check_rate_limit,
)

logger = logging.getLogger(__name__)

# Layer 1 model: Sonnet for accurate tool_use + fast response
_MODEL = "claude-sonnet-4-20250514"

# One shared async Anthropic client (initialised lazily)
_client: Optional[anthropic.AsyncAnthropic] = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        if not settings.ANTHROPIC_API_KEY:
            raise RuntimeError("ANTHROPIC_API_KEY is not set in environment variables.")
        _client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


# ── Tool definition ──────────────────────────────────────────────────────────

RUN_DATA_ANALYSIS_TOOL = {
    "name": "run_data_analysis",
    "description": (
        "Call this tool when the user's question requires querying their personal health data to answer. "
        "Examples: activity trends, medication completion rates, heart rate analysis, walk test comparisons, "
        "upcoming medication/task reminders, what tasks are due now/today, which medicines to take, "
        "meal reminders, study tasks, exercise plans, or any scheduled tasks. "
        "The tasks system covers ALL types: Medicine, Life, Study, Exercise, Work, Meditation, Love — not just medications. "
        "Do NOT use for general health knowledge questions that can be answered directly."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "question": {
                "type": "string",
                "description": "The specific data question to analyze, passed to the data analysis system",
            },
            "data_types": {
                "type": "array",
                "items": {
                    "type": "string",
                    "enum": ["activities", "tasks", "walk_tests", "profile"],
                },
                "description": "Types of data to query",
            },
            "time_range": {
                "type": "string",
                "description": "Time range description, e.g., 'last 7 days', 'this month', 'past 30 days'",
            },
        },
        "required": ["question"],
    },
}


# ── Profile context ──────────────────────────────────────────────────────────

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
            "timezone": profile.get("timezone"),
        }
    except Exception as e:
        logger.warning(f"Could not fetch profile for advisor context: {e}")
        return {}


async def _get_subscription_tier(user_id: str) -> str:
    """Get the user's subscription tier."""
    try:
        db = get_database()
        user = await db.users.find_one({"user_id": user_id})
        if user and user.get("subscription"):
            return user["subscription"].get("tier", "free")
    except Exception as e:
        logger.warning(f"Could not fetch subscription tier: {e}")
    return "free"


# ── System prompt ────────────────────────────────────────────────────────────

def _build_system_prompt(ctx: dict) -> str:
    name = ctx.get("name") or "the user"
    age = ctx.get("age")
    condition = ctx.get("icd10_code")
    advisor = ctx.get("advisor_name")

    return f"""You are Lumie, a compassionate AI health advisor built into the Lumie app.
Lumie helps teens and young adults with chronic health conditions stay active safely.

User profile:
- Name: {name}
- Age: {age or 'unknown'}
- Medical condition (ICD-10): {condition or 'No condition on file'}
{f'- Their healthcare advisor/coach is {advisor}' if advisor else ''}

## When to use the run_data_analysis tool
Call run_data_analysis when the user asks a question that requires querying their personal data:
- Activity trends, totals, or comparisons over time
- Task/medication completion rates or statistics
- Heart rate analysis
- Walk test progress
- Any question that asks about specific numbers/trends in their data
- **Task/schedule questions**: "what should I do now", "what's due today", "any upcoming reminders", "what medicine should I take" — these require looking up the user's tasks
- Any question about the user's own tasks, medications, meals, exercise plans, or schedules
- The task system has 7 types: Medicine, Life (meals, daily habits), Study, Exercise, Work, Meditation, Love — always query ALL relevant types unless the user specifies one

Do NOT call the tool for:
- General health advice or tips (e.g., "what are good stretches for arthritis")
- Greetings or small talk
- Questions about medical conditions in general (answer from knowledge)
- Emotional support or encouragement
- Questions you can answer without the user's personal data

**Key distinction**: "What medicine should I take now?" = needs data (query their tasks) ≠ "What medications treat diabetes?" = general knowledge (answer directly)

## Response guidelines
- Keep replies concise: 2-4 sentences unless a detailed explanation is clearly needed.
- Always acknowledge the user's condition and energy levels.
- Encourage consistency over intensity.
- Never replace medical advice - remind the user to check with their care team for anything clinical.
- Use warm, supportive language. Avoid being preachy.
- TEEN-SAFE: Never output calories, BMI, weight comparisons, or performance rankings.
- You may use **bold** to emphasise key words, but do not use bullet points, numbered lists, or headers."""


# ── Main entry point ─────────────────────────────────────────────────────────

async def get_advisor_reply(
    user_id: str,
    message: str,
    history: list[dict],
    target_user_id: Optional[str] = None,
    team_id: Optional[str] = None,
) -> dict:
    """Call Claude with tool_use and return a routing result.

    Returns:
        dict with keys:
          - type: "direct" or "analysis"
          - reply: text response
          - job_id: (only for "analysis") UUID of the created job
    """
    ctx = await _get_user_context(user_id)
    system_prompt = _build_system_prompt(ctx)

    messages = [*history, {"role": "user", "content": message}]

    client = _get_client()
    response = await client.messages.create(
        model=_MODEL,
        max_tokens=800,
        temperature=0.3,
        system=system_prompt,
        messages=messages,
        tools=[RUN_DATA_ANALYSIS_TOOL],
    )

    # ── Fast path: direct reply ──────────────────────────────────────────
    if response.stop_reason == "end_turn":
        reply_text = ""
        for block in response.content:
            if block.type == "text":
                reply_text += block.text
        return {"type": "direct", "reply": reply_text}

    # ── Slow path: tool_use → data analysis ──────────────────────────────
    if response.stop_reason == "tool_use":
        # Extract tool input
        tool_input = None
        preflight_text = ""
        for block in response.content:
            if block.type == "tool_use" and block.name == "run_data_analysis":
                tool_input = block.input
            elif block.type == "text":
                preflight_text = block.text

        if not tool_input:
            return {"type": "direct", "reply": preflight_text or "I'm not sure how to help with that."}

        # Check rate limit
        rate_error = _check_rate_limit(user_id)
        if rate_error:
            return {"type": "direct", "reply": rate_error}

        # Check subscription quota
        subscription_tier = await _get_subscription_tier(user_id)
        quota_msg = await check_analysis_quota(user_id, subscription_tier)
        if quota_msg:
            return {"type": "direct", "reply": quota_msg}

        # Check parent permissions if target_user_id specified
        effective_target = target_user_id or user_id
        if target_user_id and target_user_id != user_id:
            has_access = await _verify_team_admin_access(user_id, target_user_id, team_id)
            if not has_access:
                return {
                    "type": "direct",
                    "reply": "You don't have permission to view this user's data.",
                }

        # Create analysis job
        job_id = await create_analysis_job(
            user_id=user_id,
            prompt=tool_input["question"],
            target_user_id=effective_target,
            team_id=team_id,
            data_types=tool_input.get("data_types", []),
            time_range=tool_input.get("time_range", ""),
        )

        # Start async execution
        asyncio.create_task(run_analysis_job(job_id))

        return {
            "type": "analysis",
            "reply": preflight_text or "Let me analyze your data...",
            "job_id": job_id,
        }

    # Unexpected stop_reason
    reply_text = ""
    for block in response.content:
        if block.type == "text":
            reply_text += block.text
    return {"type": "direct", "reply": reply_text or "I'm here to help!"}


async def _verify_team_admin_access(
    user_id: str,
    target_user_id: str,
    team_id: Optional[str],
) -> bool:
    """Verify that user_id has admin access to target_user_id's data via a team."""
    if not team_id:
        return False

    db = get_database()
    admin_membership = await db.team_members.find_one({
        "team_id": team_id,
        "user_id": user_id,
        "role": "admin",
        "status": "member",
    })
    if not admin_membership:
        return False

    target_membership = await db.team_members.find_one({
        "team_id": team_id,
        "user_id": target_user_id,
        "status": "member",
    })
    return target_membership is not None
