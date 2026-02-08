"""Authentication API routes."""
from fastapi import APIRouter, Depends

from ..models.user import (
    UserSignUp,
    UserLogin,
    TokenResponse,
    AccountTypeSelection,
    EmailVerification,
    ResendVerification,
)
from ..services.auth_service import auth_service, get_current_user_id


router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/signup", response_model=TokenResponse)
async def signup(data: UserSignUp):
    """
    Register a new user.

    - **email**: Valid email address (must be unique)
    - **password**: Minimum 8 characters
    - **confirm_password**: Must match password
    - **role**: Account type (teen or parent)

    Sends verification email and returns JWT token.
    User must verify email before logging in.
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
