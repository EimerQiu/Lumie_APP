"""Profile API routes."""
from fastapi import APIRouter, Depends, Query

from ..models.user import (
    TeenProfileCreate,
    ParentProfileCreate,
    ProfileUpdate,
    UserProfile,
    ICD10SearchResult,
)
from ..services.auth_service import get_current_user_id
from ..services.profile_service import profile_service
from ..services.icd10_service import icd10_service


router = APIRouter(prefix="/profile", tags=["profile"])


@router.post("/teen", response_model=UserProfile)
async def create_teen_profile(
    data: TeenProfileCreate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Create a teen profile.

    Required for teen accounts after account type selection.

    - **name**: User's display name
    - **age**: Must be 13 or older
    - **height**: Height with unit (cm or ft_in)
    - **weight**: Weight with unit (kg or lb)
    - **icd10_code**: Optional medical condition code
    - **advisor_name**: Optional advisor/counselor name
    """
    return await profile_service.create_teen_profile(user_id, data)


@router.post("/parent", response_model=UserProfile)
async def create_parent_profile(
    data: ParentProfileCreate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Create a parent profile.

    Required for parent accounts after account type selection.

    - **name**: User's display name
    - **age**: Optional (required if pairing a ring)
    - **height**: Optional (required if pairing a ring)
    - **weight**: Optional (required if pairing a ring)
    """
    return await profile_service.create_parent_profile(user_id, data)


@router.get("", response_model=UserProfile)
async def get_profile(user_id: str = Depends(get_current_user_id)):
    """
    Get current user's profile.

    Returns complete profile data.
    """
    return await profile_service.get_profile(user_id)


@router.put("", response_model=UserProfile)
async def update_profile(
    data: ProfileUpdate,
    user_id: str = Depends(get_current_user_id)
):
    """
    Update user profile.

    All fields are optional - only provided fields will be updated.

    - **name**: Display name
    - **age**: Must be 13 or older
    - **height**: Height with unit
    - **weight**: Weight with unit
    - **icd10_code**: Medical condition code (teen only)
    - **advisor_name**: Advisor name (teen only)
    """
    return await profile_service.update_profile(user_id, data)


@router.delete("")
async def delete_profile(user_id: str = Depends(get_current_user_id)):
    """
    Delete user profile.

    This will require the user to complete profile setup again.
    """
    await profile_service.delete_profile(user_id)
    return {"message": "Profile deleted successfully"}


# ICD-10 Endpoints
@router.get("/icd10/search", response_model=ICD10SearchResult)
async def search_icd10_codes(
    query: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(20, ge=1, le=50, description="Max results to return"),
    _: str = Depends(get_current_user_id)  # Require authentication
):
    """
    Search ICD-10 codes.

    Search by code, description, or category.

    - **query**: Search term
    - **limit**: Maximum results (default 20)
    """
    return icd10_service.search(query, limit)


@router.get("/icd10/categories")
async def get_icd10_categories(_: str = Depends(get_current_user_id)):
    """
    Get all ICD-10 categories.

    Returns list of unique condition categories.
    """
    return {"categories": icd10_service.get_categories()}
