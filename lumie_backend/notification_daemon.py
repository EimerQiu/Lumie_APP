"""
Med-Reminder Notification Daemon

Standalone daemon that polls MongoDB for active tasks and sends push
notifications via APNs.  Runs independently of the FastAPI server.

Usage:
    python notification_daemon.py

Env vars (same as the API server):
    MONGODB_URL          – MongoDB connection string
    MONGODB_DB_NAME      – defaults to lumie_db
    APNS_KEY_PATH        – path to .p8 key file
    APNS_KEY_ID          – Apple key ID
    APNS_TEAM_ID         – Apple team ID
    APNS_TOPIC           – bundle identifier (e.g. com.lumie.app)
    APNS_USE_SANDBOX     – "true" for development (default), "false" for production
"""

import asyncio
import logging
import os
import time
import json
import jwt
from datetime import datetime, timedelta
from typing import Optional

import httpx
from motor.motor_asyncio import AsyncIOMotorClient

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

MONGODB_URL = os.getenv("MONGODB_URL", "mongodb://localhost:27017")
MONGODB_DB_NAME = os.getenv("MONGODB_DB_NAME", "lumie_db")

APNS_KEY_PATH = os.getenv("APNS_KEY_PATH", "")
APNS_KEY_ID = os.getenv("APNS_KEY_ID", "")
APNS_TEAM_ID = os.getenv("APNS_TEAM_ID", "")
APNS_TOPIC = os.getenv("APNS_TOPIC", "")
APNS_USE_SANDBOX = os.getenv("APNS_USE_SANDBOX", "true").lower() == "true"

POLL_INTERVAL = 60  # seconds

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("notification_daemon")

# ---------------------------------------------------------------------------
# In-memory dedup cache: key = "{user_id}_{task_id}" → last_sent timestamp
# ---------------------------------------------------------------------------

_last_sent: dict[str, float] = {}

# ---------------------------------------------------------------------------
# APNs helpers
# ---------------------------------------------------------------------------

_apns_token: Optional[str] = None
_apns_token_exp: float = 0


def _get_apns_token() -> str:
    """Create or reuse a short-lived APNs JWT (refreshed every 50 min)."""
    global _apns_token, _apns_token_exp

    now = time.time()
    if _apns_token and now < _apns_token_exp:
        return _apns_token

    if not APNS_KEY_PATH or not os.path.exists(APNS_KEY_PATH):
        raise RuntimeError(f"APNs key file not found: {APNS_KEY_PATH}")

    with open(APNS_KEY_PATH, "r") as f:
        key = f.read()

    _apns_token = jwt.encode(
        {"iss": APNS_TEAM_ID, "iat": int(now)},
        key,
        algorithm="ES256",
        headers={"kid": APNS_KEY_ID},
    )
    _apns_token_exp = now + 50 * 60  # refresh before the 60-min Apple limit
    return _apns_token


def _apns_base_url() -> str:
    if APNS_USE_SANDBOX:
        return "https://api.sandbox.push.apple.com"
    return "https://api.push.apple.com"


async def send_apns(
    client: httpx.AsyncClient,
    device_token: str,
    title: str,
    body: str,
    task_id: str,
) -> bool:
    """Send a single push notification via APNs HTTP/2."""
    try:
        token = _get_apns_token()
    except RuntimeError as e:
        logger.error("APNs token error: %s", e)
        return False

    url = f"{_apns_base_url()}/3/device/{device_token}"
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
        },
        "task_id": task_id,
    }
    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": APNS_TOPIC,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }
    try:
        resp = await client.post(url, json=payload, headers=headers)
        if resp.status_code == 200:
            logger.info("Sent → %s (%s)", title, device_token[:12])
            return True
        else:
            logger.warning(
                "APNs %s for token %s: %s",
                resp.status_code,
                device_token[:12],
                resp.text,
            )
            return False
    except Exception as e:
        logger.error("APNs request failed: %s", e)
        return False


# ---------------------------------------------------------------------------
# Phase logic
# ---------------------------------------------------------------------------

def _get_phase(progress: float, duration_s: float) -> Optional[tuple[str, float, str]]:
    """
    Returns (phase_name, interval_seconds, title_suffix) or None if not eligible.
    """
    if progress < 0 or progress > 1:
        return None

    if progress <= 0.10:
        interval = duration_s * 0.05
        return ("early", interval, "Started")
    elif progress <= 0.90:
        interval = duration_s * 0.10
        return ("middle", interval, "Progress")
    else:
        interval = duration_s * 0.025 - 60
        if interval <= 0:
            interval = POLL_INTERVAL
        return ("late", interval, "Ending Soon")


# ---------------------------------------------------------------------------
# Main poll cycle
# ---------------------------------------------------------------------------

async def poll_once(db, client: httpx.AsyncClient) -> None:
    """One poll iteration: find eligible tasks and send notifications."""
    now = datetime.utcnow()
    now_ts = now.timestamp()
    now_str = now.strftime("%Y-%m-%d %H:%M")

    # Find all tasks where done field does not exist (not yet completed)
    cursor = db.tasks.find({"done": {"$exists": False}})
    tasks = await cursor.to_list(length=None)

    for task in tasks:
        open_str = task.get("open_datetime", "")
        close_str = task.get("close_datetime", "")

        try:
            open_dt = datetime.strptime(open_str, "%Y-%m-%d %H:%M")
            close_dt = datetime.strptime(close_str, "%Y-%m-%d %H:%M")
        except (ValueError, TypeError):
            continue

        duration_s = (close_dt - open_dt).total_seconds()
        if duration_s <= 0:
            continue

        progress = (now - open_dt).total_seconds() / duration_s

        phase = _get_phase(progress, duration_s)
        if phase is None:
            continue

        phase_name, interval_s, title_suffix = phase

        # Dedup check
        user_id = task["user_id"]
        task_id = task["task_id"]
        cache_key = f"{user_id}_{task_id}"

        last = _last_sent.get(cache_key, 0)
        if (now_ts - last) < interval_s:
            continue

        # Look up user device token
        user = await db.users.find_one(
            {"user_id": user_id},
            {"device_token": 1, "_id": 0},
        )
        device_token = (user or {}).get("device_token")
        if not device_token:
            continue

        # Resolve task name and body
        task_name = task.get("task_name", "Task")
        body_text = task.get("task_info") or ""

        # For template tasks, look up rpttask_info
        rpttask_id = task.get("rpttask_id")
        if rpttask_id and not body_text:
            template = await db.task_templates.find_one({"id": rpttask_id})
            if template:
                body_text = template.get("description") or ""

        if not body_text:
            body_text = "No specific information provided"

        title = f"{task_name} {title_suffix}"

        sent = await send_apns(client, device_token, title, body_text, task_id)
        if sent:
            _last_sent[cache_key] = now_ts


async def run_daemon() -> None:
    """Main daemon loop."""
    logger.info("Starting notification daemon (poll every %ds)", POLL_INTERVAL)

    mongo = AsyncIOMotorClient(MONGODB_URL)
    db = mongo[MONGODB_DB_NAME]

    async with httpx.AsyncClient(http2=True, timeout=30) as client:
        while True:
            try:
                await poll_once(db, client)
            except Exception:
                logger.exception("Error in poll cycle")

            await asyncio.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    asyncio.run(run_daemon())
