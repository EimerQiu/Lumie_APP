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
import re
from datetime import datetime, timedelta
from typing import Optional
from zoneinfo import ZoneInfo

from ..core.config import settings
from ..core.database import get_database
from ..core.credential_utils import resolve_credential_key
from . import capability_service
from . import skill_credential_service
from . import execution_service
from .llm_client import chat_completion
from .skill_registry_service import skill_registry, SkillIndexItem

logger = logging.getLogger(__name__)

# Layer 1 model routed through PaleBlueDot's OpenAI-compatible API.
_MODEL = settings.PALEBLUEDOT_MODEL
_REPLY_CLASSES = {
    "clarification_needed",
    "planned",
    "executed",
    "failed",
}


def _normalize_reply_class(value: Optional[str]) -> str:
    val = (value or "").strip().lower()
    if val in _REPLY_CLASSES:
        return val
    return "planned"


def _sanitize_non_executed_claims(text: str) -> str:
    lowered = (text or "").lower()
    blocked_markers = (
        "i created",
        "i updated",
        "i sent",
        "done - i created",
        "done — i created",
        "done, i created",
    )
    if any(marker in lowered for marker in blocked_markers):
        return "I have not completed that action yet. I will only confirm it after execution succeeds."
    return text


def _looks_like_schedule_detail(message: str) -> bool:
    text = (message or "").strip().lower()
    if not text:
        return False
    patterns = (
        r"\bnow\b",
        r"\btoday\b",
        r"\btomorrow\b",
        r"\btonight\b",
        r"\bnext\b",
        r"\bin \d+\s*(minute|minutes|min|hour|hours|hr|hrs|day|days)\b",
        r"\b\d{1,2}(:\d{2})?\s*(am|pm)\b",
        r"\b\d{1,2}:\d{2}\b",
        r"\bstart\b",
        r"\bend\b",
        r"现在|今天|明天|小时|分钟|开始|结束|点",
    )
    return any(re.search(p, text) for p in patterns)


async def _get_pending_task_create_action(user_id: str, session_id: Optional[str]) -> Optional[dict]:
    db = get_database()
    if db is None:
        return None
    now = datetime.utcnow()
    query = {
        "user_id": user_id,
        "action_type": "task_create_clarification",
        "status": "awaiting_input",
        "expires_at": {"$gt": now},
    }
    if session_id:
        query["session_id"] = session_id
    return await db.advisor_pending_actions.find_one(query, sort=[("updated_at", -1)])


async def _upsert_pending_task_create_action(
    user_id: str,
    session_id: Optional[str],
    original_request: str,
    clarification_prompt: str,
) -> None:
    db = get_database()
    if db is None:
        return
    now = datetime.utcnow()
    # 2-hour pending window
    expires_at = now + timedelta(hours=2)
    query = {
        "user_id": user_id,
        "session_id": session_id or "default",
        "action_type": "task_create_clarification",
        "status": "awaiting_input",
    }
    await db.advisor_pending_actions.update_one(
        query,
        {
            "$set": {
                "user_id": user_id,
                "session_id": session_id or "default",
                "action_type": "task_create_clarification",
                "skill_id": "tasks_create",
                "status": "awaiting_input",
                "original_request": original_request,
                "clarification_prompt": clarification_prompt,
                "updated_at": now,
                "expires_at": expires_at,
            },
            "$setOnInsert": {"created_at": now},
        },
        upsert=True,
    )


async def _mark_pending_task_create_resolved(user_id: str, session_id: Optional[str]) -> None:
    db = get_database()
    if db is None:
        return
    await db.advisor_pending_actions.update_many(
        {
            "user_id": user_id,
            "session_id": session_id or "default",
            "action_type": "task_create_clarification",
            "status": "awaiting_input",
        },
        {"$set": {"status": "resolved", "updated_at": datetime.utcnow()}},
    )

async def _extract_target_person_with_llm(message: str) -> Optional[str]:
    """Use LLM to detect if the user is asking about someone else's health/status.

    Returns the person's name/reference if asking about someone else, None if asking about self.

    Examples:
    - "Did Eimer take all her medication?" → "Eimer"
    - "Emma's sleep is low" → "Emma"
    - "How is my daughter?" → "my daughter"
    - "What's my heart rate?" → None (self)
    """
    prompt = f"""Analyze this message and determine if the user is asking about someone ELSE's health/status, or about their own.

Message: "{message}"

If the user is asking about SOMEONE ELSE's health/medication/sleep/exercise/status, respond with ONLY their name or relationship (e.g., "Emma", "John", "my daughter", "my son").
If the user is asking about their own health/status, or if it's unclear, respond with: "self"

Do NOT include quotes or explanation. Just the name or "self"."""

    try:
        response = await chat_completion(
            model=_MODEL,
            max_tokens=50,
            temperature=0,
            messages=[{"role": "user", "content": prompt}],
        )

        result = (response.text or "self").strip().lower()

        # If LLM says "self" or empty, no target person
        if result in {"self", "self.", "myself", "me", "my own", ""}:
            return None

        # Otherwise return the name/hint the LLM extracted
        return result if result else None
    except Exception as e:
        logger.warning(f"LLM target person extraction failed: {e}")
        return None


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

    Returns dict with keys: type, reply, reply_class, is_write_operation_task,
    job_id, skill_id, status, nav_hint
    """
    # ── Step 0.5: Auto-detect target user from health-related queries ────
    # Use LLM to detect if asking about someone else's health/status
    if not target_user_id:
        auto_hint = await _extract_target_person_with_llm(message)
        if auto_hint:
            resolved = await _resolve_target_user_hint(user_id, auto_hint, team_id)
            if resolved and resolved != user_id:
                target_user_id = resolved
                logger.info(f"Auto-detected target user from message: {auto_hint} → {target_user_id}")

    # ── Step 1: Load user context ────────────────────────────────────────
    ctx = await _get_user_context(user_id)
    enabled_caps = await capability_service.get_user_enabled_capability_ids(user_id)

    # Auto-enable lumie_internal_data for all users if not already set
    if not enabled_caps:
        await capability_service.toggle_capability(user_id, "lumie_internal_data", True)
        enabled_caps = {"lumie_internal_data"}
        # Auto-provision ping credentials for Lumie internal skills
        await _ensure_lumie_credentials(user_id)

    # ── Step 1.5: Resume pending task-create clarification if user provided schedule ──
    pending_task_create = await _get_pending_task_create_action(user_id, session_id)
    if pending_task_create and _looks_like_schedule_detail(message):
        original_request = pending_task_create.get("original_request") or "create a task"
        combined_prompt = (
            f"{original_request}\n\n"
            f"User follow-up details: {message}\n"
            "Use the follow-up details to fill missing schedule fields."
        )
        resumed = await _handle_skill_execution(
            user_id=user_id,
            session_id=session_id,
            tool_input={
                "skill_id": "tasks_create",
                "reason": "resume_from_clarification",
                "target_email": "",
                "target_user_hint": "",
            },
            preflight_text="Thanks, I have enough detail now. I’m creating it.",
            enabled_caps=enabled_caps,
            ctx=ctx,
            target_user_id=target_user_id,
            team_id=team_id,
            history=history,
            message=combined_prompt,
            reply_class="planned",
            is_write_operation_task=True,
        )
        if resumed.get("type") == "execution":
            await _mark_pending_task_create_resolved(user_id, session_id)
        return resumed

    # ── Step 2: Retrieve top-k candidate skills ──────────────────────────
    candidates = skill_registry.retrieve_top_k(
        query=message,
        enabled_capabilities=enabled_caps,
        top_k=8,
    )

    # ── Step 3: Build system prompt and ask LLM to route (structured) ───
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
        fallback_reply = _sanitize_non_executed_claims(response.text or "I need one more detail before I act.")
        return {
            "type": "guidance",
            "reply": fallback_reply,
            "reply_class": "clarification_needed",
            "is_write_operation_task": False,
        }

    tool_call = response.tool_calls[0]
    tool_name = tool_call.name
    tool_input = tool_call.arguments
    preflight_text = response.text

    if not tool_input or not tool_name:
        return {
            "type": "guidance",
            "reply": _sanitize_non_executed_claims(preflight_text or "I'm not sure how to help with that."),
            "reply_class": "clarification_needed",
            "is_write_operation_task": False,
        }

    if tool_name == "route_response":
        reply_class = _normalize_reply_class(tool_input.get("reply_class"))
        is_write_operation_task = bool(tool_input.get("is_write_operation_task", False))
        should_execute_skill = bool(tool_input.get("should_execute_skill", False))
        selected_skill_id = (tool_input.get("skill_id") or "").strip()
        response_text = (
            tool_input.get("response_text")
            or preflight_text
            or "I can help with that."
        )
        if reply_class != "executed":
            response_text = _sanitize_non_executed_claims(response_text)

        if should_execute_skill:
            skill_id = selected_skill_id
            if not skill_id:
                return {
                    "type": "guidance",
                    "reply": "I need one more detail before I proceed.",
                    "reply_class": "clarification_needed",
                    "is_write_operation_task": is_write_operation_task,
                }
            return await _handle_skill_execution(
                user_id=user_id,
                session_id=session_id,
                tool_input=tool_input,
                preflight_text=response_text,
                enabled_caps=enabled_caps,
                ctx=ctx,
                target_user_id=target_user_id,
                team_id=team_id,
                history=history,
                message=message,
                reply_class=reply_class,
                is_write_operation_task=is_write_operation_task,
            )

        response_type = "guidance" if reply_class in {"clarification_needed", "failed"} else "direct"
        if (
            reply_class == "clarification_needed"
            and is_write_operation_task
            and (selected_skill_id in {"tasks_create", "none", ""} or "task" in message.lower())
        ):
            await _upsert_pending_task_create_action(
                user_id=user_id,
                session_id=session_id,
                original_request=message,
                clarification_prompt=response_text,
            )
        return {
            "type": response_type,
            "reply": response_text,
            "reply_class": reply_class,
            "is_write_operation_task": is_write_operation_task,
        }

    if tool_name == "execute_skill":
        # Backward compatibility fallback if model returns legacy tool.
        return await _handle_skill_execution(
            user_id=user_id,
            session_id=session_id,
            tool_input=tool_input,
            preflight_text=_sanitize_non_executed_claims(preflight_text or "I can start this now."),
            enabled_caps=enabled_caps,
            ctx=ctx,
            target_user_id=target_user_id,
            team_id=team_id,
            history=history,
            message=message,
            reply_class="planned",
            is_write_operation_task=False,
        )

    return {
        "type": "direct",
        "reply": _sanitize_non_executed_claims(preflight_text or "I'm here to help!"),
        "reply_class": "planned",
        "is_write_operation_task": False,
    }


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
    reply_class: str,
    is_write_operation_task: bool,
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
                "reply_class": "failed",
                "is_write_operation_task": is_write_operation_task,
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
                "reply_class": "clarification_needed",
                "is_write_operation_task": is_write_operation_task,
            }

    # ── Step 5: Validate skill exists and is indexed ─────────────────
    skill = skill_registry.get_skill(skill_id)
    if not skill or skill.status != "indexed":
        return {
            "type": "guidance",
            "reply": f"{preflight_text}\n\nI couldn't find that skill. Please check your Advisor settings.",
            "reply_class": "failed",
            "is_write_operation_task": is_write_operation_task,
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
            "reply_class": "clarification_needed",
            "is_write_operation_task": is_write_operation_task,
        }

    # ── Step 7: Load full skill text ─────────────────────────────────
    skill_full_text = skill_registry.load_skill_full_text(skill_id)
    if not skill_full_text:
        return {
            "type": "guidance",
            "reply": f"{preflight_text}\n\nThe skill definition could not be loaded. Please try again later.",
            "reply_class": "failed",
            "is_write_operation_task": is_write_operation_task,
        }

    # ── Step 8: Load credentials ─────────────────────────────────────
    credential = None
    if skill.requires_credentials or skill.requires_ping:
        cred_key = resolve_credential_key(skill)
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
                "reply_class": "clarification_needed",
                "is_write_operation_task": is_write_operation_task,
            }

        if skill.requires_ping and (not credential or not credential.get("ping")):
            return {
                "type": "guidance",
                "reply": f"{preflight_text}\n\nInternal access token is missing. Please re-enable the capability in settings.",
                "reply_class": "failed",
                "is_write_operation_task": is_write_operation_task,
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
        is_write_operation_task=is_write_operation_task,
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
        "reply_class": "planned" if reply_class == "executed" else reply_class,
        "is_write_operation_task": is_write_operation_task,
    }


# ── Tool definitions ─────────────────────────────────────────────────────────

def _build_tools(candidates: list[SkillIndexItem]) -> list[dict]:
    """Build a single structured routing tool for first-hop protocol output."""
    skill_options = [c.skill_id for c in candidates] + ["none"]

    return [{
        "name": "route_response",
        "description": (
            "MANDATORY first-hop router. Always call this tool exactly once. "
            "Return protocol class + write intent + whether to execute a skill."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "reply_class": {
                    "type": "string",
                    "enum": ["clarification_needed", "planned", "executed", "failed"],
                    "description": "Protocol class for this response.",
                },
                "is_write_operation_task": {
                    "type": "boolean",
                    "description": "True if the user's request is a write-action intent (create/update/send/delete).",
                },
                "should_execute_skill": {
                    "type": "boolean",
                    "description": "Whether backend should start skill execution now.",
                },
                "response_text": {
                    "type": "string",
                    "description": "Assistant reply text. Only use completion wording when reply_class=executed.",
                },
                "skill_id": {
                    "type": "string",
                    "enum": skill_options,
                    "description": "Chosen skill_id when should_execute_skill=true; otherwise use 'none'.",
                },
                "reason": {
                    "type": "string",
                    "description": "Brief routing reason.",
                },
                "target_email": {
                    "type": "string",
                    "description": "If user asks about another person by email, put the email; else empty string.",
                },
                "target_user_hint": {
                    "type": "string",
                    "description": "If user asks about another person without email, put exact reference phrase; else empty string.",
                },
            },
            "required": ["reply_class", "is_write_operation_task", "should_execute_skill", "response_text", "skill_id"],
        },
    }]


# ── System prompt ────────────────────────────────────────────────────────────

def _build_profile_block(ctx: dict) -> str:
    """Build the User Profile section. Omits any field that is null/empty."""
    lines = []
    if ctx.get("name"):
        lines.append(f"- Name: {ctx['name']}")
    if ctx.get("age"):
        lines.append(f"- Age: {ctx['age']}")
    if ctx.get("role"):
        role_label = "Teen" if ctx["role"] == "teen" else "Parent/Guardian"
        lines.append(f"- Account type: {role_label}")
    if ctx.get("height"):
        lines.append(f"- Height: {ctx['height']}")
    if ctx.get("weight"):
        lines.append(f"- Weight: {ctx['weight']}")
    if ctx.get("condition_label"):
        lines.append(f"- Health condition: {ctx['condition_label']}")
    if ctx.get("advisor_name"):
        lines.append(f"- Healthcare provider: {ctx['advisor_name']}")
    return "\n".join(lines)


def _build_system_prompt(ctx: dict, candidates: list[SkillIndexItem]) -> str:
    name = ctx.get("name") or "the user"
    ai_advisor_name = ctx.get("ai_advisor_name")
    timezone = ctx.get("timezone") or "UTC"

    if ai_advisor_name:
        identity_block = (
            f'Your name is {ai_advisor_name}. Always use this name when referring to yourself. '
            f'If the user asks what your name is, respond with this name only — '
            f'never say your name is Lumie or any other name.'
        )
    else:
        identity_block = (
            'You do not have a name yet. If the user asks what your name is, '
            'tell them you do not have a name yet but they can set one in Edit Profile under Advisor Name. '
            'Never say your name is Lumie or any other name.'
        )

    profile_block = _build_profile_block(ctx)

    skill_summary = ""
    if candidates:
        skill_summary = "\n## Available Skills\n"
        for c in candidates:
            skill_summary += f"- **{c.title}** (`{c.skill_id}`): {c.summary}\n"

    logger.debug(f"[advisor_orchestrator] system_prompt[:300]: {identity_block[:300]}")

    return f"""{identity_block}

You are a compassionate AI health advisor built into the app.
This app helps teens and young adults with chronic health conditions stay active safely.

## About {name}
{profile_block if profile_block else "No profile information available yet."}

## Decision Rules

You have one mandatory routing tool: `route_response`.
Always call it exactly once for every user message.

Protocol contract:
- `reply_class` must be one of: `clarification_needed`, `planned`, `executed`, `failed`.
- You must set `is_write_operation_task` as a boolean judgment in this first call.
- Only `reply_class=executed` may contain completion claims such as "I created", "I updated", "I sent".
- If execution has not happened yet, use `planned` or `clarification_needed`.

**Set `should_execute_skill=true` when:**
- The user asks a question that requires querying their personal data
- The user asks about their activity, sleep, tasks, medication schedule, health trends
- The user wants to ADD, CREATE, or SET a new task or reminder
- The user asks about school homework, email, or anything requiring external system access
- Choose the most relevant skill from the available candidates
- If the user mentions another person by email (e.g., "check tasks of alice@example.com"), set `target_email` to that email so we query that person's data instead of the requester's
- If the user refers to another person without an email (e.g., "my daughter", "my son", "my child", or a team member's name), set `target_user_hint` to that exact phrase or name

**Set `should_execute_skill=false` when:**
- General health advice or tips
- Greetings, small talk, emotional support
- Medical knowledge questions
- Questions you can answer without data access

**Key distinction:** "What medicine should I take now?" = needs data (execute skill) ≠ "What medications treat diabetes?" = general knowledge (direct response)
{skill_summary}

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

def _icd10_label(code: str | None) -> str | None:
    """Resolve an ICD-10 code to a human-readable description."""
    if not code:
        return None
    from .icd10_service import ICD10_CODES
    for entry in ICD10_CODES:
        if entry.code == code:
            return entry.description
    # Fallback: use the code prefix to get a broad label
    prefix = code.split(".")[0]
    for entry in ICD10_CODES:
        if entry.code == prefix:
            return entry.description
    return None  # Unknown code — omit rather than expose raw code


def _format_height(height: dict | None) -> str | None:
    if not height:
        return None
    value = height.get("value")
    unit = height.get("unit", "cm")
    if value is None:
        return None
    if unit == "cm":
        return f"{int(value)} cm"
    # ft_in stored as total inches
    total_in = int(value)
    ft, inches = divmod(total_in, 12)
    return f"{ft}'{inches}\""


def _format_weight(weight: dict | None) -> str | None:
    if not weight:
        return None
    value = weight.get("value")
    unit = weight.get("unit", "kg")
    if value is None:
        return None
    return f"{value:.1f} {unit}"


async def _get_user_context(user_id: str) -> dict:
    try:
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id})
        if not profile:
            return {}
        ai_advisor_name = profile.get("ai_advisor_name")
        logger.info(f"[advisor_orchestrator] _get_user_context: ai_advisor_name={ai_advisor_name!r} for user_id={user_id}")
        return {
            "name": profile.get("name"),
            "age": profile.get("age"),
            "role": profile.get("role"),
            "height": _format_height(profile.get("height")),
            "weight": _format_weight(profile.get("weight")),
            "icd10_code": profile.get("icd10_code"),
            "condition_label": _icd10_label(profile.get("icd10_code")),
            "advisor_name": profile.get("advisor_name"),
            "ai_advisor_name": ai_advisor_name,
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
