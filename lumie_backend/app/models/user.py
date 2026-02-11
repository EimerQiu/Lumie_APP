"""User and Profile data models for Lumie API."""
from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field, EmailStr


class AccountRole(str, Enum):
    """User account role."""
    TEEN = "teen"
    PARENT = "parent"


class SubscriptionTier(str, Enum):
    """User subscription tier."""
    FREE = "free"
    MONTHLY = "monthly"
    ANNUAL = "annual"


class HeightUnit(str, Enum):
    """Height measurement unit."""
    CM = "cm"
    FT_IN = "ft_in"


class WeightUnit(str, Enum):
    """Weight measurement unit."""
    KG = "kg"
    LB = "lb"


# ============ Shared Models ============

class HeightData(BaseModel):
    """Height measurement data."""
    value: float = Field(..., gt=0)
    unit: HeightUnit


class WeightData(BaseModel):
    """Weight measurement data."""
    value: float = Field(..., gt=0)
    unit: WeightUnit


class SubscriptionStatus(BaseModel):
    """User subscription status and details."""
    tier: SubscriptionTier = SubscriptionTier.FREE
    is_active: bool = True
    is_trial: bool = False
    trial_end_date: Optional[datetime] = None
    subscription_start_date: Optional[datetime] = None
    subscription_end_date: Optional[datetime] = None
    ring_included: bool = False  # Annual plan includes free ring
    auto_renew: bool = False


class RestDaySettings(BaseModel):
    """Rest days configuration for user."""
    weekly_rest_days: list[int] = Field(
        default_factory=list,
        description="Days of week (0=Monday, 6=Sunday) that are recurring rest days"
    )
    specific_dates: list[str] = Field(
        default_factory=list,
        description="ISO date strings (YYYY-MM-DD) for one-time rest days"
    )
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    @classmethod
    def validate_weekly_days(cls, v):
        """Validate weekly rest days are in valid range."""
        if any(day < 0 or day > 6 for day in v):
            raise ValueError('Weekly rest days must be 0-6')
        return sorted(list(set(v)))  # Remove duplicates and sort

    @classmethod
    def validate_dates(cls, v):
        """Validate and normalize specific dates."""
        validated = []
        for date_str in v:
            try:
                date_obj = datetime.fromisoformat(date_str)
                validated.append(date_obj.date().isoformat())
            except ValueError:
                raise ValueError(f'Invalid date format: {date_str}')
        return sorted(list(set(validated)))  # Remove duplicates and sort


# ============ Authentication Models ============

class UserSignUp(BaseModel):
    """Request model for user signup."""
    email: EmailStr
    password: str = Field(..., min_length=8)
    confirm_password: str = Field(..., min_length=8)
    role: AccountRole
    invitation_token: Optional[str] = None  # If provided, skip email verification


class UserLogin(BaseModel):
    """Request model for user login."""
    email: EmailStr
    password: str


class EmailVerification(BaseModel):
    """Request model for email verification."""
    token: str


class ResendVerification(BaseModel):
    """Request model for resending verification email."""
    email: EmailStr


class TokenResponse(BaseModel):
    """JWT token response."""
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str
    role: Optional[AccountRole] = None
    profile_complete: bool = False
    email_verified: bool = False
    subscription_tier: SubscriptionTier = SubscriptionTier.FREE


class UserInDB(BaseModel):
    """User model as stored in database."""
    user_id: str
    email: EmailStr
    hashed_password: str
    role: Optional[AccountRole] = None
    profile_complete: bool = False
    email_verified: bool = False
    verification_token: Optional[str] = None
    verification_token_expires: Optional[datetime] = None
    subscription: SubscriptionStatus = Field(default_factory=lambda: SubscriptionStatus())
    created_at: datetime
    updated_at: datetime


# ============ Profile Models ============

class AccountTypeSelection(BaseModel):
    """Request model for selecting account type after signup."""
    role: AccountRole


class TeenProfileCreate(BaseModel):
    """Request model for creating a teen profile."""
    name: str = Field(..., min_length=1, max_length=100)
    age: int = Field(..., ge=13)
    height: HeightData
    weight: WeightData
    icd10_code: Optional[str] = None
    advisor_name: Optional[str] = None


class ParentProfileCreate(BaseModel):
    """Request model for creating a parent profile."""
    name: str = Field(..., min_length=1, max_length=100)
    age: Optional[int] = Field(None, ge=18)
    height: Optional[HeightData] = None
    weight: Optional[WeightData] = None


class ProfileUpdate(BaseModel):
    """Request model for updating profile."""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    age: Optional[int] = Field(None, ge=13)
    height: Optional[HeightData] = None
    weight: Optional[WeightData] = None
    icd10_code: Optional[str] = None
    advisor_name: Optional[str] = None
    rest_days: Optional[RestDaySettings] = None


class UserProfile(BaseModel):
    """Complete user profile response."""
    user_id: str
    email: EmailStr
    role: AccountRole
    name: str
    age: Optional[int] = None
    height: Optional[HeightData] = None
    weight: Optional[WeightData] = None
    icd10_code: Optional[str] = None
    advisor_name: Optional[str] = None
    rest_days: Optional[RestDaySettings] = None
    profile_complete: bool = True
    subscription: SubscriptionStatus = Field(default_factory=lambda: SubscriptionStatus())
    created_at: datetime
    updated_at: datetime


class ProfileInDB(BaseModel):
    """Profile model as stored in database."""
    user_id: str
    role: AccountRole
    name: str
    age: Optional[int] = None
    height: Optional[dict] = None  # {value, unit}
    weight: Optional[dict] = None  # {value, unit}
    icd10_code: Optional[str] = None
    advisor_name: Optional[str] = None
    subscription: Optional[dict] = None  # SubscriptionStatus as dict
    created_at: datetime
    updated_at: datetime


# ============ ICD-10 Code Models ============

class ICD10Code(BaseModel):
    """ICD-10 code entry."""
    code: str
    description: str
    category: str


class ICD10SearchResult(BaseModel):
    """ICD-10 search results."""
    results: list[ICD10Code]
    total: int
