"""
Meal API Routes (Meal Feature, PRD §8).

Endpoints:
  POST   /meals/analyze            multipart upload → structured analysis (no DB write)
  POST   /meals                    confirm a previously-analyzed meal
  GET    /meals/me                 personal meal history (cursor-paginated)
  GET    /meals/feed               team feed (?team_id=)
  GET    /meals/{meal_id}          detail
  PUT    /meals/{meal_id}          edit foods/macros/note/visibility
  DELETE /meals/{meal_id}
  POST   /meals/{meal_id}/correction   capture correction (personal-bias learning)
"""

from typing import Optional

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile, status

from ..models.meal import (
    MacroLevel,
    MacroRatio,
    MacroScores,
    MealAnalyzeResponse,
    MealAnalyzeTextRequest,
    MealCreate,
    MealUpdate,
    MealResponse,
    MealListResponse,
    MealCorrectionCreate,
    MealCorrectionResponse,
    MealRestructureRequest,
    MealRestructureResponse,
    MealTrendResponse,
    NutritionLevel,
    FoodItem,
)
from ..services.auth_service import get_current_user_id
from ..services.meal_service import meal_service

router = APIRouter(prefix="/meals", tags=["meals"])


@router.post("/analyze", response_model=MealAnalyzeResponse)
async def analyze_meal_images(
    files: list[UploadFile] = File(...),
    summary_text: Optional[str] = Form(None),
    user_id: str = Depends(get_current_user_id),
):
    """
    Upload meal photo(s) and receive structured analysis.

    - Max 99 images per request
    - Saves images under uploads/meals/{meal_id}/ but does NOT yet persist a meal
      document — the client must POST /meals to confirm
    - Macro ratios are categorical (low/moderate/high); numeric grams are never returned

    `summary_text` (optional): if the caller has already obtained the
    Nutrition-Task vision summary by calling `/tasks/nutrition/analyze-images`
    directly, they pass it here and the backend skips the vision call entirely
    — only the meal-specific Step-7 structuring layer runs. This is the
    Lumie Meal-feature flow per the PRD: vision step always goes through the
    proven `/tasks/nutrition/analyze-images` endpoint, never a parallel pipeline.
    """
    return await meal_service.analyze_uploads(
        user_id, files, summary_text=summary_text,
    )


@router.post("/analyze-text", response_model=MealAnalyzeResponse)
async def analyze_meal_text(
    data: MealAnalyzeTextRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Structured analysis from typed food items — no photo required.

    Runs the same LLM structuring layer as the photo path and returns a new
    `meal_id` the client uses to confirm via `POST /meals` (with `text_only=true`).
    Used by the "Type in Meal" and "Recent Meals" entry paths.
    """
    return await meal_service.analyze_text_only(user_id, data.food_items)


@router.post("/restructure", response_model=MealRestructureResponse)
async def restructure_meal_draft(
    data: MealRestructureRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Re-run structuring against a user-edited food list (with portion weights)
    without re-running vision or persisting the meal. Powers the Log screen's
    in-place Re-analyze button, where the meal hasn't been confirmed yet so
    PUT /meals/{id} isn't applicable.
    """
    parsed = await meal_service.restructure_food_list(user_id, data.food_items)
    macro_dump = parsed.get("macro_ratio") or {}
    food_dumps = parsed.get("food_items") or []
    scores_raw = parsed.get("macro_scores")
    return MealRestructureResponse(
        food_items=[FoodItem(**fi) for fi in food_dumps],
        macro_ratio=MacroRatio(**macro_dump),
        macro_scores=MacroScores(**scores_raw) if isinstance(scores_raw, dict) else None,
        meal_name=parsed.get("meal_name") or None,
        nutrition_level=NutritionLevel(parsed["nutrition_level"])
            if parsed.get("nutrition_level") else None,
        advisor_insight=parsed.get("advisor_insight") or None,
        processing_level=MacroLevel(parsed["processing_level"])
            if parsed.get("processing_level") else None,
        added_sugar=MacroLevel(parsed["added_sugar"])
            if parsed.get("added_sugar") else None,
    )


@router.post("", response_model=MealResponse, status_code=status.HTTP_201_CREATED)
async def create_meal(
    data: MealCreate,
    user_id: str = Depends(get_current_user_id),
):
    """
    Confirm a meal previously analyzed via POST /meals/analyze.

    - Requires meal_id returned by /meals/analyze
    - Server re-scans uploads/meals/{meal_id}/ to attach images
    - When visibility='team', team_id is required and membership is verified
    """
    return await meal_service.create_meal(user_id, data)


@router.get("/trend", response_model=MealTrendResponse)
async def get_meal_trend(
    days: int = Query(7, ge=1, le=31),
    user_id: str = Depends(get_current_user_id),
):
    """
    Weekly nutrition trend for the home-screen chart.

    - One bucket per local-calendar day (user's profile timezone).
    - Oldest first; the last entry is today.
    - `level` is null for days with zero meals.
    - Average nutrition_level is mapped to the nearest categorical level.
    """
    return await meal_service.get_trend(user_id, days=days)


@router.get("/me", response_model=MealListResponse)
async def list_my_meals(
    limit: int = Query(20, ge=1, le=50),
    before: Optional[str] = Query(None, description="ISO timestamp cursor – return meals older than this"),
    user_id: str = Depends(get_current_user_id),
):
    """
    List the current user's meals, newest first.

    - Cursor-paginated by created_at
    """
    return await meal_service.list_user_meals(user_id, limit=limit, before=before)


@router.get("/feed", response_model=MealListResponse)
async def get_meal_feed(
    team_id: str = Query(..., description="Team to fetch the meals feed for"),
    limit: int = Query(20, ge=1, le=50),
    before: Optional[str] = Query(None, description="ISO timestamp cursor"),
    user_id: str = Depends(get_current_user_id),
):
    """
    Team-scoped meals feed.

    - Caller must be an active team member
    - Returns meals where visibility='team' and team_id matches
    """
    return await meal_service.get_team_feed(team_id, user_id, limit=limit, before=before)


@router.get("/{meal_id}", response_model=MealResponse)
async def get_meal(
    meal_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """
    Get meal detail.

    - Owner can always view
    - Other team members can view if visibility='team'
    """
    return await meal_service.get_meal(meal_id, user_id)


@router.put("/{meal_id}", response_model=MealResponse)
async def update_meal(
    meal_id: str,
    data: MealUpdate,
    user_id: str = Depends(get_current_user_id),
):
    """
    Edit a meal's food items, macro ratios, note, or visibility.

    - Only the meal owner can edit
    - Switching visibility to 'team' requires team_id and active membership
    - Switching to 'private' auto-detaches team_id
    """
    return await meal_service.update_meal(meal_id, user_id, data)


@router.delete("/{meal_id}")
async def delete_meal(
    meal_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """
    Delete a meal.

    - Only the meal owner can delete
    - Best-effort cleanup of on-disk images
    """
    return await meal_service.delete_meal(meal_id, user_id)


@router.post(
    "/{meal_id}/correction",
    response_model=MealCorrectionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_correction(
    meal_id: str,
    data: MealCorrectionCreate,
    user_id: str = Depends(get_current_user_id),
):
    """
    Capture a user correction for personal-bias learning (PRD §6).

    - Stored in meal_corrections; future analyses surface these as few-shot hints
    - Only the meal owner can submit corrections
    """
    return await meal_service.save_correction(meal_id, user_id, data)
