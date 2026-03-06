"""
Subscription validation helpers for team and task limits
"""

from fastapi import HTTPException
from ..models.user import SubscriptionTier

# Team limits by subscription tier
TEAM_LIMIT_FREE = 1
TEAM_LIMIT_PRO = 100

# Task date-range limit by subscription tier (max days into the future)
TASK_DATE_RANGE_FREE = 7  # Free users: tasks within 7 days only
TASK_DATE_RANGE_PRO = 999999  # Pro users: no limit


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


def get_task_date_range(tier: SubscriptionTier) -> int:
    """
    Get max days into the future for task creation by subscription tier.

    Free: 7 days. Pro: unlimited.
    """
    if tier == SubscriptionTier.FREE:
        return TASK_DATE_RANGE_FREE
    return TASK_DATE_RANGE_PRO


def raise_task_date_range_error(user_tier: str, max_days: int):
    """
    Raise error when free user tries to create a task beyond the allowed date range.
    """
    error_response = {
        "error": {
            "code": "SUBSCRIPTION_LIMIT_REACHED",
            "message": f"Free plan tasks are limited to {max_days} days from today",
            "detail": f"Upgrade to Pro to create tasks with no date restriction.",
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
