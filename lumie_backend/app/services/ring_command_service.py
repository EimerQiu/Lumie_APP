"""Service for ring live command round-trip.

Flow:
  1. Advisor skill inserts a doc into ring_command_requests (status=pending).
  2. Skill inserts a push notification into notification_queue (type=ring_command).
  3. Flutter polls GET /ring/command/pending, gets the request, executes BLE.
  4. Flutter posts result to POST /ring/command/{id}/result.
  5. Advisor skill polls the doc until status=completed (up to 35 s).
"""

import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from ..core.database import get_database

logger = logging.getLogger(__name__)


async def create_command(
    user_id: str,
    command_type: str,
    duration_seconds: int = 10,
) -> str:
    """Insert a pending command and queue the push notification.

    Returns the request_id so the caller can poll for results.
    """
    db = get_database()
    request_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    await db.ring_command_requests.insert_one({
        "request_id": request_id,
        "user_id": user_id,
        "command_type": command_type,
        "duration_seconds": duration_seconds,
        "status": "pending",
        "created_at": now,
        "result": None,
        "completed_at": None,
    })

    # Queue push notification so the phone wakes up and polls
    await db.notification_queue.insert_one({
        "notification_id": str(uuid.uuid4()),
        "type": "ring_command",
        "recipient_user_id": user_id,
        "title": "Lumie Ring",
        "body": "Taking a live reading from your ring...",
        "data": {
            "type": "ring_command",
            "request_id": request_id,
            "command_type": command_type,
        },
        "status": "pending",
        "created_at": now,
        "sent_at": None,
    })

    logger.info(f"[RingCommand] Created {command_type} request {request_id} for user {user_id}")
    return request_id


async def get_pending_command(user_id: str) -> Optional[dict]:
    """Return the oldest pending command for this user, or None."""
    db = get_database()
    return await db.ring_command_requests.find_one(
        {"user_id": user_id, "status": "pending"},
        sort=[("created_at", 1)],
    )


async def store_result(
    request_id: str,
    user_id: str,
    success: bool,
    data: dict,
    error: Optional[str] = None,
) -> bool:
    """Mark a command as completed and store its result.

    Returns True if the document was found and updated.
    """
    db = get_database()
    result = await db.ring_command_requests.update_one(
        {"request_id": request_id, "user_id": user_id, "status": "pending"},
        {"$set": {
            "status": "completed" if success else "failed",
            "result": data,
            "error": error,
            "completed_at": datetime.now(timezone.utc).isoformat(),
        }},
    )
    return result.modified_count > 0


async def get_result(request_id: str, user_id: str) -> Optional[dict]:
    """Fetch a command document (for advisor skill polling)."""
    db = get_database()
    return await db.ring_command_requests.find_one(
        {"request_id": request_id, "user_id": user_id},
    )
