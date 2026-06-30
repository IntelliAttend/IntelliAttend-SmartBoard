import logging
from typing import Optional

from fastapi import Header, HTTPException, status, Request, Depends
from firebase_admin import auth as firebase_auth
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from models.sql_models import User

logger = logging.getLogger("IntelliAttend")


# --- Shared helpers -----------------------------------------------------------


async def verify_firebase_token(authorization: Optional[str]) -> dict:
    """Extract and verify Firebase ID token from Authorization header."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="AUTH_FAILED: Missing or invalid Authorization header",
        )

    id_token = authorization.split(" ")[1]

    try:
        decoded_token = firebase_auth.verify_id_token(id_token)
    except Exception as e:
        logger.error(f"[Auth] Firebase token verification failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="AUTH_FAILED: Invalid Firebase ID token",
        )

    return decoded_token


# --- PostgreSQL-based board auth ----------------------------------------------
#
# Looks up board user by email in the 'users' table with role='board'
# and auth_status='active'. Supports boards that are pending registration
# as well as fully active boards.


async def get_current_board_pg(
    request: Request,
    session: AsyncSession = Depends(get_db),
    authorization: str = Header(default=None),
) -> dict:
    """
    PostgreSQL-backed Firebase Auth dependency for SmartBoard endpoints.

    Validates Firebase ID token, looks up board user by email in the
    'users' table, verifies role='board' and auth_status='active'.
    """
    decoded_token = await verify_firebase_token(authorization)

    email = decoded_token.get("email")
    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="AUTH_FAILED: No email claim in Firebase token",
        )

    result = await session.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="BOARD_NOT_FOUND: No board linked to this email",
        )

    if user.role.value != "board":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="INSUFFICIENT_PERMISSIONS: User role is not 'board'",
        )

    if user.auth_status.value != "active":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="BOARD_SUSPENDED: This board has been deactivated",
        )

    return {
        "user_id": user.id,
        "email": user.email,
        "name": user.name,
        "room_id": user.room_id,
        "institution_id": user.institution_id,
        "auth_status": user.auth_status.value,
        "smart_board_id": user.smart_board_id,
    }
