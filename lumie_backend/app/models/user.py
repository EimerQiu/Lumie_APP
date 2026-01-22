"""User and Profile data models for Lumie API."""
from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field, EmailStr


class AccountRole(str, Enum):
    """User account role."""
    TEEN = "teen"
    PARENT = "parent"


class HeightUnit(str, Enum):
    """Height measurement unit."""
    CM = "cm"
    FT_IN = "ft_in"


class WeightUnit(str, Enum):
    """Weight measurement unit."""
    KG = "kg"
    LB = "lb"


# ============ Authentication Models ============

class UserSignUp(BaseModel):
    """Request model for user signup."""
    email: EmailStr
    password: str = Field(..., min_length=8)
    confirm_password: str = Field(..., min_length=8)


class UserLogin(BaseModel):
    """Request model for user login."""
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    """JWT token response."""
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str
    role: Optional[AccountRole] = None
    profile_complete: bool = False


class UserInDB(BaseModel):
    """User model as stored in database."""
    user_id: str
    email: EmailStr
    hashed_password: str
    role: Optional[AccountRole] = None
    profile_complete: bool = False
    created_at: datetime
    updated_at: datetime


# ============ Profile Models ============

class HeightData(BaseModel):
    """Height measurement data."""
    value: float = Field(..., gt=0)
    unit: HeightUnit


class WeightData(BaseModel):
    """Weight measurement data."""
    value: float = Field(..., gt=0)
    unit: WeightUnit


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
