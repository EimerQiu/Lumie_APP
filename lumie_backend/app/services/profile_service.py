"""Profile service for user profile management."""
from datetime import datetime
from typing import Optional

from fastapi import HTTPException, status

from ..core.database import get_database
from ..models.user import (
    AccountRole,
    TeenProfileCreate,
    ParentProfileCreate,
    ProfileUpdate,
    UserProfile,
    HeightData,
    WeightData,
)


class ProfileService:
    """Service for managing user profiles."""

    async def create_teen_profile(self, user_id: str, data: TeenProfileCreate) -> UserProfile:
        """Create a teen profile."""
        db = get_database()

        # Get user and verify role
        user = await db.users.find_one({"user_id": user_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )

        if user.get("role") != AccountRole.TEEN.value:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User is not a teen account"
            )

        # Check if profile already exists
        existing_profile = await db.profiles.find_one({"user_id": user_id})
        if existing_profile:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Profile already exists. Use update endpoint."
            )

        # Validate age
        if data.age < 13:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Users must be 13 years or older to create an account"
            )

        now = datetime.utcnow()

        # Create profile document
        profile_doc = {
            "user_id": user_id,
            "role": AccountRole.TEEN.value,
            "name": data.name,
            "age": data.age,
            "height": {"value": data.height.value, "unit": data.height.unit.value},
            "weight": {"value": data.weight.value, "unit": data.weight.unit.value},
            "icd10_code": data.icd10_code,
            "advisor_name": data.advisor_name,
            "created_at": now,
            "updated_at": now,
        }

        await db.profiles.insert_one(profile_doc)

        # Mark user profile as complete
        await db.users.update_one(
            {"user_id": user_id},
            {"$set": {"profile_complete": True, "updated_at": now}}
        )

        return UserProfile(
            user_id=user_id,
            email=user["email"],
            role=AccountRole.TEEN,
            name=data.name,
            age=data.age,
            height=data.height,
            weight=data.weight,
            icd10_code=data.icd10_code,
            advisor_name=data.advisor_name,
            profile_complete=True,
            created_at=now,
            updated_at=now,
        )

    async def create_parent_profile(self, user_id: str, data: ParentProfileCreate) -> UserProfile:
        """Create a parent profile."""
        db = get_database()

        # Get user and verify role
        user = await db.users.find_one({"user_id": user_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )

        if user.get("role") != AccountRole.PARENT.value:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User is not a parent account"
            )

        # Check if profile already exists
        existing_profile = await db.profiles.find_one({"user_id": user_id})
        if existing_profile:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Profile already exists. Use update endpoint."
            )

        now = datetime.utcnow()

        # Create profile document
        profile_doc = {
            "user_id": user_id,
            "role": AccountRole.PARENT.value,
            "name": data.name,
            "age": data.age,
            "height": {"value": data.height.value, "unit": data.height.unit.value} if data.height else None,
            "weight": {"value": data.weight.value, "unit": data.weight.unit.value} if data.weight else None,
            "icd10_code": None,
            "advisor_name": None,
            "created_at": now,
            "updated_at": now,
        }

        await db.profiles.insert_one(profile_doc)

        # Mark user profile as complete
        await db.users.update_one(
            {"user_id": user_id},
            {"$set": {"profile_complete": True, "updated_at": now}}
        )

        return UserProfile(
            user_id=user_id,
            email=user["email"],
            role=AccountRole.PARENT,
            name=data.name,
            age=data.age,
            height=data.height,
            weight=data.weight,
            icd10_code=None,
            advisor_name=None,
            profile_complete=True,
            created_at=now,
            updated_at=now,
        )

    async def get_profile(self, user_id: str) -> UserProfile:
        """Get user profile."""
        db = get_database()

        user = await db.users.find_one({"user_id": user_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )

        profile = await db.profiles.find_one({"user_id": user_id})
        if not profile:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Profile not found. Please complete profile setup."
            )

        # Convert height/weight to proper format
        height_data = None
        if profile.get("height"):
            height_data = HeightData(
                value=profile["height"]["value"],
                unit=profile["height"]["unit"]
            )

        weight_data = None
        if profile.get("weight"):
            weight_data = WeightData(
                value=profile["weight"]["value"],
                unit=profile["weight"]["unit"]
            )

        return UserProfile(
            user_id=user_id,
            email=user["email"],
            role=AccountRole(profile["role"]),
            name=profile["name"],
            age=profile.get("age"),
            height=height_data,
            weight=weight_data,
            icd10_code=profile.get("icd10_code"),
            advisor_name=profile.get("advisor_name"),
            profile_complete=True,
            created_at=profile["created_at"],
            updated_at=profile["updated_at"],
        )

    async def update_profile(self, user_id: str, data: ProfileUpdate) -> UserProfile:
        """Update user profile."""
        db = get_database()

        profile = await db.profiles.find_one({"user_id": user_id})
        if not profile:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Profile not found"
            )

        # Build update document
        update_fields = {"updated_at": datetime.utcnow()}

        if data.name is not None:
            update_fields["name"] = data.name
        if data.age is not None:
            if data.age < 13:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Age must be 13 or older"
                )
            update_fields["age"] = data.age
        if data.height is not None:
            update_fields["height"] = {"value": data.height.value, "unit": data.height.unit.value}
        if data.weight is not None:
            update_fields["weight"] = {"value": data.weight.value, "unit": data.weight.unit.value}
        if data.icd10_code is not None:
            # Only allow for teen accounts
            if profile["role"] == AccountRole.TEEN.value:
                update_fields["icd10_code"] = data.icd10_code if data.icd10_code else None
        if data.advisor_name is not None:
            # Only allow for teen accounts
            if profile["role"] == AccountRole.TEEN.value:
                update_fields["advisor_name"] = data.advisor_name if data.advisor_name else None

        await db.profiles.update_one(
            {"user_id": user_id},
            {"$set": update_fields}
        )

        return await self.get_profile(user_id)

    async def delete_profile(self, user_id: str) -> bool:
        """Delete user profile (soft delete would be better for production)."""
        db = get_database()

        result = await db.profiles.delete_one({"user_id": user_id})

        if result.deleted_count == 0:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Profile not found"
            )

        # Update user profile_complete status
        await db.users.update_one(
            {"user_id": user_id},
            {"$set": {"profile_complete": False, "updated_at": datetime.utcnow()}}
        )

        return True


# Singleton service instance
profile_service = ProfileService()
