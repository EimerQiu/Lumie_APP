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


class MacroRatio(BaseModel):
    protein: MacroLevel
    carbs: MacroLevel
    fat: MacroLevel
    fiber: MacroLevel


class FoodItem(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    macro_ratio: Optional[MacroRatio] = None


# ============ Analyze (multipart upload result) ============

class MealAnalyzeResponse(BaseModel):
    """Response from POST /meals/analyze. Images are persisted; the meal document
    is NOT yet created — the caller must POST /meals to confirm."""
    meal_id: str = Field(..., description="Generated meal_id; pass back to POST /meals to confirm")
    images: List[dict] = Field(default_factory=list)
    food_items: List[FoodItem]
    macro_ratio: MacroRatio
    meal_name: Optional[str] = Field(None, description="3–6 word descriptive name generated from food items")
    nutrition_level: Optional[NutritionLevel] = Field(None, description="Overall meal-quality tier")
    advisor_insight: Optional[str] = Field(None, description="Short, curiosity-driven Advisor paragraph (1–2 sentences)")


# ============ Create / Update / Read ============

class MealCreate(BaseModel):
    """Confirm a previously-analyzed meal (or create one bridged from a task)."""
    meal_id: str = Field(..., description="meal_id returned by /meals/analyze")
    food_items: List[FoodItem] = Field(..., min_length=1)
    macro_ratio: MacroRatio
    note: Optional[str] = Field(None, description="Free-form user note; no char cap (PRD §11)")
    visibility: MealVisibility = MealVisibility.PRIVATE
    team_id: Optional[str] = Field(None, description="Required when visibility='team'")
    linked_task_id: Optional[str] = Field(None, description="Set internally when bridged from a Nutrition Task")
    # Optional v2 fields — server derives defaults if absent.
    meal_name: Optional[str] = Field(None, description="3–6 word descriptive name; server auto-generates if absent")
    meal_type: Optional[MealType] = Field(None, description="Breakfast/Lunch/Dinner/Snack; server picks from local time if absent")
    meal_time: Optional[str] = Field(None, description="ISO datetime of when meal was eaten; defaults to now (UTC)")
    nutrition_level: Optional[NutritionLevel] = Field(None, description="Overall meal tier; server derives from macro_ratio if absent")
    advisor_insight: Optional[str] = Field(None, description="Short Advisor paragraph; server uses analyze-time output if absent")
    timezone: Optional[str] = Field(None, description="Caller's IANA timezone for meal_type derivation (e.g. America/Los_Angeles)")


class MealUpdate(BaseModel):
    """Partial update. Fields not present are unchanged."""
    food_items: Optional[List[FoodItem]] = Field(None, min_length=1)
    macro_ratio: Optional[MacroRatio] = None
    note: Optional[str] = None
    visibility: Optional[MealVisibility] = None
    team_id: Optional[str] = Field(None, description="null to detach from a team")
    meal_name: Optional[str] = None
    meal_type: Optional[MealType] = None
    meal_time: Optional[str] = Field(None, description="ISO datetime of when meal was eaten")
    nutrition_level: Optional[NutritionLevel] = None
    advisor_insight: Optional[str] = None


class MealResponse(BaseModel):
    meal_id: str
    user_id: str
    user_name: Optional[str] = None
    images: List[dict] = Field(default_factory=list)
    food_items: List[FoodItem]
    macro_ratio: MacroRatio
    note: Optional[str] = None
    visibility: MealVisibility
    team_id: Optional[str] = None
    linked_task_id: Optional[str] = None
    meal_name: Optional[str] = None
    meal_type: Optional[MealType] = None
    meal_time: Optional[str] = None
    nutrition_level: Optional[NutritionLevel] = None
    advisor_insight: Optional[str] = None
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
