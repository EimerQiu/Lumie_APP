"""Advisor Orchestrator — handles /api/v2/advisor/chat.

Unified entry point that:
1. Loads user context and capabilities
2. Retrieves top-k candidate skills
3. Asks LLM to route: direct reply vs skill selection
4. Validates preconditions (capability, credentials)
5. Creates execution jobs or returns direct replies
"""
import asyncio
import logging
from datetime import datetime
from typing import Optional
from zoneinfo import ZoneInfo

from ..core.config import settings
from ..core.database import get_database
from . import capability_service
from . import skill_credential_service
from . import execution_service
from .llm_client import chat_completion
from .skill_registry_service import skill_registry, SkillIndexItem
from .task_service import TaskService
from ..models.task import TaskCreate, TaskType

logger = logging.getLogger(__name__)

# Layer 1 model routed through PaleBlueDot's OpenAI-compatible API.
_MODEL = settings.PALEBLUEDOT_MODEL


# ── Main entry point ─────────────────────────────────────────────────────────

async def handle_chat(
    user_id: str,
    message: str,
    history: list[dict],
    session_id: Optional[str] = None,
    target_user_id: Optional[str] = None,
    team_id: Optional[str] = None,
) -> dict:
    """Process a v2 advisor chat message.

    Returns dict with keys: type, reply, job_id, skill_id, status, nav_hint
    """
    # ── Step 1: Load user context ────────────────────────────────────────
    ctx = await _get_user_context(user_id)
    enabled_caps = await capability_service.get_user_enabled_capability_ids(user_id)

    # Auto-enable lumie_internal_data for all users if not already set
    if not enabled_caps:
        await capability_service.toggle_capability(user_id, "lumie_internal_data", True)
        enabled_caps = {"lumie_internal_data"}
        # Auto-provision ping credentials for Lumie internal skills
        await _ensure_lumie_credentials(user_id)

    # ── Step 2: Retrieve top-k candidate skills ──────────────────────────
    candidates = skill_registry.retrieve_top_k(
        query=message,
        enabled_capabilities=enabled_caps,
        top_k=8,
    )

    # ── Step 3: Build system prompt and ask LLM to route ─────────────────
    system_prompt = _build_system_prompt(ctx, candidates)
    tools = _build_tools(candidates)

    messages = [*history, {"role": "user", "content": message}]

    response = await chat_completion(
        model=_MODEL,
        max_tokens=800,
        temperature=0.3,
        system=system_prompt,
        messages=messages,
        tools=tools,
    )

    # ── Step 4: Process response ─────────────────────────────────────────
    if not response.tool_calls:
        return {"type": "direct", "reply": response.text or "I'm here to help!"}

    tool_call = response.tool_calls[0]
    tool_name = tool_call.name
    tool_input = tool_call.arguments
    preflight_text = response.text

    if not tool_input or not tool_name:
        return {"type": "direct", "reply": preflight_text or "I'm not sure how to help with that."}

    if tool_name == "create_task":
        return await _handle_create_task(
            user_id=user_id,
            tool_input=tool_input,
            timezone=ctx.get("timezone") or "UTC",
            preflight_text=preflight_text,
        )

    if tool_name == "execute_skill":
        return await _handle_skill_execution(
            user_id=user_id,
            session_id=session_id,
            tool_input=tool_input,
            preflight_text=preflight_text,
            enabled_caps=enabled_caps,
            ctx=ctx,
            target_user_id=target_user_id,
            team_id=team_id,
            history=history,
            message=message,
        )

    return {"type": "direct", "reply": preflight_text or "I'm here to help!"}


# ── Skill execution handler ─────────────────────────────────────────────────

async def _handle_skill_execution(
    user_id: str,
    session_id: Optional[str],
    tool_input: dict,
    preflight_text: str,
    enabled_caps: set[str],
    ctx: dict,
    target_user_id: Optional[str],
    team_id: Optional[str],
    history: list[dict],
    message: str,
) -> dict:
    """Handle the execute_skill tool call."""
    skill_id = tool_input.get("skill_id", "")
    reason = tool_input.get("reason", "")
    target_email = tool_input.get("target_email", "")
    target_user_hint = tool_input.get("target_user_hint", "")

    # Resolve target email → user_id if provided
    if target_email:
        resolved_id = await _resolve_email_to_user_id(target_email)
        if resolved_id:
            target_user_id = resolved_id
        else:
            return {
                "type": "direct",
                "reply": f"I couldn't find a user with the email **{target_email}** in the system.",
            }
    elif target_user_hint:
        resolved_id = await _resolve_target_user_hint(
            request_user_id=user_id,
            target_user_hint=target_user_hint,
            team_id=team_id,
        )
        if resolved_id:
            target_user_id = resolved_id
        else:
            return {
                "type": "guidance",
                "reply": (
                    f"{preflight_text}\n\n"
                    "I wasn't able to tell exactly which person you meant. "
                    "Please tell me their full name or email address, and I can look it up."
                ).strip(),
            }

    # ── Step 5: Validate skill exists and is indexed ─────────────────
    skill = skill_registry.get_skill(skill_id)
    if not skill or skill.status != "indexed":
        return {
            "type": "guidance",
            "reply": f"{preflight_text}\n\nI couldn't find that skill. Please check your Advisor settings.",
        }

    # ── Step 6: Check capability ─────────────────────────────────────
    if skill.capability_id not in enabled_caps:
        return {
            "type": "guidance",
            "reply": (
                f"{preflight_text}\n\n"
                f"To do this, you need to enable the **{skill.capability_id}** capability "
                f"in Advisor Settings."
            ),
        }

    # ── Step 7: Load full skill text ─────────────────────────────────
    skill_full_text = skill_registry.load_skill_full_text(skill_id)
    if not skill_full_text:
        return {
            "type": "guidance",
            "reply": f"{preflight_text}\n\nThe skill definition could not be loaded. Please try again later.",
        }

    # ── Step 8: Load credentials ─────────────────────────────────────
    credential = None
    if skill.requires_credentials or skill.requires_ping:
        cred_key = f"__shared__{skill.shared_credential_id}" if skill.shared_credential_id else skill_id
        credential = await skill_credential_service.get_credential(user_id, cred_key)

        # Auto-provision Lumie internal credentials
        if not credential and skill.capability_id == "lumie_internal_data" and skill.requires_ping:
            credential = await skill_credential_service.ensure_lumie_internal_credential(
                user_id, skill_id
            )

        if skill.requires_credentials and (not credential or credential.get("status") not in ("valid", "saved_not_tested")):
            return {
                "type": "guidance",
                "reply": (
                    f"{preflight_text}\n\n"
                    f"This skill requires credentials that haven't been configured yet. "
                    f"Please set up your credentials for **{skill.title}** in Advisor Settings."
                ),
            }

        if skill.requires_ping and (not credential or not credential.get("ping")):
            return {
                "type": "guidance",
                "reply": f"{preflight_text}\n\nInternal access token is missing. Please re-enable the capability in settings.",
            }

    # ── Step 9: Create execution job ─────────────────────────────────
    effective_target = target_user_id or user_id
    job_id = await execution_service.create_execution_job(
        user_id=user_id,
        session_id=session_id,
        skill=skill,
        prompt=message,
        target_user_id=effective_target,
        team_id=team_id,
    )

    # ── Step 10: Start execution asynchronously ──────────────────────
    history_summary = _summarize_history(history) if history else ""

    asyncio.create_task(
        execution_service.run_execution_job(
            job_id=job_id,
            skill=skill,
            skill_full_text=skill_full_text,
            credential=credential,
            user_context=ctx,
            history_summary=history_summary,
        )
    )

    # ── Step 11: Return immediately ──────────────────────────────────
    return {
        "type": "execution",
        "reply": preflight_text or f"Let me look into that using **{skill.title}**...",
        "job_id": job_id,
        "skill_id": skill_id,
        "status": "pending",
    }


# ── Tool definitions ─────────────────────────────────────────────────────────

def _build_tools(candidates: list[SkillIndexItem]) -> list[dict]:
    """Build the tool definitions for the LLM, including execute_skill and create_task."""
    # Build skill enum from candidates
    skill_options = []
    for c in candidates:
        skill_options.append(c.skill_id)

    tools = [
        {
            "name": "execute_skill",
            "description": (
                "Call this tool when the user's question requires executing a skill to answer. "
                "Select the most appropriate skill from the available candidates. "
                "Do NOT use for general knowledge questions — only when user data or external system access is needed.\n\n"
                "Available skills:\n" +
                "\n".join(
                    f"- {c.skill_id}: {c.summary}"
                    for c in candidates
                )
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "skill_id": {
                        "type": "string",
                        "enum": skill_options if skill_options else ["none"],
                        "description": "The ID of the skill to execute",
                    },
                    "reason": {
                        "type": "string",
                        "description": "Brief reason for choosing this skill",
                    },
                    "target_email": {
                        "type": "string",
                        "description": "If the user is asking about ANOTHER person (e.g. a team member), provide that person's email address here. Leave empty if the user is asking about themselves.",
                    },
                    "target_user_hint": {
                        "type": "string",
                        "description": "If the user is asking about another person but no email is provided, put the exact reference here, such as 'my daughter', 'my son', 'my child', or the team member's name. Leave empty for self-queries.",
                    },
                },
                "required": ["skill_id"],
            },
        },
        {
            "name": "create_task",
            "description": (
                "Call this tool when the user wants to CREATE, ADD, or SET a new task or reminder. "
                "Supports deadline mode (single task with start/end) and recurring mode (daily tasks)."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_name": {"type": "string", "description": "Name of the task"},
                    "task_type": {
                        "type": "string",
                        "enum": ["Medicine", "Life", "Study", "Exercise", "Work", "Meditation", "Love"],
                        "description": "Type of task",
                    },
                    "mode": {
                        "type": "string",
                        "enum": ["deadline", "recurring"],
                        "description": "deadline = single task, recurring = repeated daily tasks",
                    },
                    "open_datetime": {"type": "string", "description": "DEADLINE mode: start datetime 'yyyy-MM-dd HH:mm'"},
                    "close_datetime": {"type": "string", "description": "DEADLINE mode: end datetime 'yyyy-MM-dd HH:mm'"},
                    "dates": {"type": "array", "items": {"type": "string"}, "description": "RECURRING mode: list of dates"},
                    "times": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "open_time": {"type": "string"},
                                "close_time": {"type": "string"},
                            },
                            "required": ["open_time", "close_time"],
                        },
                        "description": "RECURRING mode: time windows",
                    },
                    "task_info": {"type": "string", "description": "Optional notes"},
                },
                "required": ["task_name", "task_type", "mode"],
            },
        },
    ]

    return tools


# ── System prompt ────────────────────────────────────────────────────────────

def _build_system_prompt(ctx: dict, candidates: list[SkillIndexItem]) -> str:
    name = ctx.get("name") or "the user"
    age = ctx.get("age")
    condition = ctx.get("icd10_code")
    advisor = ctx.get("advisor_name")
    timezone = ctx.get("timezone") or "UTC"

    skill_summary = ""
    if candidates:
        skill_summary = "\n## Available Skills\n"
        for c in candidates:
            skill_summary += f"- **{c.title}** (`{c.skill_id}`): {c.summary}\n"

    return f"""You are Lumie, a compassionate AI health advisor built into the Lumie app.
Lumie helps teens and young adults with chronic health conditions stay active safely.

User profile:
- Name: {name}
- Age: {age or 'unknown'}
- Medical condition (ICD-10): {condition or 'No condition on file'}
{f'- Their healthcare advisor/coach is {advisor}' if advisor else ''}

## Decision Rules

You have two tools: `execute_skill` and `create_task`.

**Use execute_skill when:**
- The user asks a question that requires querying their personal data
- The user asks about their activity, sleep, tasks, medication schedule, health trends
- The user asks about school homework, email, or anything requiring external system access
- Choose the most relevant skill from the available candidates
- If the user mentions another person by email (e.g., "check tasks of alice@example.com"), set `target_email` to that email so we query that person's data instead of the requester's
- If the user refers to another person without an email (e.g., "my daughter", "my son", "my child", or a team member's name), set `target_user_hint` to that exact phrase or name

**Use create_task when:**
- The user wants to ADD, CREATE, or SET a new task or reminder
- "Remind me to...", "Add a task for...", "Set a reminder..."

**Answer directly when:**
- General health advice or tips
- Greetings, small talk, emotional support
- Medical knowledge questions
- Questions you can answer without data access

**Key distinction:** "What medicine should I take now?" = needs data (use execute_skill) ≠ "What medications treat diabetes?" = general knowledge (answer directly)
{skill_summary}

## create_task guidelines
- DEADLINE mode: single task with open_datetime + close_datetime
- RECURRING mode: dates × time windows
- "before X" means close_datetime = day BEFORE X at 23:59
- User's timezone: {timezone}

## Response guidelines
- Keep replies concise: 2-4 sentences unless detailed explanation needed
- Acknowledge the user's condition and energy levels
- Encourage consistency over intensity
- Never replace medical advice
- Use warm, supportive language
- TEEN-SAFE: Never output calories, BMI, weight comparisons
- You may use **bold** but avoid bullet points in conversational replies

## Context
- Right now (user's local time): {_user_now(timezone).strftime('%Y-%m-%d %H:%M')} ({_user_now(timezone).strftime('%A')})
- User's timezone: {timezone}"""


# ── Helpers ──────────────────────────────────────────────────────────────────

async def _get_user_context(user_id: str) -> dict:
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


def _user_now(timezone: str) -> datetime:
    try:
        tz = ZoneInfo(timezone)
    except Exception:
        tz = ZoneInfo("UTC")
    return datetime.now(tz)


def _summarize_history(history: list[dict]) -> str:
    """Create a brief summary of conversation history for execution context."""
    if not history:
        return ""
    recent = history[-6:]  # Last 3 exchanges
    lines = []
    for msg in recent:
        role = msg.get("role", "")
        content = msg.get("content", "")
        if len(content) > 200:
            content = content[:200] + "..."
        lines.append(f"{role}: {content}")
    return "\n".join(lines)


async def _resolve_email_to_user_id(email: str) -> Optional[str]:
    """Resolve an email address to a user_id."""
    try:
        db = get_database()
        user = await db.users.find_one({"email": email.strip().lower()})
        if user:
            return user.get("user_id")
        return None
    except Exception as e:
        logger.warning(f"Could not resolve email {email}: {e}")
        return None


async def _resolve_target_user_hint(
    request_user_id: str,
    target_user_hint: str,
    team_id: Optional[str] = None,
) -> Optional[str]:
    """Resolve a natural-language target user reference to a user_id.

    Supports:
    - direct self references: "me", "myself", "my"
    - email hints
    - family/team references like "my daughter", "my son", "my child"
    - exact or partial team member name matches within admin-accessible teams
    """
    hint = (target_user_hint or "").strip()
    if not hint:
        return None

    hint_lower = hint.lower()
    if hint_lower in {"me", "myself", "my", "self"}:
        return request_user_id

    if "@" in hint_lower:
        return await _resolve_email_to_user_id(hint_lower)

    db = get_database()

    # Build the set of teams the requester administers.
    team_query: dict = {
        "user_id": request_user_id,
        "role": "admin",
        "status": "member",
    }
    if team_id:
        team_query["team_id"] = team_id

    admin_memberships = await db.team_members.find(team_query).to_list(length=50)
    if not admin_memberships:
        return None

    team_ids = [m["team_id"] for m in admin_memberships]
    team_members = await db.team_members.find({
        "team_id": {"$in": team_ids},
        "status": "member",
    }).to_list(length=200)

    candidate_user_ids = {
        m["user_id"]
        for m in team_members
        if m.get("user_id") != request_user_id
    }
    if not candidate_user_ids:
        return None

    # Family references: if there is exactly one accessible member, use it.
    family_hints = {
        "my daughter", "daughter", "my son", "son", "my child", "child",
        "my kid", "kid", "my teen", "teen",
    }
    if hint_lower in family_hints and len(candidate_user_ids) == 1:
        return next(iter(candidate_user_ids))

    # Load candidate profiles + emails for exact/partial matching.
    profiles = await db.profiles.find({
        "user_id": {"$in": list(candidate_user_ids)},
    }).to_list(length=200)
    users = await db.users.find(
        {"user_id": {"$in": list(candidate_user_ids)}},
        {"user_id": 1, "email": 1, "_id": 0},
    ).to_list(length=200)
    email_by_user_id = {
        u["user_id"]: (u.get("email") or "").lower()
        for u in users
    }

    exact_matches: list[str] = []
    partial_matches: list[str] = []
    for profile in profiles:
        candidate_id = profile["user_id"]
        name = (profile.get("name") or "").strip().lower()
        email = email_by_user_id.get(candidate_id, "")

        if hint_lower == name or hint_lower == email:
            exact_matches.append(candidate_id)
            continue
        if hint_lower in name or (email and hint_lower in email):
            partial_matches.append(candidate_id)

    if len(exact_matches) == 1:
        return exact_matches[0]
    if len(partial_matches) == 1:
        return partial_matches[0]
    if hint_lower in family_hints:
        # Ambiguous family reference: if multiple members exist, prefer no resolution
        # over picking the wrong person.
        return None
    return None


async def _ensure_lumie_credentials(user_id: str) -> None:
    """Auto-provision Lumie internal credentials for all lumie_internal_data skills."""
    skills = skill_registry.get_skills_by_capability("lumie_internal_data")
    for skill in skills:
        if skill.requires_ping:
            await skill_credential_service.ensure_lumie_internal_credential(
                user_id, skill.skill_id
            )


# ── create_task handler (reused from v1) ─────────────────────────────────────

async def _handle_create_task(
    user_id: str,
    tool_input: dict,
    timezone: str,
    preflight_text: str,
) -> dict:
    task_service = TaskService()
    task_name = tool_input.get("task_name", "Task")
    task_type_str = tool_input.get("task_type", "Medicine")
    mode = tool_input.get("mode", "recurring")
    task_info = tool_input.get("task_info")

    try:
        task_type = TaskType(task_type_str)
    except ValueError:
        task_type = TaskType.MEDICINE

    created_count = 0
    errors = []

    if mode == "deadline":
        open_dt = tool_input.get("open_datetime")
        close_dt = tool_input.get("close_datetime")
        if not open_dt or not close_dt:
            return {"type": "direct", "reply": "I need a start and end time to create this task. Could you clarify when it should be?"}
        try:
            task_data = TaskCreate(
                task_name=task_name, task_type=task_type,
                open_datetime=open_dt, close_datetime=close_dt,
                timezone=timezone, task_info=task_info,
            )
            await task_service.create_task(user_id, task_data)
            created_count = 1
        except Exception as e:
            errors.append(getattr(e, "detail", str(e)))
    else:
        times = tool_input.get("times", [])
        dates = tool_input.get("dates", [])
        if not times or not dates:
            return {"type": "direct", "reply": "I need both dates and times to create recurring tasks. Could you tell me the schedule?"}
        for date_str in dates:
            for tw in times:
                try:
                    task_data = TaskCreate(
                        task_name=task_name, task_type=task_type,
                        open_datetime=f"{date_str} {tw.get('open_time', '08:00')}",
                        close_datetime=f"{date_str} {tw.get('close_time', '09:00')}",
                        timezone=timezone, task_info=task_info,
                    )
                    await task_service.create_task(user_id, task_data)
                    created_count += 1
                except Exception as e:
                    errors.append(f"{date_str}: {getattr(e, 'detail', str(e))}")

    if created_count == 0:
        return {"type": "direct", "reply": f"I wasn't able to create the task. {errors[0] if errors else 'Unknown error'}"}

    reply = f"Done! I've created **{task_name}**." if created_count == 1 else f"Done! I've created **{created_count}** **{task_name}** tasks."
    if errors:
        reply += f" ({len(errors)} could not be created.)"
    return {"type": "direct", "reply": reply, "nav_hint": "task_list"}
