"""Energy status assessment for proactive advisor."""
import logging
from datetime import datetime

from ...models.proactive import ProactiveSkillResult, ProactiveStatus

logger = logging.getLogger(__name__)

SKILL_ID = "proactive_energy_assessment"
DOMAIN = "energy"


async def assess(db, user_id: str, now_utc: datetime) -> ProactiveSkillResult:
    """Assess home energy status (solar, battery, AC, consumption, grid)."""
    # Note: Energy data comes from external API (home.yumo.org)
    # This assessment fetches the latest energy status and evaluates for concerns

    # Check if user has energy monitoring enabled (via credentials)
    cred = await db.advisor_skill_credentials.find_one({
        "user_id": user_id,
        "credential_id": "home_energy",
    })

    if not cred:
        return ProactiveSkillResult(
            skill_id=SKILL_ID,
            domain=DOMAIN,
            status=ProactiveStatus.MISSING,
            summary="Home energy monitoring not configured.",
            score=0.0,
            signals=["no_energy_credentials"],
            evidence={"reason": "home_energy credential not found"},
        )

    # For now, return insufficient_data since real-time energy data is external
    # Future: could integrate with httpx to fetch from home.yumo.org/api/energy-status
    # and cache results in MongoDB for proactive use
    return ProactiveSkillResult(
        skill_id=SKILL_ID,
        domain=DOMAIN,
        status=ProactiveStatus.INSUFFICIENT_DATA,
        summary="Real-time energy data fetching from external API not yet cached for proactive use.",
        score=0.0,
        signals=["energy_api_not_cached"],
        evidence={
            "note": "Energy assessment requires caching energy API responses in MongoDB",
            "suggestion": "Store latest energy status in energy_readings collection",
        },
    )
