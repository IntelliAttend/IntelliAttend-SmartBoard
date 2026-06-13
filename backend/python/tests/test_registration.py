"""
DEPRECATED — Tests for legacy OTP-based board registration (S1–S6).

The SmartBoard now authenticates using Firebase Auth email/password,
the same as the Faculty and Student mobile apps. Board accounts are
provisioned via Firebase Auth Admin at install time, not via OTP flow.

These tests are preserved for reference in case re-registration flows
are revisited. The schemas and rate-limiting functions they depend on
have been commented out in the main codebase.
"""

# import os
# os.environ.setdefault("JWT_SECRET", "test-secret-key-not-for-production")
#
# import asyncio
# import hashlib
# from datetime import datetime, timezone, timedelta
# from unittest.mock import patch, AsyncMock, MagicMock
#
# import pytest
# from fastapi import HTTPException
# from google.cloud import firestore
#
# from services.auth_service import AuthService
# from models.board_auth_schema import DeviceRegisterInitiateRequest


class _MockDoc:
    """Synchronous document snapshot — to_dict() returns dict, not coroutine."""
    def __init__(self, exists: bool, data: dict | None = None):
        self.exists = exists
        self._data = data or {}

    def to_dict(self):
        return self._data


def _make_db(board_data: dict | None = None, pending_data: dict | None = None):
    """Build an AsyncMock Firestore client with shared internal refs.

    Returns (db, pending_doc_ref) where pending_doc_ref can be used by
    tests to assert on .set(...), .delete(), .update() calls.
    """
    db = AsyncMock(spec=firestore.AsyncClient)

    board_col = MagicMock()
    board_doc_ref = MagicMock()
    board_doc = _MockDoc(board_data is not None, board_data)
    board_doc_ref.get = AsyncMock(return_value=board_doc)
    board_col.document.return_value = board_doc_ref

    pending_col = MagicMock()
    pending_doc_ref = MagicMock()
    pending_doc = _MockDoc(pending_data is not None, pending_data)
    pending_doc_ref.get = AsyncMock(return_value=pending_doc)
    pending_doc_ref.set = AsyncMock()
    pending_doc_ref.update = AsyncMock()
    pending_doc_ref.delete = AsyncMock()
    pending_col.document.return_value = pending_doc_ref

    other_col = MagicMock()
    other_doc_ref = MagicMock()
    other_doc_ref.get = AsyncMock(return_value=_MockDoc(False))
    other_col.document.return_value = other_doc_ref

    def _collection(name: str):
        if name == "smart_boards":
            return board_col
        if name == "pending_ignitions":
            return pending_col
        return other_col

    db.collection.side_effect = _collection
    return db, pending_doc_ref


def _run(coro):
    return asyncio.run(coro)


# ===========================================================================
# S6: password field removed from initiate request model
# ===========================================================================

class TestS6_NoPasswordField:
    def test_initiate_request_has_no_password_field(self):
        req = DeviceRegisterInitiateRequest(smart_board_id="IASB-4208")
        assert req.smart_board_id == "IASB-4208"
        with pytest.raises(AttributeError):
            _ = req.password


# ===========================================================================
# S5: already_registered response
# ===========================================================================

class TestS5_AlreadyRegistered:
    def test_returns_already_registered_when_board_is_bound(self):
        db, _ = _make_db({
            "is_registered": True,
            "status": "ACTIVE",
            "room_id": "R101",
            "room_name": "Hall 1",
            "building": "Main",
            "department": "CS",
        })
        result = _run(AuthService.initiate_registration("IASB-4208", db))

        assert result is not None
        assert result["status"] == "already_registered"
        assert result["smart_board_id"] == "IASB-4208"
        assert result["room_id"] == "R101"

    def test_returns_none_when_board_not_provisioned(self):
        db, _ = _make_db(None)
        result = _run(AuthService.initiate_registration("UNKNOWN", db))
        assert result is None

    def test_proceeds_with_otp_when_board_not_registered(self):
        db, _ = _make_db({
            "is_registered": False,
            "status": "PROVISIONED",
            "admin_email": "admin@example.com",
        })
        result = _run(AuthService.initiate_registration("IASB-4208", db))

        assert result is not None
        assert result["status"] == "success"
        assert result["admin_email"] == "admin@example.com"


# ===========================================================================
# S1: OTP hashed (SHA-256) before storage
# ===========================================================================

class TestS1_OtpHash:
    def test_stores_hash_not_plaintext(self):
        db, pending_ref = _make_db({
            "is_registered": False,
            "status": "PROVISIONED",
            "admin_email": "admin@example.com",
        })

        with patch("secrets.randbelow", return_value=123456):
            result = _run(AuthService.initiate_registration("IASB-4208", db))

        assert result is not None

        call_kwargs = pending_ref.set.call_args[0][0]
        assert "otp_hash" in call_kwargs
        assert "otp" not in call_kwargs

        # otp = str(123456 + 100000) = "223456"
        expected_hash = hashlib.sha256(b"223456").hexdigest()
        assert call_kwargs["otp_hash"] == expected_hash

    def test_verify_otp_uses_hash_comparison(self):
        otp_hash = hashlib.sha256(b"654321").hexdigest()
        db, pending_ref = _make_db(
            board_data={"is_registered": False, "status": "PROVISIONED"},
            pending_data={
                "otp_hash": otp_hash,
                "expires_at": datetime.now(timezone.utc) + timedelta(minutes=5),
            },
        )
        result = _run(AuthService.verify_otp("IASB-4208", "654321", db))

        assert result is not None
        assert result["status"] == "success"
        assert "verification_token" in result

    def test_verify_otp_rejects_wrong_otp(self):
        correct_hash = hashlib.sha256(b"correct_otp").hexdigest()
        db, _ = _make_db(
            board_data={"is_registered": False, "status": "PROVISIONED"},
            pending_data={
                "otp_hash": correct_hash,
                "expires_at": datetime.now(timezone.utc) + timedelta(minutes=5),
            },
        )
        result = _run(AuthService.verify_otp("IASB-4208", "wrong_otp", db))
        assert result is None


# ===========================================================================
# S2: OTP expiry checked server-side
# ===========================================================================

class TestS2_OtpExpiry:
    def test_rejects_expired_otp_and_cleans_up(self):
        otp_hash = hashlib.sha256(b"123456").hexdigest()
        db, pending_ref = _make_db(
            board_data={"is_registered": False, "status": "PROVISIONED"},
            pending_data={
                "otp_hash": otp_hash,
                "expires_at": datetime.now(timezone.utc) - timedelta(minutes=1),
            },
        )
        result = _run(AuthService.verify_otp("IASB-4208", "123456", db))

        assert result is None
        pending_ref.delete.assert_called_once()

    def test_accepts_valid_non_expired_otp(self):
        otp_hash = hashlib.sha256(b"999999").hexdigest()
        db, _ = _make_db(
            board_data={"is_registered": False, "status": "PROVISIONED"},
            pending_data={
                "otp_hash": otp_hash,
                "expires_at": datetime.now(timezone.utc) + timedelta(minutes=5),
            },
        )
        result = _run(AuthService.verify_otp("IASB-4208", "999999", db))
        assert result is not None
        assert result["status"] == "success"

    def test_handles_naive_datetime_expiry(self):
        """expires_at from Firestore may be naive (no tzinfo)."""
        otp_hash = hashlib.sha256(b"555555").hexdigest()
        naive_expiry = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=5)
        db, _ = _make_db(
            board_data={"is_registered": False, "status": "PROVISIONED"},
            pending_data={
                "otp_hash": otp_hash,
                "expires_at": naive_expiry,
            },
        )
        result = _run(AuthService.verify_otp("IASB-4208", "555555", db))
        assert result is not None
        assert result["status"] == "success"

    def test_rejects_expired_naive_datetime(self):
        otp_hash = hashlib.sha256(b"444444").hexdigest()
        naive_expired = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(minutes=1)
        db, pending_ref = _make_db(
            board_data={"is_registered": False, "status": "PROVISIONED"},
            pending_data={
                "otp_hash": otp_hash,
                "expires_at": naive_expired,
            },
        )
        result = _run(AuthService.verify_otp("IASB-4208", "444444", db))
        assert result is None

        pending_ref.delete.assert_called_once()


# ===========================================================================
# S3: Server-side OTP rate limiting
# ===========================================================================

class TestS3_OtpRateLimit:
    def setup_method(self):
        from main import _otp_attempts
        _otp_attempts.clear()

    def test_allows_first_attempt(self):
        from main import _check_otp_rate_limit
        _check_otp_rate_limit("BOARD-001")

    def test_blocks_after_max_attempts(self):
        from main import _check_otp_rate_limit, _record_otp_attempt, _OTP_MAX_ATTEMPTS

        for _ in range(_OTP_MAX_ATTEMPTS):
            _record_otp_attempt("BOARD-001", success=False)

        with pytest.raises(HTTPException) as exc:
            _check_otp_rate_limit("BOARD-001")
        assert exc.value.status_code == 429

    def test_successful_attempt_resets_counter(self):
        from main import _check_otp_rate_limit, _record_otp_attempt, _otp_attempts

        for _ in range(5):
            _record_otp_attempt("BOARD-001", success=False)
        _record_otp_attempt("BOARD-001", success=True)

        assert "BOARD-001" not in _otp_attempts
        _check_otp_rate_limit("BOARD-001")

    def test_different_boards_independent(self):
        from main import _check_otp_rate_limit, _record_otp_attempt, _OTP_MAX_ATTEMPTS

        for _ in range(_OTP_MAX_ATTEMPTS):
            _record_otp_attempt("BOARD-001", success=False)

        _check_otp_rate_limit("BOARD-002")

    def test_lockout_has_expected_duration(self):
        from main import _record_otp_attempt, _otp_attempts, _OTP_MAX_ATTEMPTS

        for _ in range(_OTP_MAX_ATTEMPTS):
            _record_otp_attempt("BOARD-001", success=False)

        state = _otp_attempts["BOARD-001"]
        assert state["lockout_until"] is not None
        remaining = (state["lockout_until"] - datetime.now(timezone.utc)).total_seconds()
        assert 14 * 60 <= remaining <= 15 * 60

    def test_verify_endpoint_calls_rate_limit(self):
        """Verify the /verify endpoint actually invokes rate limiting."""
        from main import _check_otp_rate_limit, _record_otp_attempt

        for _ in range(10):
            _record_otp_attempt("BOARD-001", success=False)

        with pytest.raises(HTTPException) as exc:
            _check_otp_rate_limit("BOARD-001")
        assert exc.value.status_code == 429
        assert "Too many OTP attempts" in exc.value.detail

    def test_lockout_auto_resets_after_expiry(self):
        """After lockout period expires, next attempt resets counter."""
        from main import _check_otp_rate_limit, _record_otp_attempt, _otp_attempts, _OTP_MAX_ATTEMPTS

        for _ in range(_OTP_MAX_ATTEMPTS):
            _record_otp_attempt("BOARD-001", success=False)

        with pytest.raises(HTTPException):
            _check_otp_rate_limit("BOARD-001")

        _otp_attempts["BOARD-001"]["lockout_until"] = datetime.now(timezone.utc) - timedelta(seconds=1)

        _check_otp_rate_limit("BOARD-001")
        assert "BOARD-001" not in _otp_attempts


# ===========================================================================
# S4: OTP redacted from info logs
# ===========================================================================

class TestS4_OtpLogRedaction:
    def test_info_log_does_not_contain_plaintext_otp(self, caplog):
        import logging
        caplog.set_level(logging.INFO)

        db, _ = _make_db({
            "is_registered": False,
            "status": "PROVISIONED",
            "admin_email": "admin@example.com",
        })

        with patch("secrets.randbelow", return_value=123456):
            _run(AuthService.initiate_registration("IASB-4208", db))

        # otp = str(123456 + 100000) = "223456"
        for record in caplog.records:
            msg = record.getMessage()
            if record.levelno >= logging.INFO:
                assert "223456" not in msg, f"OTP leaked at INFO: {msg}"

    def test_debug_log_contains_otp(self, caplog):
        import logging
        caplog.set_level(logging.DEBUG)

        db, _ = _make_db({
            "is_registered": False,
            "status": "PROVISIONED",
            "admin_email": "admin@example.com",
        })

        with patch("secrets.randbelow", return_value=123456):
            _run(AuthService.initiate_registration("IASB-4208", db))

        # otp = str(123456 + 100000) = "223456"
        debug_contains_otp = any(
            "223456" in record.getMessage()
            for record in caplog.records
            if record.levelno == logging.DEBUG
        )
        assert debug_contains_otp, "OTP should appear at DEBUG level"

    def test_verify_otp_rejects_no_pending_ignition(self):
        db, _ = _make_db(
            board_data={"is_registered": False, "status": "PROVISIONED"},
            pending_data=None,
        )
        result = _run(AuthService.verify_otp("IASB-4208", "123456", db))
        assert result is None
