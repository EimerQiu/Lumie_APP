"""
Subscription validation helpers for team limits
"""

from fastapi import HTTPException
from ..models.user import SubscriptionTier

# Team limits by subscription tier
TEAM_LIMIT_FREE = 1
TEAM_LIMIT_PRO = 100


def get_team_limit(tier: SubscriptionTier) -> int:
    """
    Get team limit for subscription tier

    Args:
        tier: User's subscription tier

    Returns:
        Maximum number of teams allowed
    """
    if tier == SubscriptionTier.FREE:
        return TEAM_LIMIT_FREE
    # Both monthly and annual are "Pro" tier
    return TEAM_LIMIT_PRO


def raise_subscription_limit_error(
    user_tier: str,
    current_count: int,
    limit: int,
    action: str = "create/join"
):
    """
    Raise standardized subscription limit error

    Args:
        user_tier: User's current subscription tier ("free", "monthly", "annual")
        current_count: Current number of teams user has
        limit: Maximum number of teams allowed
        action: Action being attempted (for error message)

    Raises:
        HTTPException with status 403 and structured error response
    """
    error_response = {
        "error": {
            "code": "SUBSCRIPTION_LIMIT_REACHED",
            "message": f"You've reached your team limit ({current_count}/{limit} teams)",
            "detail": f"Free users can {action} 1 team. Upgrade to Pro for up to 100 teams.",
            "subscription": {
                "current_tier": user_tier,
                "required_tier": "pro",
                "upgrade_required": True
            },
            "action": {
                "type": "upgrade",
                "label": "Upgrade to Pro",
                "destination": "/subscription/upgrade"
            }
        }
    }
    raise HTTPException(status_code=403, detail=error_response)
