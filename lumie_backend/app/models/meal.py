"""
Meal models for the Meal Feature (PRD §7).

Replaces the text-only Nutrition Task summary with a first-class, structured meal
entity that supports a personal history, team-scoped feed, and correction learning.
"""

from typing import Optional, List
from pydantic import BaseModel, Field
from enum import Enum


class MacroLevel(str, Enum):
    """Macro composition category. Numeric grams/calories are NEVER exposed."""
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"


class MealVisibility(str, Enum):
    PRIVATE = "private"
    TEAM = "team"


class MealType(str, Enum):
    """When the meal was eaten — auto-suggested from local time at create time,
    user-editable on the detail screen."""
    BREAKFAST = "Breakfast"
    LUNCH = "Lunch"
    DINNER = "Dinner"
    SNACK = "Snack"


class NutritionLevel(str, Enum):
    """Overall meal-quality tier. LLM-derived from food_items + macro_ratio.
    Drives the Limited→Nutritious slider on the detail screen and the weekly
    trend chart on the home screen. Never numeric."""
    LIMITED = "Limited"
    FAIR = "Fair"
    GOOD = "Good"
    NUTRITIOUS = "Nutritious"


class MealStructure(str, Enum):
    """How the meal is laid out for portion editing.

    - MULTI_ITEM: separate dishes/foods (e.g. bread + egg + milk). Portion
      slider is shown at the item level, one drag bar per food.
    - SINGLE_ITEM_WITH_INGREDIENTS: one composite dish made of components
      (e.g. yogurt bowl with yogurt + berries + granola). Portion slider is
      shown at the ingredient level — the parent food acts as a container.

    Defaults to MULTI_ITEM when ambiguous so the UI always renders a usable
    portion control even if classification is unsure.
    """
    MULTI_ITEM = "multi_item"
    SINGLE_ITEM_WITH_INGREDIENTS = "single_item_with_ingredients"


class MacroScores(BaseModel):
    """Continuous score (0.0–1.0) for each macro field.

    Drives the smooth visual fill position of the breakdown bar — values are
    more precise than the three-point Low/Moderate/High categorical labels.

    Ranges:
      0.00–0.33  Low
      0.34–0.66  Moderate
      0.67–1.00  High

    Fallback derivation when LLM omits scores:
      low → 0.17, moderate → 0.50, high → 0.83
    """
    protein: float = Field(0.5, ge=0.0, le=1.0)
    carbs: float = Field(0.5, ge=0.0, le=1.0)
    fat: float = Field(0.5, ge=0.0, le=1.0)
    fiber: float = Field(0.5, ge=0.0, le=1.0)
    processing_level: float = Field(0.5, ge=0.0, le=1.0)
    added_sugar: float = Field(0.5, ge=0.0, le=1.0)


class MacroRatio(BaseModel):
    protein: MacroLevel
    carbs: MacroLevel
    fat: MacroLevel
    fiber: MacroLevel


class Ingredient(BaseModel):
    """A component of a single composite food item (e.g. granola in a yogurt
    bowl). Carries only a name and a relative portion weight — no grams or
    calories ever leave the backend."""
    name: str = Field(..., min_length=1, max_length=200)
    portion_weight: int = Field(1, ge=1, le=20)


class FoodItem(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    macro_ratio: Optional[MacroRatio] = None
    # Relative portion weight as estimated visually from the photo. Higher
    # number = larger share of the plate. Always relative — no grams, no
    # calories. Used to weight each item's macro contribution in the
    # structuring prompt and to render the user-draggable portion bar.
    portion_weight: int = Field(1, ge=1, le=20)
    # Populated only when the parent meal's `structure` is
    # SINGLE_ITEM_WITH_INGREDIENTS. Each ingredient gets its own portion
    # weight; the user-draggable bar then operates on these instead of on
    # sibling food_items.
    ingredients: Optional[List[Ingredient]] = None


# ============ Analyze (multipart upload result) ============

class MealAnalyzeResponse(BaseModel):
    """Response from POST /meals/analyze. Images are persisted; the meal document
    is NOT yet created — the caller must POST /meals to confirm."""
    meal_id: str = Field(..., description="Generated meal_id; pass back to POST /meals to confirm")
    images: List[dict] = Field(default_factory=list)
    food_items: List[FoodItem]
    macro_ratio: MacroRatio
    structure: MealStructure = Field(
        MealStructure.MULTI_ITEM,
        description="Layout for the portion editor (item-level vs ingredient-level)",
    )
    meal_name: Optional[str] = Field(None, description="3–6 word descriptive name generated from food items")
    nutrition_level: Optional[NutritionLevel] = Field(None, description="Overall meal-quality tier")
    advisor_insight: Optional[str] = Field(None, description="Short, curiosity-driven Advisor paragraph (1–2 sentences)")
    processing_level: Optional[MacroLevel] = Field(None, description="How processed the foods are (low=whole, high=ultra-processed)")
    added_sugar: Optional[MacroLevel] = Field(None, description="Added-sugar load (low=none, high=heavily sweetened); natural fruit sugar does NOT count")
    is_packaged: bool = Field(False, description="True when the LLM detected a branded/packaged product and used its actual ingredient list for grading")
    detected_brand: Optional[str] = Field(None, description="Identified brand name, e.g. 'RX Bar'")
    detected_product: Optional[str] = Field(None, description="Identified product name, e.g. 'Chocolate Sea Salt RX Bar'")
    macro_scores: Optional[MacroScores] = Field(None, description="Continuous 0–1 scores driving the smooth breakdown bar fill")


# ============ Create / Update / Read ============

class MealAnalyzeTextRequest(BaseModel):
    """POST /meals/analyze-text — structured analysis from typed food items only;
    no photo required. The backend runs the same LLM structuring layer as the
    photo path and returns a new meal_id the client uses to confirm via
    POST /meals."""
    food_items: List[FoodItem] = Field(..., min_length=1)


class MealCreate(BaseModel):
    """Confirm a previously-analyzed meal (or create one bridged from a task)."""
    meal_id: str = Field(..., description="meal_id returned by /meals/analyze or /meals/analyze-text")
    food_items: List[FoodItem] = Field(..., min_length=1)
    macro_ratio: MacroRatio
    structure: Optional[MealStructure] = Field(
        None,
        description="Multi-item vs single-item-with-ingredients; defaults to multi_item",
    )
    note: Optional[str] = Field(None, description="Free-form user note; no char cap (PRD §11)")
    text_only: bool = Field(
        False,
        description="True when the meal was created without a photo (typed or recent-meal path). Skips the image-presence check on the server.",
    )
    macro_scores: Optional[MacroScores] = Field(
        None, description="Continuous 0–1 scores; passed back from the analyze result"
    )
    is_packaged: Optional[bool] = Field(
        None,
        description="Pass through from the analyze response; persisted on the meal document.",
    )
    detected_brand: Optional[str] = Field(None, description="Brand name from packaged food detection")
    detected_product: Optional[str] = Field(None, description="Product name from packaged food detection")
    visibility: MealVisibility = MealVisibility.PRIVATE
    team_id: Optional[str] = Field(None, description="Required when visibility='team'")
    linked_task_id: Optional[str] = Field(None, description="Set internally when bridged from a Nutrition Task")
    # Optional v2 fields — server derives defaults if absent.
    meal_name: Optional[str] = Field(None, description="3–6 word descriptive name; server auto-generates if absent")
    meal_type: Optional[MealType] = Field(None, description="Breakfast/Lunch/Dinner/Snack; server picks from local time if absent")
    meal_time: Optional[str] = Field(None, description="ISO datetime of when meal was eaten; defaults to now (UTC)")
    nutrition_level: Optional[NutritionLevel] = Field(None, description="Overall meal tier; server derives from macro_ratio if absent")
    advisor_insight: Optional[str] = Field(None, description="Short Advisor paragraph; server uses analyze-time output if absent")
    processing_level: Optional[MacroLevel] = Field(None, description="Processing tier (low/moderate/high)")
    added_sugar: Optional[MacroLevel] = Field(None, description="Added-sugar tier (low/moderate/high)")
    timezone: Optional[str] = Field(None, description="Caller's IANA timezone for meal_type derivation (e.g. America/Los_Angeles)")


class MealUpdate(BaseModel):
    """Partial update. Fields not present are unchanged."""
    food_items: Optional[List[FoodItem]] = Field(None, min_length=1)
    macro_ratio: Optional[MacroRatio] = None
    structure: Optional[MealStructure] = None
    note: Optional[str] = None
    visibility: Optional[MealVisibility] = None
    team_id: Optional[str] = Field(None, description="null to detach from a team")
    meal_name: Optional[str] = None
    meal_type: Optional[MealType] = None
    meal_time: Optional[str] = Field(None, description="ISO datetime of when meal was eaten")
    nutrition_level: Optional[NutritionLevel] = None
    advisor_insight: Optional[str] = None
    processing_level: Optional[MacroLevel] = None
    added_sugar: Optional[MacroLevel] = None


class MealResponse(BaseModel):
    meal_id: str
    user_id: str
    user_name: Optional[str] = None
    images: List[dict] = Field(default_factory=list)
    food_items: List[FoodItem]
    macro_ratio: MacroRatio
    structure: MealStructure = MealStructure.MULTI_ITEM
    macro_scores: Optional[MacroScores] = None
    is_packaged: bool = False
    detected_brand: Optional[str] = None
    detected_product: Optional[str] = None
    note: Optional[str] = None
    visibility: MealVisibility
    team_id: Optional[str] = None
    linked_task_id: Optional[str] = None
    meal_name: Optional[str] = None
    meal_type: Optional[MealType] = None
    meal_time: Optional[str] = None
    nutrition_level: Optional[NutritionLevel] = None
    advisor_insight: Optional[str] = None
    processing_level: Optional[MacroLevel] = None
    added_sugar: Optional[MacroLevel] = None
    created_at: str
    updated_at: str


# ============ Trend (weekly nutrition chart) ============

class MealTrendDay(BaseModel):
    """One bucket in the weekly trend chart."""
    date: str = Field(..., description="YYYY-MM-DD in the user's local timezone")
    level: Optional[NutritionLevel] = Field(None, description="Average nutrition level for the day; null when zero meals")
    meal_count: int = 0


class MealTrendResponse(BaseModel):
    days: List[MealTrendDay] = Field(..., description="Oldest first; the last entry is today")


class MealListResponse(BaseModel):
    meals: List[MealResponse]
    total: int
    next_cursor: Optional[str] = Field(None, description="ISO timestamp; pass as ?before= for next page")


# ============ Corrections ============

class MealCorrectionCreate(BaseModel):
    """Capture a user correction so future analyses can bias toward it."""
    original_food_items: List[FoodItem]
    corrected_food_items: List[FoodItem]
    original_macro_ratio: Optional[MacroRatio] = None
    corrected_macro_ratio: Optional[MacroRatio] = None


class MealCorrectionResponse(BaseModel):
    correction_id: str
    meal_id: str
    user_id: str
    created_at: str


# ============ Re-structure (pre-confirm draft re-analysis) ============

class MealRestructureRequest(BaseModel):
    """Re-run the structuring layer against a user-edited food list (with
    portion weights) without re-uploading the photo. Used by the Log screen's
    in-place Re-analyze button — the meal hasn't been confirmed yet, so we
    don't have a DB record to PUT against."""
    food_items: List[FoodItem] = Field(..., min_length=1)


class MealRestructureResponse(BaseModel):
    """Same shape as MealAnalyzeResponse minus the persisted-image bits."""
    food_items: List[FoodItem]
    macro_ratio: MacroRatio
    structure: MealStructure = MealStructure.MULTI_ITEM
    macro_scores: Optional[MacroScores] = None
    meal_name: Optional[str] = None
    nutrition_level: Optional[NutritionLevel] = None
    advisor_insight: Optional[str] = None
    processing_level: Optional[MacroLevel] = None
    added_sugar: Optional[MacroLevel] = None
