"""
Tests for the PostgreSQL-backed device registration flow.

All database interactions are mocked — no live Postgres required.
"""

import os
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock

os.environ.setdefault("JWT_SECRET", "test-secret-key-not-for-production")

import pytest
from fastapi import HTTPException

from services.auth_service import AuthService
from models.sql_models import User, PendingRegistration, AuthStatus, UserRole


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_user(**overrides):
    u = User()
    u.id = overrides.get("id", "user-1")
    u.email = overrides.get("email", "iasb-4208@smartboard.intelliattend.com")
    u.name = overrides.get("name", "SmartBoard IASB-4208")
    u.role = overrides.get("role", UserRole.BOARD)
    u.auth_status = overrides.get("auth_status", AuthStatus.ACTIVE)
    u.firebase_uid = overrides.get("firebase_uid", "firebase-uid-1")
    u.smart_board_id = overrides.get("smart_board_id", "IASB-4208")
    u.room_id = overrides.get("room_id", None)
    u.institution_id = overrides.get("institution_id", None)
    return u


def _mock_session(users=None, pendings=None):
    session = AsyncMock()

    def _exec_side_effect(statement):
        mock_result = MagicMock()
        stmt_str = str(statement)

        if "users" in stmt_str:
            mock_result.scalar_one_or_none.return_value = users
        elif "pending_registrations" in stmt_str:
            mock_result.scalar_one_or_none.return_value = pendings
        else:
            mock_result.scalar_one_or_none.return_value = None

        return mock_result

    session.execute.side_effect = _exec_side_effect
    session.flush = AsyncMock()
    session.add = MagicMock()
    session.delete = AsyncMock()
    return session


# ---------------------------------------------------------------------------
# Tests: register_initiate_pg
# ---------------------------------------------------------------------------


class TestRegisterInitiate:
    @pytest.mark.asyncio
    async def test_otp_required_for_new_board(self):
        user = _make_user(auth_status=AuthStatus.PENDING)
        session = _mock_session(users=user)

        result = await AuthService.register_initiate_pg(
            smart_board_id="IASB-4208",
            firebase_uid="firebase-uid-1",
            email="iasb-4208@smartboard.intelliattend.com",
            session=session,
        )

        assert result["status"] == "otp_required"
        assert result["is_registered"] is False
        assert result["smart_board_id"] == "IASB-4208"
        assert session.add.call_count >= 1

    @pytest.mark.asyncio
    async def test_already_registered_for_active_user(self):
        user = _make_user(auth_status=AuthStatus.ACTIVE, smart_board_id="IASB-4208")
        session = _mock_session(users=user)

        result = await AuthService.register_initiate_pg(
            smart_board_id="IASB-4208",
            firebase_uid="firebase-uid-1",
            email="iasb-4208@smartboard.intelliattend.com",
            session=session,
        )

        assert result["status"] == "already_registered"
        assert result["is_registered"] is True
        assert session.add.call_count == 0

    @pytest.mark.asyncio
    async def test_blocks_suspended_user(self):
        user = _make_user(auth_status=AuthStatus.SUSPENDED)
        session = _mock_session(users=user)

        with pytest.raises(HTTPException) as exc:
            await AuthService.register_initiate_pg(
                smart_board_id="IASB-4208",
                firebase_uid="firebase-uid-1",
                email="iasb-4208@smartboard.intelliattend.com",
                session=session,
            )

        assert exc.value.status_code == 403


# ---------------------------------------------------------------------------
# Tests: register_verify_pg
# ---------------------------------------------------------------------------


class TestRegisterVerify:
    @pytest.mark.asyncio
    async def test_invalid_otp_returns_400(self):
        session = _mock_session(pendings=None)

        with pytest.raises(HTTPException) as exc:
            await AuthService.register_verify_pg(
                smart_board_id="IASB-9999", otp="123456", session=session
            )

        assert exc.value.status_code == 400

    @pytest.mark.asyncio
    async def test_verify_increases_attempts_on_failure(self):
        pending = PendingRegistration()
        pending.id = "pending-1"
        pending.smart_board_id = "IASB-4208"
        pending.firebase_uid = "firebase-uid-1"
        pending.email = "iasb-4208@smartboard.intelliattend.com"
        pending.otp_hash = AuthService._hash_otp("654321")
        pending.otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
        pending.attempts = 0
        pending.locked_until = None

        session = _mock_session(pendings=pending)

        with pytest.raises(HTTPException) as exc:
            await AuthService.register_verify_pg(
                smart_board_id="IASB-4208", otp="123456", session=session
            )

        assert exc.value.status_code == 400
        assert pending.attempts == 1
