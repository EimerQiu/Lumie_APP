"""Advisor notification service — queues push notifications for the daemon.

Three notification types:
  1. important_insight  → sent to team admins (parents) when a teen raises a
     concerning topic (symptom, emotional distress, medication issue).
  2. analysis_complete  → sent to the user when an analysis job finishes.
  3. advisor_checkin    → proactive check-in nudge at a scheduled time.

All notifications are written to the ``notification_queue`` MongoDB collection
and picked up by the notification daemon on its next poll cycle.  This keeps
the API response fast (no inline APNs call) and centralises delivery in one
process that already holds the HTTP/2 client.

Queue document schema::

    {
        "notification_id": str (UUID),
        "type": "important_insight" | "analysis_complete" | "advisor_checkin",
        "recipient_user_id": str,
        "title": str,
        "body": str,
        "data": dict,            # extra payload for deep-linking
        "status": "pending" | "sent" | "failed",
        "created_at": str (ISO),
        "sent_at": str | None,
    }
"""

import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from ..core.database import get_database

logger = logging.getLogger(__name__)


# ── Public helpers ────────────────────────────────────────────────────────────

async def queue_important_insight_notification(
    user_id: str,
    summary: str,
    category: str,
) -> None:
    """Notify the user's team admins about a flagged important insight.

    Looks up every team the user belongs to, finds admins, and queues a
    notification for each admin who has a device token.
    """
    try:
        db = get_database()

        # Find teams where this user is a member
        memberships = await db.team_members.find(
            {"user_id": user_id, "status": "member"},
            {"team_id": 1},
        ).to_list(length=100)

        team_ids = [m["team_id"] for m in memberships]
        if not team_ids:
            # User is not in any team — notify the user themselves
            await _enqueue(
                db,
                notification_type="important_insight",
                recipient_user_id=user_id,
                title=_insight_title(category),
                body=summary,
                data={"type": "important_insight", "category": category, "source_user_id": user_id},
            )
            return

        # Find admins in those teams (exclude the user themselves)
        admin_members = await db.team_members.find(
            {
                "team_id": {"$in": team_ids},
                "role": "admin",
                "status": "member",
                "user_id": {"$ne": user_id},
            },
            {"user_id": 1},
        ).to_list(length=100)

        admin_ids = list({m["user_id"] for m in admin_members})

        if not admin_ids:
            # No admins other than the user — send to user
            admin_ids = [user_id]

        # Get the user's display name for the notification
        profile = await db.profiles.find_one({"user_id": user_id}, {"name": 1})
        user_name = (profile or {}).get("name", "Your team member")

        for admin_id in admin_ids:
            await _enqueue(
                db,
                notification_type="important_insight",
                recipient_user_id=admin_id,
                title=_insight_title(category),
                body=f"{user_name}: {summary}",
                data={
                    "type": "important_insight",
                    "category": category,
                    "source_user_id": user_id,
                    "navigate_to": "advisor",
                },
            )

        logger.info(
            f"Queued important_insight notifications for {len(admin_ids)} admins "
            f"(user={user_id}, category={category})"
        )
    except Exception as e:
        logger.warning(f"Failed to queue important_insight notification: {e}")


async def queue_analysis_complete_notification(
    user_id: str,
    job_id: str,
    summary: str,
) -> None:
    """Notify the user that their analysis job has completed."""
    try:
        db = get_database()
        # Truncate summary for push notification body
        short_summary = summary[:120] + ("…" if len(summary) > 120 else "")
        await _enqueue(
            db,
            notification_type="analysis_complete",
            recipient_user_id=user_id,
            title="Analysis Ready",
            body=short_summary,
            data={
                "type": "analysis_complete",
                "job_id": job_id,
                "navigate_to": "advisor",
            },
        )
        logger.info(f"Queued analysis_complete notification for user={user_id}, job={job_id}")
    except Exception as e:
        logger.warning(f"Failed to queue analysis_complete notification: {e}")


async def queue_checkin_notification(
    user_id: str,
    message: str,
) -> None:
    """Send a proactive check-in nudge to the user."""
    try:
        db = get_database()
        await _enqueue(
            db,
            notification_type="advisor_checkin",
            recipient_user_id=user_id,
            title="Lumie Advisor",
            body=message,
            data={
                "type": "advisor_checkin",
                "navigate_to": "advisor",
            },
        )
        logger.info(f"Queued advisor_checkin notification for user={user_id}")
    except Exception as e:
        logger.warning(f"Failed to queue advisor_checkin notification: {e}")


# ── Private helpers ───────────────────────────────────────────────────────────

def _insight_title(category: str) -> str:
    """Human-friendly notification title based on insight category."""
    titles = {
        "symptom": "Health Alert",
        "medication": "Medication Alert",
        "emotional": "Wellness Check",
        "health_concern": "Health Alert",
        "urgent": "Urgent Alert",
        "other": "Advisor Alert",
    }
    return titles.get(category, "Advisor Alert")


async def _enqueue(
    db,
    *,
    notification_type: str,
    recipient_user_id: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> None:
    """Insert a notification into the queue collection."""
    doc = {
        "notification_id": str(uuid.uuid4()),
        "type": notification_type,
        "recipient_user_id": recipient_user_id,
        "title": title,
        "body": body,
        "data": data or {},
        "status": "pending",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "sent_at": None,
    }
    await db.notification_queue.insert_one(doc)
