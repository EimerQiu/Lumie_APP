"""Advisor service — intelligent routing via Claude tool_use.

Layer 1: Routes user messages to either a direct reply (fast path) or
data analysis (slow path) using Claude's tool_use capability.
"""
import asyncio
import logging
from datetime import datetime
from typing import Optional
from zoneinfo import ZoneInfo

import anthropic

from ..core.config import settings
from ..core.database import get_database
from .analysis_service import (
    check_analysis_quota,
    create_analysis_job,
    run_analysis_job,
    _check_rate_limit,
)
from .task_service import TaskService
from ..models.task import TaskCreate, TaskType

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

CREATE_TASK_TOOL = {
    "name": "create_task",
    "description": (
        "Call this tool when the user wants to CREATE, ADD, or SET a new task or reminder. "
        "This tool supports two modes:\n"
        "1. DEADLINE mode: one task with a start and end datetime (use open_datetime + close_datetime). "
        "Use for 'before Tuesday', 'by Friday', 'remind me to do X this week'.\n"
        "2. RECURRING mode: multiple daily tasks at specific times (use dates + times). "
        "Use for 'every day at 8am', 'take medicine at 9am and 9pm for the next 5 days'.\n"
        "This tool CREATES tasks — do NOT use it for querying existing tasks (use run_data_analysis for that)."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "task_name": {
                "type": "string",
                "description": "Name of the task, e.g. 'Take Metformin', 'Buy flowers', 'Study Math'",
            },
            "task_type": {
                "type": "string",
                "enum": ["Medicine", "Life", "Study", "Exercise", "Work", "Meditation", "Love"],
                "description": "Type of task. Use Medicine for medications, Life for meals/daily habits/errands, etc.",
            },
            "mode": {
                "type": "string",
                "enum": ["deadline", "recurring"],
                "description": "deadline = single task with start/end datetime. recurring = repeated daily tasks.",
            },
            "open_datetime": {
                "type": "string",
                "description": "DEADLINE mode only. Start datetime in 'yyyy-MM-dd HH:mm' format. Use current time if the user says 'from now'.",
            },
            "close_datetime": {
                "type": "string",
                "description": "DEADLINE mode only. End datetime in 'yyyy-MM-dd HH:mm' format. For 'before Tuesday', set to Monday 23:59.",
            },
            "dates": {
                "type": "array",
                "items": {"type": "string"},
                "description": "RECURRING mode only. List of dates in yyyy-MM-dd format.",
            },
            "times": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "open_time": {
                            "type": "string",
                            "description": "Start time in HH:mm format (24h)",
                        },
                        "close_time": {
                            "type": "string",
                            "description": "End time in HH:mm format (24h). Default to 1 hour after open_time if not specified.",
                        },
                    },
                    "required": ["open_time", "close_time"],
                },
                "description": "RECURRING mode only. Time windows for each day.",
            },
            "task_info": {
                "type": "string",
                "description": "Optional extra info or notes about the task",
            },
        },
        "required": ["task_name", "task_type", "mode"],
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


# ── Helpers ──────────────────────────────────────────────────────────────────

def _user_now(timezone: str) -> datetime:
    """Return the current datetime in the user's timezone."""
    try:
        tz = ZoneInfo(timezone)
    except Exception:
        tz = ZoneInfo("UTC")
    return datetime.now(tz)


# ── System prompt ────────────────────────────────────────────────────────────

def _build_system_prompt(ctx: dict) -> str:
    name = ctx.get("name") or "the user"
    age = ctx.get("age")
    condition = ctx.get("icd10_code")
    advisor = ctx.get("advisor_name")
    timezone = ctx.get("timezone") or "UTC"

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
- Creating/adding new tasks or reminders (use create_task instead)

**Key distinction**: "What medicine should I take now?" = needs data (query their tasks) ≠ "What medications treat diabetes?" = general knowledge (answer directly)

## When to use the create_task tool
Call create_task when the user wants to ADD, CREATE, or SET a new task or reminder.

**Choose the right mode:**

DEADLINE mode (mode="deadline") — for tasks with a time window to complete:
- "Remind me to buy flowers before Tuesday" → deadline: open_datetime=current datetime (from Context above), close_datetime=Monday 23:59
- "I need to finish my homework by Friday" → deadline: open_datetime=current datetime, close_datetime=Friday 23:59
- "Add a study session tomorrow 3-5pm" → deadline: open_datetime=tomorrow 15:00, close_datetime=tomorrow 17:00
- IMPORTANT: "before X" / "by X" means the task must be done BEFORE that day starts. close_datetime = the day BEFORE X at 23:59. Example: "before Tuesday March 25" → close = "2026-03-24 23:59" (Monday). NEVER set close to Tuesday itself.
- "on X" / "at X time" → open and close on that specific day/time

RECURRING mode (mode="recurring") — for repeated daily tasks:
- "Remind me to take my medicine at 8am every day this week" → recurring: list each date, times=[08:00-09:00]
- "Exercise at 6pm for the next 3 days" → recurring: 3 dates, times=[18:00-19:00]
- "Take pills at 9am and 9pm daily" → recurring: dates list, times=[09:00-10:00, 21:00-22:00]

Guidelines:
- Always pick the most appropriate task_type from: Medicine, Life, Study, Exercise, Work, Meditation, Love
- For recurring mode: if end time not specified, default close_time to 1 hour after open_time
- For deadline mode: if start not specified, use the exact current datetime from the Context section; if "before X", close = day before X at 23:59
- The user's timezone is: {timezone}

## Response guidelines
- Keep replies concise: 2-4 sentences unless a detailed explanation is clearly needed.
- Always acknowledge the user's condition and energy levels.
- Encourage consistency over intensity.
- Never replace medical advice - remind the user to check with their care team for anything clinical.
- Use warm, supportive language. Avoid being preachy.
- TEEN-SAFE: Never output calories, BMI, weight comparisons, or performance rankings.
- You may use **bold** to emphasise key words, but do not use bullet points, numbered lists, or headers.

## Context
- Right now (user's local time): {_user_now(timezone).strftime('%Y-%m-%d %H:%M')} ({_user_now(timezone).strftime('%A')})
- User's timezone: {timezone}"""


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
        tools=[RUN_DATA_ANALYSIS_TOOL, CREATE_TASK_TOOL],
    )

    # ── Fast path: direct reply ──────────────────────────────────────────
    if response.stop_reason == "end_turn":
        reply_text = ""
        for block in response.content:
            if block.type == "text":
                reply_text += block.text
        return {"type": "direct", "reply": reply_text}

    # ── Tool use path ─────────────────────────────────────────────────────
    if response.stop_reason == "tool_use":
        # Extract which tool was called
        tool_name = None
        tool_input = None
        preflight_text = ""
        for block in response.content:
            if block.type == "tool_use":
                tool_name = block.name
                tool_input = block.input
            elif block.type == "text":
                preflight_text = block.text

        if not tool_input or not tool_name:
            return {"type": "direct", "reply": preflight_text or "I'm not sure how to help with that."}

        # ── create_task path ──────────────────────────────────────────────
        if tool_name == "create_task":
            return await _handle_create_task(
                user_id=user_id,
                tool_input=tool_input,
                timezone=ctx.get("timezone") or "UTC",
                preflight_text=preflight_text,
            )

        # ── run_data_analysis path (default) ─────────────────────────────
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


async def _handle_create_task(
    user_id: str,
    tool_input: dict,
    timezone: str,
    preflight_text: str,
) -> dict:
    """Handle the create_task tool call by creating tasks via TaskService.

    Supports two modes:
    - deadline: single task with open_datetime + close_datetime
    - recurring: multiple tasks from dates × times
    """
    task_service = TaskService()

    task_name = tool_input.get("task_name", "Task")
    task_type_str = tool_input.get("task_type", "Medicine")
    mode = tool_input.get("mode", "recurring")
    task_info = tool_input.get("task_info")

    # Map task_type string to enum
    try:
        task_type = TaskType(task_type_str)
    except ValueError:
        task_type = TaskType.MEDICINE

    created_count = 0
    errors = []

    if mode == "deadline":
        # ── Deadline mode: single task with full datetimes ────────────
        open_dt = tool_input.get("open_datetime")
        close_dt = tool_input.get("close_datetime")

        if not open_dt or not close_dt:
            return {
                "type": "direct",
                "reply": "I need a start and end time to create this task. Could you clarify when it should be?",
            }

        try:
            task_data = TaskCreate(
                task_name=task_name,
                task_type=task_type,
                open_datetime=open_dt,
                close_datetime=close_dt,
                timezone=timezone,
                task_info=task_info,
            )
            await task_service.create_task(user_id, task_data)
            created_count = 1
        except Exception as e:
            detail = getattr(e, "detail", str(e))
            errors.append(detail)
            logger.warning(f"Failed to create deadline task: {e}")

    else:
        # ── Recurring mode: dates × time windows ─────────────────────
        times = tool_input.get("times", [])
        dates = tool_input.get("dates", [])

        if not times or not dates:
            return {
                "type": "direct",
                "reply": "I need both dates and times to create recurring tasks. Could you tell me the schedule?",
            }

        for date_str in dates:
            for time_window in times:
                open_time = time_window.get("open_time", "08:00")
                close_time = time_window.get("close_time", "09:00")

                try:
                    task_data = TaskCreate(
                        task_name=task_name,
                        task_type=task_type,
                        open_datetime=f"{date_str} {open_time}",
                        close_datetime=f"{date_str} {close_time}",
                        timezone=timezone,
                        task_info=task_info,
                    )
                    await task_service.create_task(user_id, task_data)
                    created_count += 1
                except Exception as e:
                    detail = getattr(e, "detail", str(e))
                    errors.append(f"{date_str}: {detail}")
                    logger.warning(f"Failed to create task for {date_str}: {e}")

    # Build reply
    if created_count == 0:
        error_msg = errors[0] if errors else "Unknown error"
        return {
            "type": "direct",
            "reply": f"I wasn't able to create the task. {error_msg}",
        }

    if created_count == 1:
        reply = f"Done! I've created **{task_name}** for you."
    else:
        reply = f"Done! I've created **{created_count}** **{task_name}** tasks for you."

    if errors:
        reply += f" ({len(errors)} could not be created.)"

    return {
        "type": "direct",
        "reply": reply,
        "nav_hint": "task_list",
    }


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
