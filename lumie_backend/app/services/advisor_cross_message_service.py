"""Advisor <-> advisor cross-user messaging service (MVP).

Owns the lifecycle of ``advisor_cross_messages`` documents — creation,
delivery, status transitions, and thread queries — for the foundational
advisor-to-advisor communication mechanism described in
``docs/advisor_cross_advisor_pending_action_design.en.md``.

There is **no public HTTP endpoint** for cross-advisor messaging.  All
callers are internal services (the orchestrator, the execution service).

State machine (see §5.1):

    queued -> delivered -> processed
    queued|delivered -> expired   (timeout)
    *       -> failed             (error path)
"""

import logging
import uuid
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any

from ..core.database import get_database
from ..core.datetime_utils import format_utc_datetime
from ..models.advisor_cross_message import (
    CrossMessageStatus,
    CrossMessageType,
    CrossActionType,
)

logger = logging.getLogger(__name__)


_TERMINAL_STATUSES = {
    CrossMessageStatus.PROCESSED.value,
    CrossMessageStatus.FAILED.value,
    CrossMessageStatus.EXPIRED.value,
}

_DEFAULT_THREAD_TTL_HOURS = 24


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _new_message_id() -> str:
    return str(uuid.uuid4())


def new_thread_id() -> str:
    """Allocate a new thread_id for a brand-new advisor-to-advisor conversation."""
    return str(uuid.uuid4())


async def _insert(doc: Dict[str, Any]) -> None:
    db = get_database()
    await db.advisor_cross_messages.insert_one(doc)


async def create_request(
    *,
    from_user_id: str,
    to_user_id: str,
    action_type: CrossActionType,
    action_params: Dict[str, Any],
    thread_id: Optional[str] = None,
    require_confirmation: bool = True,
    idempotency_key: Optional[str] = None,
    ttl_hours: int = _DEFAULT_THREAD_TTL_HOURS,
) -> Dict[str, Any]:
    """Create a new ``action_request`` and immediately mark it ``delivered``.

    Per §6.1 there is no public initiation endpoint, so the producer
    (orchestrator) and consumer (orchestrator on the other side) live in
    the same process — there is no separate delivery worker, and we mark
    delivered inline so the receiver can pick it up directly.
    """
    db = get_database()

    if idempotency_key:
        existing = await db.advisor_cross_messages.find_one(
            {"idempotency_key": idempotency_key}, {"_id": 0}
        )
        if existing:
            return existing

    now = _now()
    expires_at = now + timedelta(hours=ttl_hours)
    doc = {
        "message_id": _new_message_id(),
        "thread_id": thread_id or new_thread_id(),
        "from_user_id": from_user_id,
        "to_user_id": to_user_id,
        "from_advisor_id": "default",
        "to_advisor_id": "default",
        "message_type": CrossMessageType.ACTION_REQUEST.value,
        "payload": {
            "action_type": action_type.value if isinstance(action_type, CrossActionType) else action_type,
            "action_params": action_params or {},
            "require_confirmation": require_confirmation,
        },
        "status": CrossMessageStatus.DELIVERED.value,
        "idempotency_key": idempotency_key,
        "created_at": format_utc_datetime(now),
        "updated_at": format_utc_datetime(now),
        "expires_at": format_utc_datetime(expires_at),
    }
    await _insert(doc)
    logger.info(
        "cross_msg.create_request thread=%s from=%s to=%s action=%s",
        doc["thread_id"], from_user_id, to_user_id, doc["payload"]["action_type"],
    )
    return doc


async def create_decision_reply(
    *,
    thread_id: str,
    from_user_id: str,
    to_user_id: str,
    decision: str,
    summary: Optional[str] = None,
) -> Dict[str, Any]:
    """Receiver advisor replies to a request with an approve/reject/clarify decision."""
    if decision not in {"approve", "reject", "ask_more"}:
        raise ValueError(f"invalid decision: {decision}")

    now = _now()
    doc = {
        "message_id": _new_message_id(),
        "thread_id": thread_id,
        "from_user_id": from_user_id,
        "to_user_id": to_user_id,
        "from_advisor_id": "default",
        "to_advisor_id": "default",
        "message_type": CrossMessageType.DECISION_REPLY.value,
        "payload": {
            "decision": decision,
            "summary": summary,
        },
        "status": CrossMessageStatus.DELIVERED.value,
        "created_at": format_utc_datetime(now),
        "updated_at": format_utc_datetime(now),
    }
    await _insert(doc)
    logger.info(
        "cross_msg.decision_reply thread=%s decision=%s", thread_id, decision
    )
    return doc


async def create_execution_result(
    *,
    thread_id: str,
    from_user_id: str,
    to_user_id: str,
    success: bool,
    summary: str,
    detail: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Receiver advisor reports execution outcome back into the thread."""
    now = _now()
    doc = {
        "message_id": _new_message_id(),
        "thread_id": thread_id,
        "from_user_id": from_user_id,
        "to_user_id": to_user_id,
        "from_advisor_id": "default",
        "to_advisor_id": "default",
        "message_type": CrossMessageType.EXECUTION_RESULT.value,
        "payload": {
            "execution_result": {
                "success": success,
                "summary": summary,
                "detail": detail or {},
            },
            "summary": summary,
        },
        "status": CrossMessageStatus.PROCESSED.value,
        "created_at": format_utc_datetime(now),
        "updated_at": format_utc_datetime(now),
    }
    await _insert(doc)
    logger.info(
        "cross_msg.execution_result thread=%s success=%s", thread_id, success
    )
    return doc


async def transition_status(message_id: str, new_status: CrossMessageStatus) -> None:
    """Move a message to a new status; rejects illegal transitions."""
    db = get_database()
    current = await db.advisor_cross_messages.find_one(
        {"message_id": message_id}, {"_id": 0, "status": 1}
    )
    if not current:
        raise ValueError(f"message {message_id} not found")
    if current["status"] in _TERMINAL_STATUSES and new_status.value != current["status"]:
        raise ValueError(
            f"cannot transition message {message_id} from terminal {current['status']} to {new_status.value}"
        )
    await db.advisor_cross_messages.update_one(
        {"message_id": message_id},
        {"$set": {"status": new_status.value, "updated_at": format_utc_datetime(_now())}},
    )


async def mark_processed(message_id: str) -> None:
    await transition_status(message_id, CrossMessageStatus.PROCESSED)


async def mark_failed(message_id: str, reason: str) -> None:
    db = get_database()
    await db.advisor_cross_messages.update_one(
        {"message_id": message_id},
        {"$set": {
            "status": CrossMessageStatus.FAILED.value,
            "failure_reason": reason,
            "updated_at": format_utc_datetime(_now()),
        }},
    )


async def get_message(message_id: str) -> Optional[Dict[str, Any]]:
    db = get_database()
    return await db.advisor_cross_messages.find_one(
        {"message_id": message_id}, {"_id": 0}
    )


async def get_thread(thread_id: str) -> list[Dict[str, Any]]:
    db = get_database()
    cursor = db.advisor_cross_messages.find(
        {"thread_id": thread_id}, {"_id": 0}
    ).sort("created_at", 1)
    return await cursor.to_list(length=200)


async def count_thread_turns(thread_id: str) -> int:
    """Count action_request messages — one per requester turn."""
    db = get_database()
    return await db.advisor_cross_messages.count_documents(
        {"thread_id": thread_id, "message_type": CrossMessageType.ACTION_REQUEST.value}
    )


def sanitize_summary(text: str, max_len: int = 500) -> str:
    """Strip newlines and clip to ``max_len`` for collab-thread display.

    Per §13.6, collab threads must not contain LLM chain-of-thought, full
    internal prompts, or sensitive tokens.  Callers are responsible for
    not passing such content; this helper just enforces a hard length cap
    and collapses whitespace.
    """
    if not text:
        return ""
    collapsed = " ".join(text.split())
    if len(collapsed) > max_len:
        return collapsed[: max_len - 1] + "…"
    return collapsed
