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
from ..core.datetime_utils import format_utc_datetime
from ..models.advisor_cross_message import (
    CrossActionType,
    CrossAdvisorPendingActionStatus,
    CrossMessageStatus,
)
from . import capability_service
from . import skill_credential_service
from . import execution_service
from . import advisor_cross_message_service
from . import chat_history_service
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


# ── Cross-advisor pending action helpers ─────────────────────────────────────

CROSS_ADVISOR_ACTION_TYPE = "cross_advisor_action_confirmation"
DEFAULT_MAX_CROSS_TURNS = 5
CROSS_PENDING_TTL_HOURS = 24

_CONFIRM_TOKENS = {
    "yes", "y", "yep", "yeah", "ok", "okay", "sure", "confirm", "confirmed",
    "approve", "approved", "agree", "agreed", "do it", "go ahead", "proceed",
    "是", "好", "好的", "可以", "同意", "确认", "行",
}
_REJECT_TOKENS = {
    "no", "n", "nope", "cancel", "stop", "reject", "rejected", "deny", "denied",
    "don't", "dont", "do not",
    "不", "不要", "取消", "拒绝",
}


def _classify_user_confirmation(text: str) -> str:
    """Classify a user reply as approve | reject | ask_more.

    Pure keyword matching for MVP — short replies like "yes" or "no" are the
    common case.  Anything that doesn't clearly map to approve/reject is
    treated as ``ask_more`` so the pending action stays open.
    """
    if not text:
        return "ask_more"
    normalized = text.strip().lower().rstrip(".!?。！？")
    if normalized in _CONFIRM_TOKENS:
        return "approve"
    if normalized in _REJECT_TOKENS:
        return "reject"
    # Multi-word: check the first 3 tokens for an unambiguous signal.
    head = " ".join(normalized.split()[:3])
    if head in _CONFIRM_TOKENS:
        return "approve"
    if head in _REJECT_TOKENS:
        return "reject"
    for tok in normalized.split():
        if tok in _CONFIRM_TOKENS:
            return "approve"
        if tok in _REJECT_TOKENS:
            return "reject"
    return "ask_more"


async def _get_pending_cross_advisor_action(user_id: str, session_id: Optional[str]) -> Optional[dict]:
    """Fetch the latest awaiting_user_confirm pending action for ``user_id``."""
    db = get_database()
    if db is None:
        return None
    now = datetime.utcnow()
    query = {
        "user_id": user_id,
        "action_type": CROSS_ADVISOR_ACTION_TYPE,
        "status": CrossAdvisorPendingActionStatus.AWAITING_USER_CONFIRM.value,
        "expires_at": {"$gt": now},
    }
    if session_id:
        query["session_id"] = session_id
    return await db.advisor_pending_actions.find_one(query, sort=[("updated_at", -1)])


async def _get_pending_cross_advisor_outreach(user_id: str, session_id: Optional[str]) -> Optional[dict]:
    """Fetch the latest awaiting_user_decision outreach confirmation for ``user_id``."""
    db = get_database()
    if db is None:
        return None
    now = datetime.utcnow()
    query = {
        "user_id": user_id,
        "action_type": "cross_advisor_outreach_confirmation",
        "status": "awaiting_user_decision",
        "expires_at": {"$gt": now},
    }
    if session_id:
        query["session_id"] = session_id
    return await db.advisor_pending_actions.find_one(query, sort=[("updated_at", -1)])


async def _upsert_pending_cross_advisor_outreach(
    user_id: str,
    session_id: Optional[str],
    target_user_id: str,
    target_user_hint: str,
    concern_message: str,
    advisor_response: str,
) -> None:
    """Create or update a pending outreach confirmation. Follows the pattern of _upsert_pending_task_create_action."""
    db = get_database()
    if db is None:
        return
    now = datetime.utcnow()
    expires_at = now + timedelta(hours=2)
    query = {
        "user_id": user_id,
        "session_id": session_id or "default",
        "action_type": "cross_advisor_outreach_confirmation",
        "status": "awaiting_user_decision",
    }
    await db.advisor_pending_actions.update_one(
        query,
        {
            "$set": {
                "user_id": user_id,
                "session_id": session_id or "default",
                "action_type": "cross_advisor_outreach_confirmation",
                "status": "awaiting_user_decision",
                "target_user_id": target_user_id,
                "target_user_hint": target_user_hint,
                "concern_message": concern_message,
                "advisor_response": advisor_response,
                "updated_at": now,
                "expires_at": expires_at,
            },
            "$setOnInsert": {"created_at": now},
        },
        upsert=True,
    )


async def _create_cross_advisor_pending_action(
    *,
    user_id: str,
    session_id: Optional[str],
    thread_id: str,
    source_message_id: str,
    requester_user_id: str,
    approver_user_id: str,
    resume_payload: dict,
    status: str,
    turn_count: int,
    max_turns: int = DEFAULT_MAX_CROSS_TURNS,
) -> None:
    """Insert (or upsert by thread_id) a cross-advisor pending action."""
    db = get_database()
    if db is None:
        return
    now = datetime.utcnow()
    expires_at = now + timedelta(hours=CROSS_PENDING_TTL_HOURS)
    query = {
        "user_id": user_id,
        "thread_id": thread_id,
        "action_type": CROSS_ADVISOR_ACTION_TYPE,
    }
    await db.advisor_pending_actions.update_one(
        query,
        {
            "$set": {
                "user_id": user_id,
                "session_id": session_id or "default",
                "action_type": CROSS_ADVISOR_ACTION_TYPE,
                "thread_id": thread_id,
                "source_message_id": source_message_id,
                "requester_user_id": requester_user_id,
                "approver_user_id": approver_user_id,
                "resume_payload": resume_payload,
                "status": status,
                "turn_count": turn_count,
                "max_turns": max_turns,
                "updated_at": now,
                "expires_at": expires_at,
            },
            "$setOnInsert": {"created_at": now},
        },
        upsert=True,
    )


async def _set_cross_advisor_pending_status(thread_id: str, user_id: str, new_status: str) -> None:
    db = get_database()
    if db is None:
        return
    await db.advisor_pending_actions.update_one(
        {
            "user_id": user_id,
            "thread_id": thread_id,
            "action_type": CROSS_ADVISOR_ACTION_TYPE,
        },
        {"$set": {"status": new_status, "updated_at": datetime.utcnow()}},
    )


def _collab_session_id(thread_id: str) -> str:
    """Per-user session id used for the read-only collab audit thread."""
    return f"collab:{thread_id}"


def _cross_confirm_session_id(thread_id: str) -> str:
    """Dedicated writable chat session for cross-advisor confirmation."""
    return f"cross-confirm:{thread_id}"


def _extract_labeled_value(text: str, label: str) -> str:
    """Extract `label: value` from multi-line free-form message text."""
    if not text:
        return ""
    prefix = f"{label.strip().lower()}:"
    for raw in text.splitlines():
        line = raw.strip()
        if line.lower().startswith(prefix):
            return line[len(prefix):].strip()
    return ""


async def _post_collab_audit(
    *,
    user_id: str,
    thread_id: str,
    peer_user_id: str,
    content: str,
    collab_status: str,
    role: str = "assistant",
    sender_label: Optional[str] = None,
) -> None:
    """Append a sanitized message to the user's read-only collab thread.

    Writes into the existing ``chat_messages`` collection per §13.1 with
    ``metadata.channel = "advisor_collab"``.  Callers must pass
    user-readable summaries only — no chain-of-thought, prompts, or
    credentials (§13.6).
    """
    sanitized = advisor_cross_message_service.sanitize_summary(content)
    await chat_history_service.save_message(
        user_id=user_id,
        session_id=_collab_session_id(thread_id),
        role=role,
        content=sanitized,
        metadata={
            "channel": "advisor_collab",
            "readonly": True,
            "thread_id": thread_id,
            "collab_status": collab_status,
            "peer_user_id": peer_user_id,
            "sender_label": sender_label,
        },
    )


async def _load_cross_task_details(task_id: str, owner_user_id: str) -> dict:
    """Best-effort fetch of task details to enrich cross-advisor prompts."""
    db = get_database()
    if db is None or not task_id or not owner_user_id:
        return {}
    doc = await db.tasks.find_one(
        {"task_id": task_id, "user_id": owner_user_id},
        {
            "_id": 0,
            "task_id": 1,
            "task_name": 1,
            "open_datetime": 1,
            "close_datetime": 1,
            "task_info": 1,
        },
    )
    return doc or {}


async def _extract_target_person_with_llm(message: str) -> Optional[str]:
    """Use LLM to detect if the user is mentioning another person by name/relationship.

    Returns the person's name/reference if mentioning someone else, None if talking about self.

    Examples:
    - "Did Eimer take all her medication?" → "Eimer"
    - "Emma's sleep is low" → "Emma"
    - "How is my daughter?" → "my daughter"
    - "Tell Ciline I love her" → "Ciline"
    - "What's my heart rate?" → None (self)
    """
    prompt = f"""Analyze this message and determine if the user is mentioning or talking about someone ELSE, or about themselves.

Message: "{message}"

If the user is mentioning, asking about, or addressing SOMEONE ELSE (by name, email, or relationship), respond with ONLY their name, email, or relationship descriptor (e.g., "Eimer", "Emma", "my daughter", "my son", "Ciline", "john@example.com").
If the user is talking about their own status, health, or matters, or if it's unclear, respond with: "self"

Do NOT include quotes or explanation. Just the name/email/relationship or "self"."""

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

        logger.debug(f"Extracted target person: {result} from message: {message[:50]}")
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

    # ── Step 1.6: Resume cross-advisor outreach confirmation ───────────
    pending_outreach = await _get_pending_cross_advisor_outreach(user_id, session_id)
    if pending_outreach:
        resumed = await _resume_cross_advisor_outreach_after_user_reply(
            user_id=user_id,
            session_id=session_id,
            user_message=message,
            pending=pending_outreach,
            ctx=ctx,
            enabled_caps=enabled_caps,
            history=history,
            team_id=team_id,
        )
        if resumed is not None:
            return resumed

    # ── Step 1.7: Resume cross-advisor confirmation ──────────────────────
    pending_cross = await _get_pending_cross_advisor_action(user_id, session_id)
    if pending_cross:
        resumed = await _resume_cross_advisor_after_user_reply(
            user_id=user_id,
            session_id=session_id,
            user_message=message,
            pending=pending_cross,
            ctx=ctx,
            enabled_caps=enabled_caps,
            history=history,
        )
        if resumed is not None:
            return resumed

    # ── Step 2: Retrieve top-k candidate skills ──────────────────────────
    # Score against recent user turns + the current message so a follow-up
    # reply (e.g., user supplying just a team name "Yumo Family team")
    # doesn't lose the original-intent skill from the candidate set.
    recent_user_turns = [
        h.get("content", "")
        for h in (history or [])
        if h.get("role") == "user" and h.get("content")
    ][-3:]
    retrieval_query = " ".join([*recent_user_turns, message])

    candidates = skill_registry.retrieve_top_k(
        query=retrieval_query,
        enabled_capabilities=enabled_caps,
        top_k=8,
    )

    # Mid-flow guard: while a task-create clarification is awaiting input,
    # keep tasks_create available even if the user's reply is detail-only
    # (a team name, a person, etc.) and would not match its keywords.
    if pending_task_create and not any(c.skill_id == "tasks_create" for c in candidates):
        tasks_create_skill = skill_registry.get_skill("tasks_create")
        if tasks_create_skill and tasks_create_skill.status == "indexed":
            candidates = [tasks_create_skill, *candidates[:7]]

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

        # ── Propose peer outreach (ask user if they want to reach out to peer advisor) ─
        propose_outreach = bool(tool_input.get("propose_peer_outreach", False))
        if propose_outreach and target_user_id and target_user_id != user_id:
            outreach_question = (
                f"{response_text}\n\n"
                f"Would you like me to also reach out to their advisor and share this concern with them? "
                f"(Reply **yes** or **no**)"
            )
            await _upsert_pending_cross_advisor_outreach(
                user_id=user_id,
                session_id=session_id,
                target_user_id=target_user_id,
                target_user_hint=tool_input.get("target_user_hint", ""),
                concern_message=message,
                advisor_response=response_text,
            )
            return {
                "type": "guidance",
                "reply": outreach_question,
                "reply_class": "clarification_needed",
                "is_write_operation_task": True,
            }

        # ── Cross-advisor write request branch ───────────────────────
        cross_action_raw = (tool_input.get("cross_advisor_action_type") or "none").strip()
        if cross_action_raw and cross_action_raw != "none":
            return await _initiate_cross_advisor_request(
                requester_user_id=user_id,
                session_id=session_id,
                tool_input=tool_input,
                preflight_text=response_text,
                team_id=team_id,
                message=message,
            )

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
        logger.info(f"Resolving target_user_hint: {target_user_hint} for user_id={user_id}")
        resolved_id = await _resolve_target_user_hint(
            request_user_id=user_id,
            target_user_hint=target_user_hint,
            team_id=team_id,
        )
        logger.info(f"Resolution result: {resolved_id}")
        if resolved_id:
            target_user_id = resolved_id
        else:
            logger.warning(f"Could not resolve target_user_hint: {target_user_hint}")
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


# ── Cross-advisor flow ──────────────────────────────────────────────────────

async def _initiate_cross_advisor_request(
    *,
    requester_user_id: str,
    session_id: Optional[str],
    tool_input: dict,
    preflight_text: str,
    team_id: Optional[str],
    message: str,
) -> dict:
    """B-side: open a cross-advisor thread targeting another user's advisor.

    Resolves the peer user, persists an ``action_request`` cross-message,
    seeds the read-only collab thread for B, and triggers receiver-side
    processing inline (which will post a confirmation question to A's chat
    and create an ``awaiting_user_confirm`` pending action).
    """
    cross_action = (tool_input.get("cross_advisor_action_type") or "none").strip()
    if cross_action == "none":
        return {
            "type": "direct",
            "reply": preflight_text or "I'm here to help!",
            "reply_class": "planned",
            "is_write_operation_task": True,
        }

    target_email = (tool_input.get("target_email") or "").strip()
    target_user_hint = (tool_input.get("target_user_hint") or "").strip()
    cross_action_params = tool_input.get("cross_action_params") or {}

    target_user_id: Optional[str] = None
    if target_email:
        target_user_id = await _resolve_email_to_user_id(target_email)
    elif target_user_hint:
        target_user_id = await _resolve_target_user_hint(
            request_user_id=requester_user_id,
            target_user_hint=target_user_hint,
            team_id=team_id,
        )

    if not target_user_id:
        return {
            "type": "guidance",
            "reply": (
                "I couldn't tell which person you meant. "
                "Please share their full name or email so I can route this to their advisor."
            ),
            "reply_class": "clarification_needed",
            "is_write_operation_task": True,
        }
    if target_user_id == requester_user_id:
        return {
            "type": "guidance",
            "reply": (
                "That action targets your own account, so I don't need to ask another user's advisor — "
                "let me know if you'd like me to do it directly."
            ),
            "reply_class": "clarification_needed",
            "is_write_operation_task": True,
        }

    # MVP supports tasks_complete only.
    if cross_action != CrossActionType.TASKS_COMPLETE.value:
        return {
            "type": "guidance",
            "reply": "I can only route task-completion requests across advisors right now.",
            "reply_class": "failed",
            "is_write_operation_task": True,
        }

    task_id = (cross_action_params.get("task_id") or "").strip() if isinstance(cross_action_params, dict) else ""
    if not task_id:
        return {
            "type": "guidance",
            "reply": "Which task should be marked complete? Please share the task id.",
            "reply_class": "clarification_needed",
            "is_write_operation_task": True,
        }

    # Idempotency: same requester + target + task within the open window
    # collapses to one thread.
    idempotency_key = f"tasks_complete:{requester_user_id}:{target_user_id}:{task_id}"
    task_detail = await _load_cross_task_details(task_id, requester_user_id)
    reason_fallback = _extract_labeled_value(message, "reason")
    enriched_action_params = {
        "task_id": task_id,
        "task_name": task_detail.get("task_name") or cross_action_params.get("task_name"),
        "open_datetime": task_detail.get("open_datetime") or cross_action_params.get("open_datetime"),
        "close_datetime": task_detail.get("close_datetime") or cross_action_params.get("close_datetime"),
        "reason": cross_action_params.get("reason") or reason_fallback or task_detail.get("task_info") or "",
    }

    cross_msg = await advisor_cross_message_service.create_request(
        from_user_id=requester_user_id,
        to_user_id=target_user_id,
        action_type=CrossActionType.TASKS_COMPLETE,
        action_params=enriched_action_params,
        require_confirmation=True,
        idempotency_key=idempotency_key,
    )
    thread_id = cross_msg["thread_id"]

    # Seed the requester-side collab audit thread.
    await _post_collab_audit(
        user_id=requester_user_id,
        thread_id=thread_id,
        peer_user_id=target_user_id,
        content=f"Requested mark-complete for task {task_id}. Awaiting confirmation from peer.",
        collab_status="in_progress",
    )

    # Trigger receiver-side processing inline.  Failures here are logged
    # but do not bubble up — B's user already received the synchronous
    # acknowledgement and the cross-message stays queryable for retry.
    try:
        await _process_incoming_cross_request(cross_msg)
    except Exception as exc:  # pragma: no cover — defensive
        logger.exception("cross_msg.deliver_failed thread=%s: %s", thread_id, exc)
        await advisor_cross_message_service.mark_failed(
            cross_msg["message_id"], reason=str(exc)
        )

    reply = (
        "I've passed your request to that user's advisor and asked them to confirm. "
        "I'll let you know what they decide."
    )
    return {
        "type": "direct",
        "reply": reply,
        "reply_class": "planned",
        "is_write_operation_task": True,
    }


async def _process_incoming_cross_request(message_doc: dict) -> None:
    """Receiver-side: ask the receiving user to confirm the request.

    Per §2.1 every cross-user write request requires confirmation, so for
    MVP we skip an LLM reasoning hop and post a templated question.  The
    pending action carries the resume payload that ``_resume_cross_advisor_after_user_reply``
    consumes when the user replies.
    """
    payload = message_doc.get("payload") or {}
    action_type = payload.get("action_type")
    action_params = payload.get("action_params") or {}
    thread_id = message_doc["thread_id"]
    requester_user_id = message_doc["from_user_id"]
    approver_user_id = message_doc["to_user_id"]

    # Hard termination check (§2.5).
    turn_count = await advisor_cross_message_service.count_thread_turns(thread_id)
    if turn_count > DEFAULT_MAX_CROSS_TURNS:
        await advisor_cross_message_service.mark_failed(
            message_doc["message_id"],
            reason=f"max_turns ({DEFAULT_MAX_CROSS_TURNS}) reached",
        )
        await _post_collab_audit(
            user_id=approver_user_id,
            thread_id=thread_id,
            peer_user_id=requester_user_id,
            content="Conversation closed — too many back-and-forth turns.",
            collab_status="expired",
        )
        await _post_collab_audit(
            user_id=requester_user_id,
            thread_id=thread_id,
            peer_user_id=approver_user_id,
            content="Conversation closed — too many back-and-forth turns.",
            collab_status="expired",
        )
        return

    # Build a user-facing question.  Templated for MVP (tasks_complete only).
    requester_name = await _lookup_display_name(requester_user_id)
    approver_name = await _lookup_display_name(approver_user_id)
    if action_type == CrossActionType.TASKS_COMPLETE.value:
        task_name = action_params.get("task_name") or "Unknown"
        open_time = action_params.get("open_datetime") or "Unknown"
        close_time = action_params.get("close_datetime") or "Unknown"
        reason = action_params.get("reason") or "Not provided"
        question = (
            f"**{requester_name} wants to mark \"{task_name}\" as done**\n\n"
            f"They completed it between {open_time} and {close_time} with the note: \"{reason}\"\n\n"
            "Can you approve this? (Reply **yes** or **no**)"
        )
    else:
        question = (
            f"{requester_name}'s advisor is requesting an action on your account. "
            "Reply **yes** to approve or **no** to decline."
        )
    question = advisor_cross_message_service.sanitize_summary(question, max_len=500)

    confirm_session_id = _cross_confirm_session_id(thread_id)

    # Post the question into a dedicated confirmation session so the user replies there.
    await chat_history_service.save_message(
        user_id=approver_user_id,
        session_id=confirm_session_id,
        role="assistant",
        content=question,
        metadata={
            "type": "cross_advisor_confirmation",
            "thread_id": thread_id,
            "peer_user_id": requester_user_id,
        },
    )

    # Mirror into the receiver-side collab audit thread.
    await _post_collab_audit(
        user_id=approver_user_id,
        thread_id=thread_id,
        peer_user_id=requester_user_id,
        content=question,
        collab_status="waiting_user_confirm",
        role="user",
        sender_label=f"{requester_name}'s advisor",
    )

    # Persist the pending action so handle_chat can resume on the next reply.
    await _create_cross_advisor_pending_action(
        user_id=approver_user_id,
        session_id=confirm_session_id,
        thread_id=thread_id,
        source_message_id=message_doc["message_id"],
        requester_user_id=requester_user_id,
        approver_user_id=approver_user_id,
        resume_payload={
            "action_type": action_type,
            "action_params": action_params,
            "question_to_user": question,
        },
        status=CrossAdvisorPendingActionStatus.AWAITING_USER_CONFIRM.value,
        turn_count=turn_count,
    )

    await advisor_cross_message_service.mark_processed(message_doc["message_id"])


async def _resume_cross_advisor_after_user_reply(
    *,
    user_id: str,
    session_id: Optional[str],
    user_message: str,
    pending: dict,
    ctx: dict,
    enabled_caps: set[str],
    history: list[dict],
) -> Optional[dict]:
    """Consume an awaiting_user_confirm pending action.

    Returns a chat response dict if the reply mapped to approve/reject, or
    ``None`` to fall through to the normal LLM routing (treated as
    ``ask_more`` clarification).
    """
    decision = _classify_user_confirmation(user_message)
    if decision == "ask_more":
        return None

    thread_id = pending["thread_id"]
    requester_user_id = pending["requester_user_id"]
    approver_user_id = pending["approver_user_id"]
    resume_payload = pending.get("resume_payload") or {}
    action_type = resume_payload.get("action_type")
    action_params = resume_payload.get("action_params") or {}
    approver_name = await _lookup_display_name(approver_user_id)

    if decision == "reject":
        await _set_cross_advisor_pending_status(
            thread_id, user_id, CrossAdvisorPendingActionStatus.REJECTED.value
        )
        await advisor_cross_message_service.create_decision_reply(
            thread_id=thread_id,
            from_user_id=approver_user_id,
            to_user_id=requester_user_id,
            decision="reject",
            summary="User declined the request.",
        )
        await _post_collab_audit(
            user_id=approver_user_id,
            thread_id=thread_id,
            peer_user_id=requester_user_id,
            content="No",
            collab_status="done",
            role="user",
            sender_label=approver_name,
        )
        await _post_collab_audit(
            user_id=requester_user_id,
            thread_id=thread_id,
            peer_user_id=approver_user_id,
            content="The peer declined the request.",
            collab_status="done",
        )
        await _set_cross_advisor_pending_status(
            thread_id, user_id, CrossAdvisorPendingActionStatus.CONSUMED.value
        )
        return {
            "type": "direct",
            "reply": "Understood — I let them know you declined.",
            "reply_class": "planned",
            "is_write_operation_task": False,
        }

    # Decision == approve → mark approved, run skill execution.
    await _set_cross_advisor_pending_status(
        thread_id, user_id, CrossAdvisorPendingActionStatus.APPROVED.value
    )
    await advisor_cross_message_service.create_decision_reply(
        thread_id=thread_id,
        from_user_id=approver_user_id,
        to_user_id=requester_user_id,
        decision="approve",
        summary="User approved.",
    )
    await _post_collab_audit(
        user_id=approver_user_id,
        thread_id=thread_id,
        peer_user_id=requester_user_id,
        content=f"{approver_name} approved.",
        collab_status="in_progress",
        role="user",
        sender_label=approver_name,
    )

    if action_type != CrossActionType.TASKS_COMPLETE.value:
        # Should not happen in MVP — only tasks_complete is wired up.
        await _set_cross_advisor_pending_status(
            thread_id, user_id, CrossAdvisorPendingActionStatus.CONSUMED.value
        )
        return {
            "type": "guidance",
            "reply": "Approved, but I don't have a way to execute that action yet.",
            "reply_class": "failed",
            "is_write_operation_task": True,
        }

    # Build execution prompt for the tasks_complete skill.
    task_id = action_params.get("task_id", "")
    skill = skill_registry.get_skill("tasks_complete")
    if not skill or skill.status != "indexed":
        await _set_cross_advisor_pending_status(
            thread_id, user_id, CrossAdvisorPendingActionStatus.CONSUMED.value
        )
        await advisor_cross_message_service.create_execution_result(
            thread_id=thread_id,
            from_user_id=approver_user_id,
            to_user_id=requester_user_id,
            success=False,
            summary="tasks_complete skill is not available.",
        )
        return {
            "type": "guidance",
            "reply": "I approved this, but the task-completion skill is unavailable right now.",
            "reply_class": "failed",
            "is_write_operation_task": True,
        }
    if skill.capability_id not in enabled_caps:
        # Auto-enable for the approver since they own the data.
        await capability_service.toggle_capability(user_id, skill.capability_id, True)
        enabled_caps = enabled_caps | {skill.capability_id}

    skill_full_text = skill_registry.load_skill_full_text("tasks_complete")
    credential = None
    if skill.requires_credentials or skill.requires_ping:
        cred_key = resolve_credential_key(skill)
        credential = await skill_credential_service.get_credential(user_id, cred_key)
        if not credential and skill.capability_id == "lumie_internal_data" and skill.requires_ping:
            credential = await skill_credential_service.ensure_lumie_internal_credential(
                user_id, skill.skill_id
            )

    execution_prompt = (
        f"Mark task {task_id} as complete. "
        f"This was approved by the task owner in response to a cross-advisor request."
    )

    job_id = await execution_service.create_execution_job(
        user_id=user_id,
        session_id=session_id,
        skill=skill,
        prompt=execution_prompt,
        target_user_id=requester_user_id,  # complete the requester's task
        team_id=None,
        is_write_operation_task=True,
        cross_advisor_context={
            "thread_id": thread_id,
            "source_message_id": pending["source_message_id"],
            "requester_user_id": requester_user_id,
            "approver_user_id": approver_user_id,
            "action_type": action_type,
            "action_params": action_params,
        },
    )

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

    await _set_cross_advisor_pending_status(
        thread_id, user_id, CrossAdvisorPendingActionStatus.CONSUMED.value
    )
    return {
        "type": "execution",
        "reply": "Approved — running the task completion now. I'll share the result.",
        "reply_class": "planned",
        "is_write_operation_task": True,
        "job_id": job_id,
        "skill_id": "tasks_complete",
        "status": "pending",
    }


async def _resume_cross_advisor_outreach_after_user_reply(
    *,
    user_id: str,
    session_id: Optional[str],
    user_message: str,
    pending: dict,
    ctx: dict,
    enabled_caps: set[str],
    history: list[dict],
    team_id: Optional[str] = None,
) -> Optional[dict]:
    """User decides whether to send concern to another user's advisor.

    If yes: initiate cross-advisor request with the concern message.
    If no: acknowledge and provide the advisor's response normally.
    If ask_more: stay pending for more clarification.
    """
    decision = _classify_user_confirmation(user_message)
    if decision == "ask_more":
        return None

    thread_id = pending["thread_id"]
    target_user_id = pending["target_user_id"]
    concern_message = pending["concern_message"]
    advisor_response = pending["advisor_response"]

    if decision == "reject":
        db = get_database()
        if db:
            await db.advisor_pending_actions.update_one(
                {
                    "user_id": user_id,
                    "thread_id": thread_id,
                    "action_type": CROSS_ADVISOR_OUTREACH_TYPE,
                },
                {"$set": {"status": "declined", "updated_at": datetime.utcnow()}},
            )
        return {
            "type": "direct",
            "reply": f"Understood. {advisor_response}",
            "reply_class": "planned",
            "is_write_operation_task": False,
        }

    # Decision == approve → initiate cross-advisor message
    db = get_database()
    if db:
        await db.advisor_pending_actions.update_one(
            {
                "user_id": user_id,
                "thread_id": thread_id,
                "action_type": CROSS_ADVISOR_OUTREACH_TYPE,
            },
            {"$set": {"status": "approved", "updated_at": datetime.utcnow()}},
        )

    # Initiate cross-advisor request
    idempotency_key = f"health_concern:{user_id}:{target_user_id}"
    cross_msg = await advisor_cross_message_service.create_request(
        from_user_id=user_id,
        to_user_id=target_user_id,
        action_type=CrossActionType.TASKS_COMPLETE,  # Reuse for general coordination
        action_params={
            "concern_type": "health_advice",
            "message": concern_message,
            "advisor_context": advisor_response,
        },
        require_confirmation=True,
        idempotency_key=idempotency_key,
    )
    cross_thread_id = cross_msg["thread_id"]

    # Seed collab audit
    await _post_collab_audit(
        user_id=user_id,
        thread_id=cross_thread_id,
        peer_user_id=target_user_id,
        content=f"Shared health concern with scientific advice. Awaiting peer's advisor confirmation.",
        collab_status="in_progress",
    )

    # Trigger receiver-side processing
    try:
        await _process_incoming_cross_health_concern(cross_msg, ctx)
    except Exception as exc:
        logger.exception("cross health_concern.deliver_failed thread=%s: %s", cross_thread_id, exc)
        await advisor_cross_message_service.mark_failed(
            cross_msg["message_id"], reason=str(exc)
        )

    return {
        "type": "direct",
        "reply": f"{advisor_response}\n\nI'm reaching out to their advisor now to share this concern. They'll review it and get back to us.",
        "reply_class": "planned",
        "is_write_operation_task": True,
    }


async def _process_incoming_cross_health_concern(message_doc: dict, requester_ctx: dict) -> None:
    """Receiver-side: notify the receiving user's advisor about a health concern.

    A peer (parent/advisor) has shared a health concern about the receiving user.
    Post this to the receiving user's advisor chat in a read-only audit thread,
    and ask them to acknowledge receipt and decide if action is needed.
    """
    payload = message_doc.get("payload") or {}
    action_params = payload.get("action_params") or {}
    thread_id = message_doc["thread_id"]
    requester_user_id = message_doc["from_user_id"]
    receiver_user_id = message_doc["to_user_id"]

    requester_name = await _lookup_display_name(requester_user_id)
    receiver_name = await _lookup_display_name(receiver_user_id)

    concern_message = action_params.get("message") or "A health concern was shared"
    advisor_context = action_params.get("advisor_context") or ""

    # Build user-facing notification
    question = (
        f"**{requester_name} shared a health concern about {receiver_name}:**\n\n"
        f"{concern_message}\n\n"
        f"**Advisor guidance shared:** {advisor_context}\n\n"
        f"Reply with any follow-up actions or observations."
    )
    question = advisor_cross_message_service.sanitize_summary(question, max_len=600)

    confirm_session_id = _cross_confirm_session_id(thread_id)

    # Post to receiver's confirmation session
    await chat_history_service.save_message(
        user_id=receiver_user_id,
        session_id=confirm_session_id,
        role="assistant",
        content=question,
        metadata={
            "type": "cross_advisor_health_concern",
            "thread_id": thread_id,
            "peer_user_id": requester_user_id,
        },
    )

    # Mirror to collab audit thread
    await _post_collab_audit(
        user_id=receiver_user_id,
        thread_id=thread_id,
        peer_user_id=requester_user_id,
        content=question,
        collab_status="waiting_user_respond",
        role="user",
        sender_label=f"{requester_name}'s advisor",
    )

    # Persist pending action for receiving side (using standard cross-advisor action type)
    await _create_cross_advisor_pending_action(
        user_id=receiver_user_id,
        session_id=confirm_session_id,
        thread_id=thread_id,
        source_message_id=message_doc["message_id"],
        requester_user_id=requester_user_id,
        approver_user_id=receiver_user_id,
        resume_payload={
            "concern_type": "health_advice",
            "concern_message": concern_message,
            "advisor_context": advisor_context,
            "question_to_user": question,
        },
        status=CrossAdvisorPendingActionStatus.AWAITING_USER_CONFIRM.value,
        turn_count=0,
    )

    await advisor_cross_message_service.mark_processed(message_doc["message_id"])


async def _lookup_display_name(user_id: str) -> str:
    """Best-effort name lookup for templated questions / audit messages."""
    try:
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id}, {"name": 1, "_id": 0})
        if profile and profile.get("name"):
            return profile["name"]
        user = await db.users.find_one({"user_id": user_id}, {"email": 1, "_id": 0})
        if user and user.get("email"):
            return user["email"]
    except Exception:
        pass
    return "Another user"


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
                "cross_advisor_action_type": {
                    "type": "string",
                    "enum": ["none", "tasks_complete"],
                    "description": (
                        "Set to 'tasks_complete' ONLY when the user wants to perform a "
                        "WRITE action on ANOTHER user's data (e.g. mark another user's task "
                        "complete). The receiving user must confirm. Use 'none' for self-actions "
                        "or read-only queries about another user."
                    ),
                },
                "cross_action_params": {
                    "type": "object",
                    "description": (
                        "Parameters for the cross-advisor action. For tasks_complete, MUST "
                        "include task_id (string). Also include task_name/open_datetime/"
                        "close_datetime/reason when present in the user message. Empty object "
                        "when cross_advisor_action_type='none'."
                    ),
                    "properties": {
                        "task_id": {"type": "string", "description": "Target task id."},
                        "task_name": {"type": "string", "description": "Task display name, if provided."},
                        "open_datetime": {"type": "string", "description": "Task open time, if provided."},
                        "close_datetime": {"type": "string", "description": "Task close time, if provided."},
                        "reason": {"type": "string", "description": "Why requester asks for completion."},
                    },
                },
                "propose_peer_outreach": {
                    "type": "boolean",
                    "description": (
                        "Set to true when the user expressed concern/worry about another person's health "
                        "and you'd like to offer reaching out to their advisor. Example: user says 'I'm worried "
                        "about Emma's sleep' — you give advice, then ask 'Would you like me to reach out to her "
                        "advisor?' This creates a confirmation prompt before initiating cross-advisor contact."
                    ),
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

**When another person is mentioned** (by name, relationship, or email):
1. Always set the appropriate `target_user_hint` or `target_email`
2. Consider whether this is a health concern → if yes, set `propose_peer_outreach=true` and provide advice
3. If it's a write action (marking task complete), use cross-advisor routing instead
4. The system will auto-detect family/team relationships and resolve who you mean

Protocol contract:
- `reply_class` must be one of: `clarification_needed`, `planned`, `executed`, `failed`.
- You must set `is_write_operation_task` as a boolean judgment in this first call.
- Only `reply_class=executed` may contain completion claims such as "I created", "I updated", "I sent".
- If execution has not happened yet, use `planned` or `clarification_needed`.

**Set `should_execute_skill=true` when:**
- The user asks a question that requires querying their personal data
- The user asks about their activity, sleep, tasks, medication schedule, health trends
- The user wants to ADD, CREATE, or SET a new task or reminder (their own)
- The user asks about school homework, email, or anything requiring external system access
- Choose the most relevant skill from the available candidates
- If the user mentions another person by email (e.g., "check tasks of alice@example.com"), set `target_email` to that email so we query that person's data instead of the requester's
- If the user refers to another person without an email (e.g., "my daughter", "my son", "my child", or a team member's name like "Eimer"), set `target_user_hint` to that exact phrase or name. **Do NOT ask for confirmation — just pass it to the skill and let it look up the person in your teams.**

**Use cross-advisor routing when:**
- The user wants to take a WRITE action on ANOTHER person's data (e.g., mark their task complete, confirm their action)
- The user wants to SEND A MESSAGE or COMMUNICATE something to another user through their advisor
- This is the coordination mechanism — the receiving user must confirm before the action proceeds
- Set `cross_advisor_action_type` to `"tasks_complete"` and populate `cross_action_params` with the intent

**Propose peer outreach (`propose_peer_outreach=true`) when:**
- The user expresses **worry, concern, or observation** about another person's health (e.g., "I'm worried about Emma's sleep", "Eimer seems anxious lately")
- You provide relevant health advice or guidance in your response
- AND you want to offer reaching out to that person's advisor so they can help directly
- Your response should acknowledge the concern, provide advice, THEN ask "Would you like me to reach out to their advisor?"
- Set both `target_user_hint`/`target_email` (to identify the person) AND `propose_peer_outreach=true`
- Do NOT set this if the user is asking about their own health — only for concerns about others

**Set `should_execute_skill=false` when:**
- General health advice or tips
- Greetings, small talk, emotional support
- Medical knowledge questions
- Questions you can answer without data access

**Cross-advisor write requests (`cross_advisor_action_type`):**
- Default to `"none"`.
- **When another person is involved in a write action (not just a read/query)**, use cross-advisor routing.
  This is the mechanism for coordinating between users. Examples:
  - "mark Eimer's task xxxxx complete" → `"tasks_complete"`
  - "tell Mom's advisor that Emma took her medication" → `"tasks_complete"`
  - "let her know..." or "forward a message to..." about another user → `"tasks_complete"` (brief message in the context)
- When set to `"tasks_complete"`, populate `cross_action_params` with available context:
  - `task_id` (required if it's a task action)
  - `task_name`, `reason`, or the core message intent
  - Set `target_user_hint` (or `target_email`) to identify the peer user
- Do NOT use cross-advisor routing for the user's own data — use the regular skill flow.

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

    candidate_user_ids: set[str] = set()

    # Strategy 1: Search teams the requester administers
    team_query: dict = {
        "user_id": request_user_id,
        "role": "admin",
        "status": "member",
    }
    if team_id:
        team_query["team_id"] = team_id

    admin_memberships = await db.team_members.find(team_query).to_list(length=50)
    if admin_memberships:
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

    # Strategy 2: Fallback to all team members of all teams the requester belongs to
    if not candidate_user_ids:
        try:
            # Find all teams the requester belongs to (any role, any status)
            all_user_teams = await db.team_members.find({
                "user_id": request_user_id,
                "status": "member",
            }).to_list(length=100)

            if all_user_teams:
                team_ids = [m["team_id"] for m in all_user_teams]
                # Get all members of those teams
                team_members = await db.team_members.find({
                    "team_id": {"$in": team_ids},
                    "status": "member",
                }).to_list(length=500)

                candidate_user_ids = {
                    m["user_id"]
                    for m in team_members
                    if m.get("user_id") != request_user_id
                }

                if candidate_user_ids:
                    logger.info(f"Team member search: hint='{hint}' found {len(candidate_user_ids)} candidate(s) from {len(team_ids)} team(s)")
        except Exception as e:
            logger.warning(f"Team member search failed: {e}")

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
