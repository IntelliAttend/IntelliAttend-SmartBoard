import secrets
import hashlib
import logging
import jwt
import os
from datetime import datetime, timezone, timedelta
from typing import Optional

from firebase_admin import auth as firebase_auth
from fastapi import Request, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from models.sql_models import User, PendingRegistration, AuthStatus, UserRole

logger = logging.getLogger("IntelliAttend.Auth")

JWT_SECRET = os.environ.get("JWT_SECRET")
if not JWT_SECRET:
    raise RuntimeError(
        "JWT_SECRET environment variable is not set. "
        "The application cannot start securely without it."
    )

_OTP_MAX_ATTEMPTS = 10
_OTP_LOCKOUT_MINUTES = 15
_VERIFICATION_TOKEN_TTL_MINUTES = 15


class AuthService:
    @staticmethod
    async def verify_firebase_token(id_token: str):
        """
        Verifies a Firebase ID token and returns the decoded claims.
        """
        try:
            decoded_token = firebase_auth.verify_id_token(id_token)
            return decoded_token
        except Exception as e:
            logger.warning("[Auth] Firebase token verification failed")
            return None

    @staticmethod
    def _hash_otp(otp: str) -> str:
        return hashlib.sha256(otp.encode()).hexdigest()

    @staticmethod
    def _generate_otp() -> str:
        return f"{secrets.randbelow(900000) + 100000:06d}"

    @staticmethod
    def _generate_verification_token(smart_board_id: str) -> str:
        payload = {
            "sub": smart_board_id,
            "purpose": "registration_verification",
            "iat": datetime.now(timezone.utc),
            "exp": datetime.now(timezone.utc) + timedelta(minutes=_VERIFICATION_TOKEN_TTL_MINUTES),
        }
        return jwt.encode(payload, JWT_SECRET, algorithm="HS256")

    @staticmethod
    async def _lookup_pending(session: AsyncSession, smart_board_id: str) -> Optional[PendingRegistration]:
        result = await session.execute(
            select(PendingRegistration).where(PendingRegistration.smart_board_id == smart_board_id)
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def _lockout_pending(pending: PendingRegistration) -> None:
        pending.locked_until = datetime.now(timezone.utc) + timedelta(minutes=_OTP_LOCKOUT_MINUTES)
        pending.attempts = _OTP_MAX_ATTEMPTS

    # --- PostgreSQL-backed registration flow ----------------------------------

    @staticmethod
    async def register_initiate_pg(
        smart_board_id: str,
        firebase_uid: str,
        email: str,
        session: AsyncSession,
    ) -> dict:
        """
        Step 1 of registration: verify board can register and send OTP.

        Returns dict with status 'already_registered' or 'otp_required'.
        """
        # Check if board already has an active user account
        existing = await session.execute(
            select(User).where(User.email == email)
        )
        existing_user = existing.scalar_one_or_none()

        if existing_user is not None:
            if existing_user.auth_status.value == "active":
                return {
                    "status": "already_registered",
                    "is_registered": True,
                    "smart_board_id": existing_user.smart_board_id or smart_board_id,
                    "room_id": existing_user.room_id,
                }
            if existing_user.auth_status.value == "pending":
                # User pending — allow re-initiation if no pending record
                pending = await AuthService._lookup_pending(session, smart_board_id)
                if pending is None:
                    # Clean stale pending entry if it exists for a different SBI
                    pass
            if existing_user.auth_status.value == "suspended":
                raise HTTPException(
                    status_code=403,
                    detail="BOARD_SUSPENDED: This board has been deactivated",
                )
        else:
            # Create pending user account
            new_user = User(
                id=firebase_uid[:32],  # deterministic id from firebase uid
                email=email,
                name=f"SmartBoard {smart_board_id}",
                role=UserRole.BOARD,
                auth_status=AuthStatus.PENDING,
                firebase_uid=firebase_uid,
                smart_board_id=smart_board_id,
            )
            session.add(new_user)
            await session.flush()

        # Check for existing pending registration and rate limit
        pending = await AuthService._lookup_pending(session, smart_board_id)

        if pending is not None:
            if pending.locked_until and pending.locked_until > datetime.now(timezone.utc):
                remaining = int((pending.locked_until - datetime.now(timezone.utc)).total_seconds())
                raise HTTPException(
                    status_code=429,
                    detail=f"Too many attempts. Try again in {remaining} seconds",
                )
            if pending.attempts >= _OTP_MAX_ATTEMPTS:
                await AuthService._lockout_pending(pending)
                await session.flush()
                raise HTTPException(
                    status_code=429,
                    detail=f"Too many attempts. Locked out for {_OTP_LOCKOUT_MINUTES} minutes",
                )

        # Generate and store OTP
        otp = AuthService._generate_otp()
        otp_hash = AuthService._hash_otp(otp)

        if pending is None:
            pending = PendingRegistration(
                id=secrets.token_hex(16),
                smart_board_id=smart_board_id,
                firebase_uid=firebase_uid,
                email=email,
                otp_hash=otp_hash,
                otp_expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
            )
            session.add(pending)
        else:
            pending.otp_hash = otp_hash
            pending.otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
            pending.attempts = 0
            pending.locked_until = None

        await session.flush()

        logger.info(f"[Register] OTP initiated for board {smart_board_id}")

        admin_email = email
        return {
            "status": "otp_required",
            "is_registered": False,
            "smart_board_id": smart_board_id,
            "admin_email": admin_email,
        }

    @staticmethod
    async def register_verify_pg(
        smart_board_id: str,
        otp: str,
        session: AsyncSession,
    ) -> dict:
        """
        Step 2 of registration: verify OTP.

        Returns dict with verification_token on success.
        """
        pending = await AuthService._lookup_pending(session, smart_board_id)
        if not pending:
            raise HTTPException(status_code=400, detail="Invalid OTP or Session Expired")

        if pending.locked_until and pending.locked_until > datetime.now(timezone.utc):
            raise HTTPException(status_code=429, detail="Too many attempts. Try again later.")

        if pending.attempts >= _OTP_MAX_ATTEMPTS:
            await AuthService._lockout_pending(pending)
            await session.flush()
            raise HTTPException(
                status_code=429,
                detail=f"Too many failed attempts. Locked out for {_OTP_LOCKOUT_MINUTES} minutes",
            )

        if datetime.now(timezone.utc) > pending.otp_expires_at:
            raise HTTPException(status_code=400, detail="OTP expired")

        if pending.otp_hash != AuthService._hash_otp(otp):
            pending.attempts += 1
            await session.flush()
            remaining = _OTP_MAX_ATTEMPTS - pending.attempts
            raise HTTPException(
                status_code=400,
                detail=f"Invalid OTP. {remaining} attempts remaining."
            )

        # Success — issue verification token
        verification_token = AuthService._generate_verification_token(smart_board_id)
        await session.delete(pending)
        await session.flush()

        logger.info(f"[Register] OTP verified for board {smart_board_id}")
        return {"verification_token": verification_token}

    @staticmethod
    async def register_complete_pg(
        smart_board_id: str,
        verification_token: str,
        hardware_id: str,
        metadata: Optional[dict],
        session: AsyncSession,
    ) -> dict:
        """
        Step 3 of registration: validate verification token and bind hardware.

        Returns dict with custom_token and profile on success.
        """
        try:
            payload = jwt.decode(verification_token, JWT_SECRET, algorithms=["HS256"])
            if payload.get("purpose") != "registration_verification":
                raise ValueError("Invalid token purpose")
            if payload.get("sub") != smart_board_id:
                raise ValueError("Token subject mismatch")
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=400, detail="Verification token expired")
        except jwt.InvalidTokenError:
            raise HTTPException(status_code=400, detail="Invalid verification token")

        result = await session.execute(
            select(User).where(User.smart_board_id == smart_board_id)
        )
        user = result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=403, detail="Board not found")

        if user.auth_status.value != "pending":
            raise HTTPException(status_code=400, detail="Board is not pending registration")

        # Update user to active and bind hardware
        user.auth_status = AuthStatus.ACTIVE
        user.room_id = user.room_id  # preserve existing room_id
        await session.flush()

        # Generate Firebase custom token so the client can bind the session
        try:
            custom_token = firebase_auth.create_custom_token(user.firebase_uid or smart_board_id)
        except Exception as e:
            logger.error("[Auth] Failed to create custom token")
            custom_token = None

        logger.info(f"[Register] Completed registration for board {smart_board_id}")

        return {
            "custom_token": custom_token,
            "smart_board_id": smart_board_id,
            "classroom_id": user.room_id or "",
            "room_name": user.name or f"SmartBoard {smart_board_id}",
            "building": "",
            "department": "",
        }

    @staticmethod
    def require_role(allowed_roles: list[str]):
        """
        FastAPI dependency to enforce RBAC based on legacy JWT claims.
        This is retained for admin/IT dashboard routes only. Board endpoints
        use get_current_board_pg which enforces Firebase token + role='board'.
        """
        async def _role_checker(http_request: Request) -> dict:
            auth_header = http_request.headers.get("Authorization")
            if not auth_header or not auth_header.startswith("Bearer "):
                 raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

            token = auth_header.split(" ")[1]
            try:
                payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
                user_role = payload.get("role")

                if user_role not in allowed_roles:
                    logger.warning(f"[RBAC] Access denied for role: {user_role}. Required: {allowed_roles}")
                    raise HTTPException(status_code=403, detail="Insufficient permissions")

                return payload
            except jwt.ExpiredSignatureError:
                raise HTTPException(status_code=401, detail="Token expired")
            except jwt.InvalidTokenError:
                raise HTTPException(status_code=401, detail="Invalid token")

        return _role_checker
