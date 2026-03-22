"""AI Tips Service — generates personalised task tips using Claude."""
import logging
import re
from datetime import datetime, timedelta
from typing import Optional

import anthropic

from ..core.config import settings
from ..core.database import get_database
from ..models.task import AiTipsResponse, TaskStats

logger = logging.getLogger(__name__)

_MODEL = "claude-haiku-4-5-20251001"

_client: Optional[anthropic.Anthropic] = None


def _get_client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        if not settings.ANTHROPIC_API_KEY:
            raise RuntimeError("ANTHROPIC_API_KEY is not configured.")
        _client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


def _clean(text: str) -> str:
    text = text.strip()
    text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
    text = re.sub(r'__([^_]+)__', r'\1', text)
    text = re.sub(r'[\*_]{1,2}', '', text)
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    return re.sub(r'\s+', ' ', ' '.join(lines))


async def get_ai_tips(user_id: str, days_back: int, time_zone: str) -> AiTipsResponse:
    """
    Analyse the user's task history and return a Claude-generated tip.

    Tasks are stored in UTC as "yyyy-MM-dd HH:mm" strings.
    We use string comparison for the date range (lexicographic order holds for this format).
    """
    db = get_database()
    now_utc = datetime.utcnow()
    since_utc = now_utc - timedelta(days=days_back)

    since_str = since_utc.strftime("%Y-%m-%d %H:%M")
    now_str = now_utc.strftime("%Y-%m-%d %H:%M")

    cursor = db.tasks.find({
        "user_id": user_id,
        "open_datetime": {"$gte": since_str, "$lte": now_str},
    })
    tasks = await cursor.to_list(length=None)

    total = len(tasks)

    if total == 0:
        return AiTipsResponse(
            tip="Start by creating your first task! Small consistent steps build healthy habits over time.",
            task_stats=TaskStats(
                total_tasks=0,
                completed_tasks=0,
                expired_tasks=0,
                pending_tasks=0,
                completion_rate=0.0,
            ),
        )

    completed = sum(1 for t in tasks if t.get("done"))
    expired = sum(
        1 for t in tasks
        if not t.get("done") and t.get("close_datetime", now_str) < now_str
    )
    pending = total - completed - expired
    rate = round(completed / total * 100, 1)

    # Collect task type distribution for richer context
    type_counts: dict[str, int] = {}
    for t in tasks:
        tt = t.get("task_type", "general")
        type_counts[tt] = type_counts.get(tt, 0) + 1
    top_type = max(type_counts, key=lambda k: type_counts[k]) if type_counts else "general"

    prompt = (
        f"A user's task stats over the past {days_back} days:\n"
        f"- Total: {total}, Completed: {completed} ({rate}%), "
        f"Expired: {expired}, Pending: {pending}\n"
        f"- Most common task type: {top_type}\n\n"
        "Write a warm, caring message (2-4 sentences, up to 500 characters) "
        "based on these stats. Include the actual numbers."
    )

    try:
        client = _get_client()
        response = client.messages.create(
            model=_MODEL,
            max_tokens=250,
            system=(
                "You write caring encouragement for a teen health task app. "
                "Your tone is like a loving parent who truly cares about the child: "
                "warm, reassuring, patient, and kind. "
                "Never sound like a productivity coach, manager, or lecture. "
                "Focus on comfort, encouragement, and one doable next step. "
                "You can gently suggest tapping for a chat with advisor when that would help. "
                "Always use actual digits for numbers (e.g. '4 out of 7', '85%'), never spell them out as words. "
                "Reply in 2-4 sentences, under 500 characters. "
                "You may use markdown and bullet points."
            ),
            messages=[{"role": "user", "content": prompt}],
        )
        tip = response.content[0].text.strip()
    except Exception as e:
        logger.error(f"Claude call failed in ai_tips_service: {e}")
        if rate >= 80:
            tip = f"Excellent work — {rate}% completion rate! Keep your winning streak going today."
        elif rate >= 50:
            tip = f"You're completing {rate}% of tasks. Try tackling your most important task first each day to push higher."
        else:
            tip = f"Your completion rate is {rate}%. Setting fewer, more specific tasks can help you finish more consistently."

    return AiTipsResponse(
        tip=tip,
        task_stats=TaskStats(
            total_tasks=total,
            completed_tasks=completed,
            expired_tasks=expired,
            pending_tasks=pending,
            completion_rate=rate,
        ),
    )
