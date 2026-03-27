"""Skill Credential Service — manages per-user credentials for skills.

Stores base_url, username, password, ping, and notes.
Phase 1: plain-text storage is allowed.
"""
import logging
import secrets
from datetime import datetime
from typing import Optional

from ..core.database import get_database

logger = logging.getLogger(__name__)


async def get_credential(user_id: str, skill_id: str) -> Optional[dict]:
    """Get the credential record for a user+skill pair. Returns None if not found."""
    db = get_database()
    cred = await db.advisor_skill_credentials.find_one(
        {"user_id": user_id, "skill_id": skill_id},
        {"_id": 0},
    )
    return cred


async def save_credential(
    user_id: str,
    skill_id: str,
    data: dict,
) -> dict:
    """Create or update a credential for a user+skill pair.

    `data` may contain: system_name, base_url, username, password, notes.
    Returns the saved credential (without password in plain response).
    """
    db = get_database()
    now = datetime.utcnow().isoformat()

    update_fields = {
        "status": "saved_not_tested",
        "updated_at": now,
    }
    for field_name in ("system_name", "base_url", "username", "password", "notes"):
        if field_name in data and data[field_name] is not None:
            update_fields[field_name] = data[field_name]

    result = await db.advisor_skill_credentials.find_one_and_update(
        {"user_id": user_id, "skill_id": skill_id},
        {
            "$set": update_fields,
            "$setOnInsert": {
                "credential_id": f"cred_{skill_id}_{user_id}",
                "user_id": user_id,
                "skill_id": skill_id,
                "ping": None,
                "created_at": now,
            },
        },
        upsert=True,
        return_document=True,
    )

    # Strip MongoDB _id
    if result:
        result.pop("_id", None)
    return result


async def ensure_lumie_internal_credential(user_id: str, skill_id: str) -> dict:
    """Ensure a Lumie internal skill credential exists with a valid ping.

    Auto-generates a ping if one doesn't exist. This is called automatically
    when a lumie_internal_data capability is enabled.
    """
    db = get_database()
    now = datetime.utcnow().isoformat()

    existing = await db.advisor_skill_credentials.find_one(
        {"user_id": user_id, "skill_id": skill_id}
    )

    if existing and existing.get("ping"):
        # Already has a ping
        if existing.get("status") != "valid":
            await db.advisor_skill_credentials.update_one(
                {"user_id": user_id, "skill_id": skill_id},
                {"$set": {"status": "valid", "updated_at": now}},
            )
        existing.pop("_id", None)
        return existing

    # Generate a new ping token
    ping = secrets.token_hex(16)

    result = await db.advisor_skill_credentials.find_one_and_update(
        {"user_id": user_id, "skill_id": skill_id},
        {
            "$set": {
                "ping": ping,
                "status": "valid",
                "system_name": "Lumie Internal Access",
                "updated_at": now,
            },
            "$setOnInsert": {
                "credential_id": f"cred_{skill_id}_{user_id}",
                "user_id": user_id,
                "skill_id": skill_id,
                "base_url": None,
                "username": None,
                "password": None,
                "notes": "internal access only",
                "created_at": now,
            },
        },
        upsert=True,
        return_document=True,
    )
    if result:
        result.pop("_id", None)
    logger.info(f"Created Lumie internal credential for user={user_id}, skill={skill_id}")
    return result


async def validate_ping(user_id: str, skill_id: str, ping: str) -> bool:
    """Validate that a ping matches the stored credential."""
    db = get_database()
    cred = await db.advisor_skill_credentials.find_one({
        "user_id": user_id,
        "skill_id": skill_id,
        "ping": ping,
        "status": "valid",
    })
    return cred is not None


async def update_credential_status(
    user_id: str,
    skill_id: str,
    status: str,
    test_result: Optional[str] = None,
) -> None:
    """Update the credential status after a test."""
    db = get_database()
    now = datetime.utcnow().isoformat()
    update = {"status": status, "updated_at": now}
    if test_result:
        update["last_tested_at"] = now
        update["last_test_result"] = test_result
    await db.advisor_skill_credentials.update_one(
        {"user_id": user_id, "skill_id": skill_id},
        {"$set": update},
    )


async def delete_credential(user_id: str, skill_id: str) -> bool:
    """Delete a credential record."""
    db = get_database()
    result = await db.advisor_skill_credentials.delete_one(
        {"user_id": user_id, "skill_id": skill_id}
    )
    return result.deleted_count > 0


def sanitize_credential_for_response(cred: dict) -> dict:
    """Strip sensitive fields before returning to the frontend."""
    if not cred:
        return {}
    return {
        "credential_id": cred.get("credential_id", ""),
        "user_id": cred.get("user_id", ""),
        "skill_id": cred.get("skill_id", ""),
        "status": cred.get("status", "missing"),
        "system_name": cred.get("system_name"),
        "base_url": cred.get("base_url"),
        "username": cred.get("username"),
        "has_password": bool(cred.get("password")),
        "has_ping": bool(cred.get("ping")),
        "notes": cred.get("notes"),
        "last_tested_at": cred.get("last_tested_at"),
        "last_test_result": cred.get("last_test_result"),
        "created_at": cred.get("created_at", ""),
        "updated_at": cred.get("updated_at", ""),
    }
