"""Authentication service for user management."""
import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from ..core.database import get_database
from ..core.security import (
    verify_password,
    get_password_hash,
    create_access_token,
    decode_access_token,
)
from ..core.config import settings
from ..models.user import (
    UserSignUp,
    UserLogin,
    TokenResponse,
    UserInDB,
    AccountRole,
    AccountTypeSelection,
)


security = HTTPBearer()


class AuthService:
    """Service for handling user authentication."""

    async def signup(self, data: UserSignUp) -> TokenResponse:
        """Register a new user."""
        db = get_database()

        # Validate passwords match
        if data.password != data.confirm_password:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Passwords do not match"
            )

        # Check if email already exists
        existing_user = await db.users.find_one({"email": data.email.lower()})
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered. Please log in."
            )

        # Create user
        user_id = str(uuid.uuid4())
        now = datetime.utcnow()

        user_doc = {
            "user_id": user_id,
            "email": data.email.lower(),
            "hashed_password": get_password_hash(data.password),
            "role": None,  # Will be set during account type selection
            "profile_complete": False,
            "created_at": now,
            "updated_at": now,
        }

        await db.users.insert_one(user_doc)

        # Generate token
        access_token = create_access_token(
            data={"sub": user_id, "email": data.email.lower()}
        )

        return TokenResponse(
            access_token=access_token,
            user_id=user_id,
            email=data.email.lower(),
            role=None,
            profile_complete=False,
        )

    async def login(self, data: UserLogin) -> TokenResponse:
        """Authenticate user and return token."""
        db = get_database()

        # Find user
        user = await db.users.find_one({"email": data.email.lower()})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Account not found. Please sign up."
            )

        # Verify password
        if not verify_password(data.password, user["hashed_password"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect password"
            )

        # Generate token
        access_token = create_access_token(
            data={"sub": user["user_id"], "email": user["email"]}
        )

        return TokenResponse(
            access_token=access_token,
            user_id=user["user_id"],
            email=user["email"],
            role=AccountRole(user["role"]) if user.get("role") else None,
            profile_complete=user.get("profile_complete", False),
        )

    async def select_account_type(self, user_id: str, data: AccountTypeSelection) -> TokenResponse:
        """Set account type after signup."""
        db = get_database()

        # Get user
        user = await db.users.find_one({"user_id": user_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )

        # Check if role already set
        if user.get("role"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Account type already selected"
            )

        # Update role
        await db.users.update_one(
            {"user_id": user_id},
            {
                "$set": {
                    "role": data.role.value,
                    "updated_at": datetime.utcnow(),
                }
            }
        )

        # Generate new token with role
        access_token = create_access_token(
            data={"sub": user_id, "email": user["email"]}
        )

        return TokenResponse(
            access_token=access_token,
            user_id=user_id,
            email=user["email"],
            role=data.role,
            profile_complete=False,
        )

    async def get_current_user(self, user_id: str) -> UserInDB:
        """Get current user by ID."""
        db = get_database()
        user = await db.users.find_one({"user_id": user_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        return UserInDB(**user)


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> str:
    """Dependency to get current user ID from JWT token."""
    token = credentials.credentials
    payload = decode_access_token(token)

    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user_id


# Singleton service instance
auth_service = AuthService()
