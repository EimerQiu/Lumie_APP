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
from datetime import datetime, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

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

API_BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8000")
INTERNAL_SECRET = os.getenv("INTERNAL_SECRET") or os.getenv("SECRET_KEY", "")

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
    *,
    extra_payload: Optional[dict] = None,
    include_alert: bool = True,
    include_sound: bool = True,
    content_available: bool = False,
    push_type: str = "alert",
    priority: str = "10",
) -> bool:
    """Send a single push notification via APNs HTTP/2."""
    try:
        token = _get_apns_token()
    except RuntimeError as e:
        logger.error("APNs token error: %s", e)
        return False

    url = f"{_apns_base_url()}/3/device/{device_token}"
    aps: dict = {}
    if include_alert:
        aps["alert"] = {"title": title, "body": body}
    if include_sound:
        aps["sound"] = "default"
    if content_available:
        aps["content-available"] = 1

    payload = {
        "aps": aps,
        "task_id": task_id,
    }
    if extra_payload:
        payload.update(extra_payload)
    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": APNS_TOPIC,
        "apns-push-type": push_type,
        "apns-priority": priority,
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

def _build_task_body(
    task: dict,
    close_dt: datetime,
    now: datetime,
    display_tz,
    template_cache: dict,
) -> str:
    """Build notification body text for a single task."""
    task_name = task.get("task_name", "Task")
    task_type = task.get("task_type", "Task").lower()
    body_text = task.get("task_info") or ""

    # For template tasks, look up rpttask_info
    rpttask_id = task.get("rpttask_id")
    if rpttask_id and not body_text:
        template = template_cache.get(rpttask_id)
        if template:
            body_text = template.get("description") or ""

    if not body_text:
        try:
            close_dt_local = close_dt.astimezone(display_tz)
            now_local = now.astimezone(display_tz)

            # Calculate window progress percentage
            open_str = task.get("open_datetime", "")
            try:
                open_dt = datetime.strptime(open_str, "%Y-%m-%d %H:%M").replace(tzinfo=timezone.utc)
                duration = (close_dt - open_dt).total_seconds()
                elapsed = (now - open_dt).total_seconds()
                progress_pct = int(elapsed / duration * 100) if duration > 0 else 0
                progress_pct = max(0, min(progress_pct, 100))
                progress_prefix = f"Window {progress_pct}% elapsed. "
            except Exception:
                progress_prefix = ""

            if "medicine" in task_type or "med" in task_type or "medication" in task_type:
                action_today = "Take it by"
                action_future = "Take your meds by"
            elif "exercise" in task_type or "workout" in task_type:
                action_today = "Get moving by"
                action_future = "Do your workout by"
            else:
                action_today = "Wrap up by"
                action_future = "Finish by"

            days_until = (close_dt_local.date() - now_local.date()).days
            if days_until == 0:
                close_time = close_dt_local.strftime("%I:%M %p").lstrip("0")
                time_left = close_dt_local - now_local
                hours, remainder = divmod(int(time_left.total_seconds()), 3600)
                minutes = remainder // 60
                if hours > 0:
                    time_str = f"{hours}h {minutes}m"
                else:
                    time_str = f"{minutes}m"
                body_text = f"{progress_prefix}You've got {time_str} left! 💪 {action_today} {close_time}"
            elif days_until == 1:
                close_time = close_dt_local.strftime("%I:%M %p").lstrip("0")
                body_text = f"{progress_prefix}Don't forget tomorrow! {action_future} {close_time} 🌟"
            elif days_until < 7:
                close_time = close_dt_local.strftime("%a %I:%M %p").lstrip("0")
                body_text = f"{progress_prefix}You can do it! {action_future} {close_time} 💪"
            else:
                close_time = close_dt_local.strftime("%b %d, %I:%M %p").lstrip("0")
                body_text = f"{progress_prefix}No rush, but remember: {close_time} 😊"
        except Exception:
            body_text = "Don't forget!"

    return body_text


async def poll_once(db, client: httpx.AsyncClient) -> None:
    """One poll iteration: find eligible tasks, merge per-user, send notifications."""
    now = datetime.now(timezone.utc)
    now_ts = now.timestamp()

    cursor = db.tasks.find({"done": {"$exists": False}})
    tasks = await cursor.to_list(length=None)

    # --- Phase 1: collect eligible tasks per user ---
    # user_id → list of (task, close_dt, phase_info)
    eligible: dict[str, list[dict]] = {}
    template_ids: set[str] = set()

    for task in tasks:
        open_str = task.get("open_datetime", "")
        close_str = task.get("close_datetime", "")

        try:
            open_dt = datetime.strptime(open_str, "%Y-%m-%d %H:%M").replace(tzinfo=timezone.utc)
            close_dt = datetime.strptime(close_str, "%Y-%m-%d %H:%M").replace(tzinfo=timezone.utc)
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

        user_id = task["user_id"]
        task_id = task["task_id"]
        cache_key = f"{user_id}_{task_id}"

        last = _last_sent.get(cache_key, 0)
        if (now_ts - last) < interval_s:
            continue

        # Collect template IDs for batch lookup
        rpttask_id = task.get("rpttask_id")
        if rpttask_id and not task.get("task_info"):
            template_ids.add(rpttask_id)

        eligible.setdefault(user_id, []).append({
            "task": task,
            "close_dt": close_dt,
            "phase": phase,
            "cache_key": cache_key,
        })

    if not eligible:
        return

    # --- Batch fetch templates ---
    template_cache: dict[str, dict] = {}
    if template_ids:
        tpl_cursor = db.task_templates.find({"id": {"$in": list(template_ids)}})
        async for tpl in tpl_cursor:
            template_cache[tpl["id"]] = tpl

    # --- Phase 2: per-user merge & send ---
    for user_id, entries in eligible.items():
        user = await db.users.find_one(
            {"user_id": user_id},
            {"device_token": 1, "_id": 0},
        )
        device_token = (user or {}).get("device_token")
        if not device_token:
            continue

        profile = await db.profiles.find_one(
            {"user_id": user_id},
            {"timezone": 1, "_id": 0},
        )
        profile_tz_str = (profile or {}).get("timezone", "UTC")
        try:
            display_tz = ZoneInfo(profile_tz_str)
        except Exception:
            display_tz = ZoneInfo("UTC")

        if len(entries) == 1:
            # --- Single task: send individual notification (original behavior) ---
            e = entries[0]
            task = e["task"]
            _, _, title_suffix = e["phase"]
            task_name = task.get("task_name", "Task")
            body_text = _build_task_body(task, e["close_dt"], now, display_tz, template_cache)
            title = f"{task_name} {title_suffix}"

            sent = await send_apns(client, device_token, title, body_text, task["task_id"])
            if sent:
                _last_sent[e["cache_key"]] = now_ts
        else:
            # --- Multiple tasks: merge into one notification ---
            task_names = [e["task"].get("task_name", "Task") for e in entries]
            task_ids = [e["task"]["task_id"] for e in entries]

            # Build compact body: list each task with its deadline
            lines: list[str] = []
            for e in entries:
                task = e["task"]
                name = task.get("task_name", "Task")
                try:
                    close_local = e["close_dt"].astimezone(display_tz)
                    close_time = close_local.strftime("%I:%M %p").lstrip("0")
                    lines.append(f"• {name} — by {close_time}")
                except Exception:
                    lines.append(f"• {name}")

            count = len(entries)
            title = f"You have {count} tasks to do! 💪"
            body_text = "\n".join(lines)

            sent = await send_apns(
                client, device_token, title, body_text,
                task_id=task_ids[0],
                extra_payload={"task_ids": task_ids},
            )
            if sent:
                for e in entries:
                    _last_sent[e["cache_key"]] = now_ts


# ---------------------------------------------------------------------------
# Notification queue processing (advisor alerts, analysis results, check-ins)
# ---------------------------------------------------------------------------

async def process_notification_queue(db, client: httpx.AsyncClient) -> None:
    """Drain pending entries from ``notification_queue`` and send them via APNs."""
    pending = await db.notification_queue.find(
        {"status": "pending"},
    ).sort("created_at", 1).to_list(length=50)

    for doc in pending:
        nid = doc["notification_id"]
        recipient_id = doc["recipient_user_id"]

        # Look up the recipient's device token
        user = await db.users.find_one(
            {"user_id": recipient_id},
            {"device_token": 1, "_id": 0},
        )
        device_token = (user or {}).get("device_token")

        if not device_token:
            # No device token — mark as failed so we don't retry forever
            await db.notification_queue.update_one(
                {"notification_id": nid},
                {"$set": {"status": "no_token"}},
            )
            continue

        title = doc.get("title", "Lumie")
        body = doc.get("body", "")
        extra_data = doc.get("data", {})
        notification_type = doc.get("type")
        is_ring_command = notification_type == "ring_command"

        sent = await send_apns(
            client,
            device_token,
            title,
            body,
            task_id=extra_data.get("job_id", nid),  # reuse task_id payload field
            extra_payload=extra_data,
            include_alert=not is_ring_command,
            include_sound=not is_ring_command,
            content_available=is_ring_command,
            push_type="background" if is_ring_command else "alert",
            priority="5" if is_ring_command else "10",
        )

        new_status = "sent" if sent else "failed"
        await db.notification_queue.update_one(
            {"notification_id": nid},
            {"$set": {
                "status": new_status,
                "sent_at": datetime.now(timezone.utc).isoformat() if sent else None,
            }},
        )


# ---------------------------------------------------------------------------
# Proactive advisor check-in scheduling
# ---------------------------------------------------------------------------

async def process_advisor_proactive(db, client: httpx.AsyncClient) -> None:
    """Run a proactive advisor check for ONE user per daemon cycle.

    Users are sorted by ``last_sent_at`` ascending so the one checked least
    recently gets priority. Only the first user whose interval has elapsed is
    processed. This naturally spreads load across cycles and avoids concurrent
    Haiku calls.

    Interval mapping:
        "high"   → 30 minutes
        "normal" → 60 minutes
        "lazy"   → 360 minutes (6 hours)
    """
    _interval_minutes = {"high": 30, "normal": 60, "lazy": 360}

    now = datetime.now(timezone.utc)

    # Sort by last_sent_at ascending (nulls first) so longest-waiting user is first
    checkins = await db.advisor_checkins.find(
        {"enabled": True}
    ).sort("last_sent_at", 1).to_list(length=500)

    # Find the first user whose interval has elapsed
    target = None
    for cfg in checkins:
        freq = cfg.get("frequency", "normal")
        interval_minutes = _interval_minutes.get(freq, 60)
        last_sent_raw = cfg.get("last_sent_at")

        if last_sent_raw:
            try:
                last_sent_dt = datetime.fromisoformat(last_sent_raw)
                if last_sent_dt.tzinfo is None:
                    last_sent_dt = last_sent_dt.replace(tzinfo=timezone.utc)
                elapsed_minutes = (now - last_sent_dt).total_seconds() / 60
                if elapsed_minutes < interval_minutes:
                    continue
            except (ValueError, TypeError):
                pass  # malformed timestamp — treat as eligible

        target = cfg
        break  # process only this one user this cycle

    if not target:
        logger.info("Proactive: no user due for a check this cycle")
        return

    user_id = target["user_id"]
    freq = target.get("frequency", "normal")
    last_sent_raw = target.get("last_sent_at", "never")
    logger.info("Proactive: selected user=%s freq=%s last_checked=%s", user_id, freq, last_sent_raw)

    # Mark last_sent_at immediately to prevent double-processing if daemon restarts
    await db.advisor_checkins.update_one(
        {"user_id": user_id},
        {"$set": {"last_sent_at": now.isoformat()}},
    )

    # Call the internal proactive endpoint (AI decides whether to nudge).
    # Use a plain HTTP/1.1 client — the APNs client (http2=True) is not suitable
    # for calling localhost uvicorn which does not support h2c.
    url = f"{API_BASE_URL}/api/v1/internal/advisor/proactive/run/{user_id}"
    try:
        async with httpx.AsyncClient(timeout=60) as internal_client:
            resp = await internal_client.post(
                url,
                headers={"x-internal-secret": INTERNAL_SECRET},
            )
        if resp.status_code == 200:
            result = resp.json()
            logger.info(
                "Proactive result for user=%s: nudged=%s reason=%s message=%s",
                user_id,
                result.get("nudged"),
                result.get("reason"),
                result.get("message"),
            )
        else:
            logger.warning(
                "Proactive endpoint returned %s for user=%s: %s",
                resp.status_code, user_id, resp.text,
            )
    except Exception as e:
        logger.error("Proactive check request failed for user=%s: %r", user_id, e, exc_info=True)


# ---------------------------------------------------------------------------
# Main daemon loop
# ---------------------------------------------------------------------------

async def run_daemon() -> None:
    """Main daemon loop."""
    logger.info(
        "Starting notification daemon (poll every %ds, API=%s, internal_secret=%s)",
        POLL_INTERVAL,
        API_BASE_URL,
        "set" if INTERNAL_SECRET else "NOT SET",
    )

    mongo = AsyncIOMotorClient(MONGODB_URL)
    db = mongo[MONGODB_DB_NAME]

    async with httpx.AsyncClient(http2=True, timeout=30) as client:
        cycle = 0
        while True:
            cycle += 1
            logger.info("── Daemon cycle #%d ──────────────────────────", cycle)

            try:
                await poll_once(db, client)
            except Exception:
                logger.exception("Error in task poll cycle")

            try:
                await process_notification_queue(db, client)
            except Exception:
                logger.exception("Error in notification queue cycle")

            try:
                await process_advisor_proactive(db, client)
            except Exception:
                logger.exception("Error in advisor proactive cycle")

            await asyncio.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    asyncio.run(run_daemon())
