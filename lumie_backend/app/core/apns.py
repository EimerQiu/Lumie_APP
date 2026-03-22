"""Shared APNs (Apple Push Notification Service) helper.

Provides a lightweight async interface for sending push notifications
from anywhere in the FastAPI app.  The notification daemon also uses
its own httpx client for APNs, but this module is designed for ad-hoc
sends triggered by API requests (e.g. important-insight alerts).

Env vars required (same as notification_daemon):
    APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC, APNS_USE_SANDBOX
"""

import logging
import os
import time
from typing import Optional

import jwt

logger = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────

APNS_KEY_PATH = os.getenv("APNS_KEY_PATH", "")
APNS_KEY_ID = os.getenv("APNS_KEY_ID", "")
APNS_TEAM_ID = os.getenv("APNS_TEAM_ID", "")
APNS_TOPIC = os.getenv("APNS_TOPIC", "")
APNS_USE_SANDBOX = os.getenv("APNS_USE_SANDBOX", "true").lower() == "true"

# ── JWT token cache ───────────────────────────────────────────────────────────

_apns_token: Optional[str] = None
_apns_token_exp: float = 0


def get_apns_jwt() -> str:
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
    _apns_token_exp = now + 50 * 60
    return _apns_token


def apns_base_url() -> str:
    if APNS_USE_SANDBOX:
        return "https://api.sandbox.push.apple.com"
    return "https://api.push.apple.com"
