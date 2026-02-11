"""API routes for rest days management."""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status

from ..models.user import RestDaySettings
from ..services.auth_service import get_current_user_id
from ..services.rest_days_service import rest_days_service


router = APIRouter(prefix="/rest-days", tags=["rest-days"])


@router.get("", response_model=RestDaySettings)
async def get_rest_days(user_id: str = Depends(get_current_user_id)):
    """
    Get user's rest days configuration.

    Returns the user's current rest days settings including weekly recurring
    rest days and specific custom rest dates.
    """
    rest_days = await rest_days_service.get_rest_days(user_id)

    if not rest_days:
        # Return default empty settings
        return RestDaySettings(
            weekly_rest_days=[],
            specific_dates=[],
            updated_at=datetime.utcnow()
        )

    return RestDaySettings(**rest_days)


@router.put("", response_model=RestDaySettings)
async def update_rest_days(
    settings: RestDaySettings,
    user_id: str = Depends(get_current_user_id)
):
    """
    Update user's rest days configuration.

    Allows updating both weekly recurring rest days and specific custom dates.
    """
    try:
        # Validate weekly days
        settings.weekly_rest_days = RestDaySettings.validate_weekly_days(
            settings.weekly_rest_days
        )
        # Validate specific dates
        settings.specific_dates = RestDaySettings.validate_dates(
            settings.specific_dates
        )

        # Convert to dict for storage
        settings_dict = {
            'weekly_rest_days': settings.weekly_rest_days,
            'specific_dates': settings.specific_dates,
            'updated_at': datetime.utcnow()
        }

        updated = await rest_days_service.update_rest_days(user_id, settings_dict)
        return RestDaySettings(**updated)

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update rest days"
        )


@router.get("/check-today")
async def check_today_is_rest_day(user_id: str = Depends(get_current_user_id)):
    """
    Check if today is a rest day for the user.

    Returns whether today matches a weekly rest day or is in the specific dates list.
    """
    today = datetime.utcnow()
    is_rest = await rest_days_service.is_rest_day(user_id, today)

    return {
        "is_rest_day": is_rest,
        "date": today.date().isoformat()
    }


@router.get("/suggestion")
async def get_rest_day_suggestion(user_id: str = Depends(get_current_user_id)):
    """
    Get rest day suggestion based on sleep quality.

    Checks the user's latest sleep quality and suggests a rest day if it's below threshold.
    """
    should_suggest, suggestion_data = await rest_days_service.should_suggest_rest_day(user_id)

    return {
        "should_suggest": should_suggest,
        **suggestion_data
    }


@router.post("/set-today")
async def set_today_as_rest_day(user_id: str = Depends(get_current_user_id)):
    """
    Add today to the user's specific rest dates.

    Useful when user accepts a rest day suggestion or manually wants to mark today as a rest day.
    """
    try:
        updated = await rest_days_service.add_today_as_rest_day(user_id)
        return {
            "message": "Today added as rest day",
            "rest_days": updated
        }
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to set rest day"
        )
