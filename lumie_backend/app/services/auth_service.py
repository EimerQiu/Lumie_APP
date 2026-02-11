"""Authentication service for user management."""
import uuid
import secrets
import logging
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
    EmailVerification,
)
from .email_service import email_service

logger = logging.getLogger(__name__)

# Import team service for processing pending invitations
# Avoid circular import by importing inside methods when needed


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

        # Check if signing up via invitation
        email_verified = False
        team_id_to_join = None

        if data.invitation_token:
            # Validate invitation token
            from .team_service import team_service
            payload = team_service.decode_invitation_token(data.invitation_token)

            if not payload:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid or expired invitation link"
                )

            # Verify email matches invitation
            if payload["email"].lower() != data.email.lower():
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"This invitation was sent to {payload['email']}. Please use that email address."
                )

            # Mark email as verified (they came via email invitation)
            email_verified = True
            team_id_to_join = payload["team_id"]
            logger.info(f"✅ User signing up via invitation to team {team_id_to_join}")

        # Create user
        user_id = str(uuid.uuid4())
        now = datetime.utcnow()

        # Generate verification token only if not verified via invitation
        if not email_verified:
            verification_token = secrets.token_urlsafe(32)
            verification_expires = now + timedelta(hours=24)
        else:
            verification_token = None
            verification_expires = None

        user_doc = {
            "user_id": user_id,
            "email": data.email.lower(),
            "hashed_password": get_password_hash(data.password),
            "role": data.role.value,
            "profile_complete": False,
            "email_verified": email_verified,
            "verification_token": verification_token,
            "verification_token_expires": verification_expires,
            "created_at": now,
            "updated_at": now,
        }

        await db.users.insert_one(user_doc)

        # If signed up via invitation, auto-accept the invitation
        if team_id_to_join:
            try:
                from .team_service import team_service

                # Check if there's a pending invitation for this email
                pending_invitation = await db.pending_invitations.find_one({
                    "team_id": team_id_to_join,
                    "email": data.email.lower()
                })

                if pending_invitation:
                    # Create team membership
                    await db.team_members.insert_one({
                        "team_id": team_id_to_join,
                        "user_id": user_id,
                        "role": "member",
                        "status": "member",
                        "invited_by": pending_invitation["invited_by"],
                        "invited_at": pending_invitation["invited_at"],
                        "joined_at": now
                    })

                    # Delete the pending invitation
                    await db.pending_invitations.delete_one({"_id": pending_invitation["_id"]})

                    logger.info(f"✅ Auto-accepted invitation: User {user_id} joined team {team_id_to_join}")
                else:
                    logger.warning(f"⚠️ No pending invitation found for {data.email.lower()} in team {team_id_to_join}")
            except Exception as e:
                logger.error(f"❌ Failed to auto-accept invitation: {str(e)}", exc_info=True)
                # Don't fail signup if auto-accept fails

        # Process any other pending team invitations for this email
        try:
            from .team_service import team_service
            invitations_count = await team_service.process_pending_invitations(user_id, data.email.lower())
            if invitations_count > 0:
                logger.info(f"✅ Processed {invitations_count} additional pending team invitation(s) for {data.email.lower()}")
        except Exception as e:
            logger.error(f"❌ Failed to process pending invitations: {str(e)}", exc_info=True)
            # Don't fail signup if invitation processing fails

        # Send verification email only if not verified via invitation
        if not email_verified:
            try:
                result = email_service.send_verification_email(
                    to_email=data.email.lower(),
                    verification_token=verification_token
                )
                if result:
                    logger.info(f"✅ Verification email sent to {data.email.lower()}")
                else:
                    logger.error(f"❌ Failed to send verification email to {data.email.lower()} - email service returned False")
            except Exception as e:
                logger.error(f"❌ Exception sending verification email to {data.email.lower()}: {str(e)}", exc_info=True)
                # Don't fail signup if email sending fails

        # Generate token
        access_token = create_access_token(
            data={"sub": user_id, "email": data.email.lower()}
        )

        return TokenResponse(
            access_token=access_token,
            user_id=user_id,
            email=data.email.lower(),
            role=data.role,
            profile_complete=False,
            email_verified=email_verified,
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

        # Check email verification
        if not user.get("email_verified", False):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Please verify your email before logging in. Check your inbox for the verification link."
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
            email_verified=True,
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
            email_verified=user.get("email_verified", False),
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

    async def verify_email(self, data: EmailVerification) -> dict:
        """Verify user email with token."""
        db = get_database()

        # Find user with matching token
        user = await db.users.find_one({"verification_token": data.token})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired verification token"
            )

        # Check if token has expired
        if user.get("verification_token_expires"):
            expires = user["verification_token_expires"]
            if datetime.utcnow() > expires:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Verification token has expired. Please request a new one."
                )

        # Check if already verified
        if user.get("email_verified"):
            return {
                "message": "Email already verified",
                "email": user["email"]
            }

        # Mark email as verified
        await db.users.update_one(
            {"user_id": user["user_id"]},
            {
                "$set": {
                    "email_verified": True,
                    "verification_token": None,
                    "verification_token_expires": None,
                    "updated_at": datetime.utcnow(),
                }
            }
        )

        return {
            "message": "Email verified successfully",
            "email": user["email"]
        }

    async def resend_verification_email(self, email: str) -> dict:
        """Resend verification email to user."""
        db = get_database()

        # Find user
        user = await db.users.find_one({"email": email.lower()})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Account not found"
            )

        # Check if already verified
        if user.get("email_verified"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already verified"
            )

        # Generate new verification token
        verification_token = secrets.token_urlsafe(32)
        verification_expires = datetime.utcnow() + timedelta(hours=24)

        # Update user with new token
        await db.users.update_one(
            {"user_id": user["user_id"]},
            {
                "$set": {
                    "verification_token": verification_token,
                    "verification_token_expires": verification_expires,
                    "updated_at": datetime.utcnow(),
                }
            }
        )

        # Send verification email
        try:
            email_service.send_verification_email(
                to_email=email.lower(),
                verification_token=verification_token
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to send verification email"
            )

        return {
            "message": "Verification email sent",
            "email": email.lower()
        }


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
