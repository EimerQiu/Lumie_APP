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


# ============ Authentication Models ============

class UserSignUp(BaseModel):
    """Request model for user signup."""
    email: EmailStr
    password: str = Field(..., min_length=8)
    confirm_password: str = Field(..., min_length=8)
    role: AccountRole


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
