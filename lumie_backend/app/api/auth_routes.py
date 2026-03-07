"""Authentication API routes."""
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..models.user import (
    UserSignUp,
    UserLogin,
    TokenResponse,
    AccountTypeSelection,
    EmailVerification,
    ResendVerification,
)
from ..services.auth_service import auth_service, get_current_user_id
from ..core.database import get_database


class DeviceTokenRequest(BaseModel):
    device_token: str = Field(..., min_length=1)


router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/signup", response_model=TokenResponse)
async def signup(data: UserSignUp):
    """
    Register a new user.

    - **email**: Valid email address (must be unique)
    - **password**: Minimum 8 characters
    - **confirm_password**: Must match password
    - **role**: Account type (teen or parent)
    - **invitation_token**: Optional - if provided, email is auto-verified and user auto-joins team

    **Regular Signup (no invitation_token):**
    - Sends verification email
    - User must verify email before logging in

    **Invitation Signup (with invitation_token):**
    - Email is automatically verified (came via email invitation)
    - User is automatically added to the team
    - No verification email needed - can log in immediately
    """
    return await auth_service.signup(data)


@router.post("/login", response_model=TokenResponse)
async def login(data: UserLogin):
    """
    Authenticate user and get access token.

    - **email**: Registered email address
    - **password**: Account password

    Returns JWT token and user info.
    """
    return await auth_service.login(data)


@router.post("/account-type", response_model=TokenResponse)
async def select_account_type(
    data: AccountTypeSelection,
    user_id: str = Depends(get_current_user_id)
):
    """
    Select account type after signup.

    Must be called after signup but before profile creation.

    - **role**: Either "teen" or "parent"

    This choice cannot be changed later.
    """
    return await auth_service.select_account_type(user_id, data)


@router.get("/me", response_model=TokenResponse)
async def get_current_user_info(user_id: str = Depends(get_current_user_id)):
    """
    Get current authenticated user info.

    Returns user details from token.
    """
    user = await auth_service.get_current_user(user_id)
    return TokenResponse(
        access_token="",  # Not returned on /me endpoint
        user_id=user.user_id,
        email=user.email,
        role=user.role,
        profile_complete=user.profile_complete,
        email_verified=user.email_verified,
    )


@router.post("/save-device-token")
async def save_device_token(
    data: DeviceTokenRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Save or update the device push token for the current user.
    Last-write-wins: overwrites any previous token.
    """
    db = get_database()
    from datetime import datetime
    await db.users.update_one(
        {"user_id": user_id},
        {"$set": {
            "device_token": data.device_token,
            "updated_at": datetime.utcnow(),
        }}
    )
    return {"message": "Device token saved"}


@router.delete("/device-token")
async def delete_device_token(
    user_id: str = Depends(get_current_user_id),
):
    """Remove device token on logout."""
    db = get_database()
    from datetime import datetime
    await db.users.update_one(
        {"user_id": user_id},
        {"$set": {
            "device_token": None,
            "updated_at": datetime.utcnow(),
        }}
    )
    return {"message": "Device token removed"}


@router.post("/verify-email")
async def verify_email(data: EmailVerification):
    """
    Verify user email with verification token.

    - **token**: Verification token sent to user's email

    Marks the email as verified and allows user to log in.
    """
    return await auth_service.verify_email(data)


@router.post("/resend-verification")
async def resend_verification(data: ResendVerification):
    """
    Resend verification email to user.

    - **email**: Email address to resend verification to

    Generates a new verification token and sends a new email.
    """
    return await auth_service.resend_verification_email(data.email)
