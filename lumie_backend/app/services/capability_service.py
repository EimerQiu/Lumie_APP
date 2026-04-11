"""Capability service — manages system capabilities and per-user capability state.

Capabilities gate which categories of skills Advisor can invoke.
"""
import logging
from datetime import datetime
from typing import Optional

from ..core.database import get_database
from ..core.datetime_utils import format_utc_datetime, format_utc_datetime_with_ms

logger = logging.getLogger(__name__)

# ── System-level capability definitions (seeded on startup) ──────────────────

SYSTEM_CAPABILITIES = [
    {
        "capability_id": "lumie_internal_data",
        "display_name": "Lumie Internal Data",
        "description": "Allow Advisor to access Lumie's own data (activities, tasks, sleep, walk tests) for this user",
        "enabled": True,
    },
    {
        "capability_id": "browser_portal_access",
        "display_name": "Browser Portal Access",
        "description": "Allow Advisor to log into websites (school portals, health platforms) using stored credentials",
        "enabled": True,
    },
    {
        "capability_id": "email_read",
        "display_name": "Email Read",
        "description": "Allow Advisor to search and read emails using stored email credentials",
        "enabled": True,
    },
    {
        "capability_id": "web_read",
        "display_name": "Web Read",
        "description": "Allow Advisor to read public web pages to answer questions",
        "enabled": True,
    },
    {
        "capability_id": "home_energy_access",
        "display_name": "Home Energy",
        "description": "Allow Advisor to read real-time home energy data (solar, Powerwall, Tesla, AC, temperatures)",
        "enabled": True,
    },
]


async def seed_system_capabilities() -> None:
    """Ensure all system capabilities exist in the database. Idempotent."""
    db = get_database()
    now = format_utc_datetime(datetime.utcnow())
    for cap in SYSTEM_CAPABILITIES:
        await db.advisor_capabilities.update_one(
            {"capability_id": cap["capability_id"]},
            {"$setOnInsert": {**cap, "created_at": now, "updated_at": now}},
            upsert=True,
        )
    logger.info("System capabilities seeded")


async def get_all_capabilities() -> list[dict]:
    """Return all system-level capabilities."""
    db = get_database()
    caps = await db.advisor_capabilities.find(
        {}, {"_id": 0}
    ).to_list(length=100)
    return caps


async def get_user_capabilities(user_id: str) -> list[dict]:
    """Return all capabilities with the user's enabled/ready state merged in."""
    db = get_database()

    system_caps = await get_all_capabilities()
    user_caps_cursor = db.user_advisor_capabilities.find(
        {"user_id": user_id}, {"_id": 0}
    )
    user_caps = {uc["capability_id"]: uc async for uc in user_caps_cursor}

    result = []
    for cap in system_caps:
        cid = cap["capability_id"]
        user_state = user_caps.get(cid)
        status = user_state["status"] if user_state else "disabled"
        result.append({
            **cap,
            "status": status,
            "granted_at": user_state.get("granted_at") if user_state else None,
        })
    return result


async def get_user_enabled_capability_ids(user_id: str) -> set[str]:
    """Return the set of capability_ids the user has in 'ready' or 'enabled_not_ready' state."""
    db = get_database()
    cursor = db.user_advisor_capabilities.find(
        {"user_id": user_id, "status": {"$in": ["ready", "enabled_not_ready"]}},
        {"capability_id": 1, "_id": 0},
    )
    return {doc["capability_id"] async for doc in cursor}


async def toggle_capability(user_id: str, capability_id: str, enabled: bool) -> dict:
    """Enable or disable a capability for a user.

    When enabling: sets status to 'enabled_not_ready' initially.
    The system will move it to 'ready' once all requirements are met.
    When disabling: sets status to 'disabled'.
    """
    db = get_database()
    now = format_utc_datetime(datetime.utcnow())

    if enabled:
        # Check if all requirements are met to go straight to 'ready'
        status = await _compute_capability_status(user_id, capability_id)
    else:
        status = "disabled"

    await db.user_advisor_capabilities.update_one(
        {"user_id": user_id, "capability_id": capability_id},
        {
            "$set": {
                "status": status,
                "updated_at": now,
            },
            "$setOnInsert": {
                "user_id": user_id,
                "capability_id": capability_id,
                "granted_at": now,
            },
        },
        upsert=True,
    )
    return {"capability_id": capability_id, "status": status}


async def refresh_capability_status(user_id: str, capability_id: str) -> str:
    """Recompute and update the capability status based on current requirements."""
    db = get_database()
    now = format_utc_datetime(datetime.utcnow())

    user_cap = await db.user_advisor_capabilities.find_one(
        {"user_id": user_id, "capability_id": capability_id}
    )
    if not user_cap or user_cap.get("status") == "disabled":
        return "disabled"

    status = await _compute_capability_status(user_id, capability_id)
    await db.user_advisor_capabilities.update_one(
        {"user_id": user_id, "capability_id": capability_id},
        {"$set": {"status": status, "updated_at": now}},
    )
    return status


async def _compute_capability_status(user_id: str, capability_id: str) -> str:
    """Determine whether a capability should be 'ready' or 'enabled_not_ready'.

    For lumie_internal_data: ready if user has a valid ping credential for at least one skill.
    For browser/email: ready if user has at least one valid credential for a skill in that capability.
    """
    from .skill_registry_service import skill_registry

    db = get_database()

    # Check if there are indexed skills for this capability
    skills = skill_registry.get_skills_by_capability(capability_id)
    if not skills:
        return "enabled_not_ready"

    # For lumie_internal_data, auto-ready (ping is auto-generated)
    if capability_id == "lumie_internal_data":
        return "ready"

    # For other capabilities, check if any skill has valid credentials
    for skill in skills:
        cred = await db.advisor_skill_credentials.find_one({
            "user_id": user_id,
            "skill_id": skill.skill_id,
            "status": "valid",
        })
        if cred:
            return "ready"

    return "enabled_not_ready"
