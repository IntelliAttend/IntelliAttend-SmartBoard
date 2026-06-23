"""
Tests for core backend services — auth, cache, session, and alert logic.
Does NOT require Firestore or Redis — all dependencies are mocked.
"""

import os

os.environ.setdefault("JWT_SECRET", "test-secret-key-not-for-production")
os.environ["REDIS_URL"] = ""  # Prevent Redis connection attempts in tests

import time
import json
from datetime import datetime, timezone, timedelta
from unittest.mock import patch, AsyncMock, MagicMock

import jwt
import pytest
from fastapi import HTTPException, Request

from services.auth_service import AuthService
from services.cache_service import CacheService
from services.session_service import SessionService
from services.alert_service import AlertService


# ===========================================================================
# JWT / Auth Service Tests
# ===========================================================================

class TestAuthServiceJWT:
    def test_jwt_secret_is_loaded(self):
        import services.auth_service as svc
        assert len(svc.JWT_SECRET) > 0

    def test_jwt_encode_and_decode(self):
        payload = {"sub": "board-001", "role": "smart_board", "iat": int(time.time())}
        token = jwt.encode(payload, os.environ["JWT_SECRET"], algorithm="HS256")
        decoded = jwt.decode(token, os.environ["JWT_SECRET"], algorithms=["HS256"])
        assert decoded["sub"] == "board-001"
        assert decoded["role"] == "smart_board"

    def test_expired_token_is_rejected(self):
        payload = {
            "sub": "board-001",
            "role": "smart_board",
            "exp": int(time.time()) - 3600,
        }
        token = jwt.encode(payload, os.environ["JWT_SECRET"], algorithm="HS256")
        with pytest.raises(jwt.ExpiredSignatureError):
            jwt.decode(token, os.environ["JWT_SECRET"], algorithms=["HS256"])

    def test_tampered_token_is_rejected(self):
        payload = {"sub": "board-001", "role": "smart_board"}
        token = jwt.encode(payload, os.environ["JWT_SECRET"], algorithm="HS256")
        tampered = token[:-5] + "XXXXX"
        with pytest.raises(jwt.InvalidTokenError):
            jwt.decode(tampered, os.environ["JWT_SECRET"], algorithms=["HS256"])


class TestAuthServiceDependencies:
    """Tests require_role() which is a FastAPI dependency factory."""

    def test_missing_auth_header_returns_401(self):
        request = MagicMock(spec=Request)
        request.headers = {}

        role_checker = AuthService.require_role(allowed_roles=["smart_board"])
        with pytest.raises(HTTPException) as exc:
            import asyncio
            asyncio.run(role_checker(request))
        assert exc.value.status_code == 401

    def test_invalid_token_returns_401(self):
        request = MagicMock(spec=Request)
        request.headers = {"Authorization": "Bearer invalid_token_xyz"}

        role_checker = AuthService.require_role(allowed_roles=["smart_board"])
        with pytest.raises(HTTPException) as exc:
            import asyncio
            asyncio.run(role_checker(request))
        assert exc.value.status_code == 401

    def test_valid_token_wrong_role_returns_403(self):
        payload = {"sub": "board-001", "role": "student", "iat": int(time.time())}
        token = jwt.encode(payload, os.environ["JWT_SECRET"], algorithm="HS256")

        request = MagicMock(spec=Request)
        request.headers = {"Authorization": f"Bearer {token}"}

        role_checker = AuthService.require_role(allowed_roles=["smart_board"])
        with pytest.raises(HTTPException) as exc:
            import asyncio
            asyncio.run(role_checker(request))
        assert exc.value.status_code == 403

    def test_valid_token_correct_role_passes(self):
        payload = {"sub": "board-001", "role": "smart_board", "iat": int(time.time())}
        token = jwt.encode(payload, os.environ["JWT_SECRET"], algorithm="HS256")

        request = MagicMock(spec=Request)
        request.headers = {"Authorization": f"Bearer {token}"}

        role_checker = AuthService.require_role(allowed_roles=["smart_board"])
        import asyncio
        result = asyncio.run(role_checker(request))
        assert result["sub"] == "board-001"
        assert result["role"] == "smart_board"


# ===========================================================================
# Cache Service Tests
# ===========================================================================

class TestCacheService:
    def teardown_method(self):
        CacheService._client = None
        CacheService._local_fallback = {}
        CacheService._warned = False

    def test_set_and_get_local_fallback(self):
        import asyncio
        asyncio.run(CacheService.set("test_key", "test_value"))
        result = asyncio.run(CacheService.get("test_key"))
        assert result == "test_value"

    def test_set_json_and_get_json(self):
        import asyncio
        data = {"session_id": "abc123", "status": "active"}
        asyncio.run(CacheService.set_json("session:abc123", data))
        result = asyncio.run(CacheService.get_json("session:abc123"))
        assert result == data

    def test_delete_removes_key(self):
        import asyncio
        asyncio.run(CacheService.set("temp_key", "temp_value"))
        assert asyncio.run(CacheService.get("temp_key")) == "temp_value"
        asyncio.run(CacheService.delete("temp_key"))
        assert asyncio.run(CacheService.get("temp_key")) is None

    def test_get_nonexistent_key(self):
        import asyncio
        assert asyncio.run(CacheService.get("nonexistent")) is None

    def test_get_json_nonexistent(self):
        import asyncio
        assert asyncio.run(CacheService.get_json("nonexistent")) is None

    def test_get_json_invalid_json(self):
        import asyncio
        CacheService._local_fallback["bad"] = "not-json"
        assert asyncio.run(CacheService.get_json("bad")) is None

    def test_set_with_ttl_stores_value(self):
        import asyncio
        asyncio.run(CacheService.set("ttl_key", "ttl_value", ttl=60))
        assert asyncio.run(CacheService.get("ttl_key")) == "ttl_value"

    def test_multiple_keys_independent(self):
        import asyncio
        asyncio.run(CacheService.set("key_a", "value_a"))
        asyncio.run(CacheService.set("key_b", "value_b"))
        assert asyncio.run(CacheService.get("key_a")) == "value_a"
        assert asyncio.run(CacheService.get("key_b")) == "value_b"
        asyncio.run(CacheService.delete("key_a"))
        assert asyncio.run(CacheService.get("key_a")) is None
        assert asyncio.run(CacheService.get("key_b")) == "value_b"


# ===========================================================================
# Session Service Tests
# ===========================================================================

class TestSessionService:
    """Tests session ID derivation.
    These tests do NOT require Firestore."""

    def test_generate_deterministic_id_is_deterministic(self):
        sid_a = SessionService.generate_deterministic_id("slot_001")
        sid_b = SessionService.generate_deterministic_id("slot_001")
        assert sid_a == sid_b
        assert len(sid_a) == 20

    def test_generate_deterministic_id_differs_by_slot(self):
        sid_slot1 = SessionService.generate_deterministic_id("slot_001")
        sid_slot2 = SessionService.generate_deterministic_id("slot_002")
        assert sid_slot1 != sid_slot2

    def test_session_id_is_hex(self):
        sid = SessionService.generate_deterministic_id("slot_001")
        int(sid, 16)

    def test_create_session_returns_expected_keys(self):
        import asyncio
        course_data = {
            "slot_id": "slot_001",
            "course_name": "CS101",
            "faculty_name": "Dr. Smith",
            "roster_count": 30,
        }
        result = asyncio.run(SessionService.create_session(course_data, db=None))
        assert "session_id" in result
        assert "otp" in result
        assert "session_secret_half1" in result
        assert result["course_name"] == "CS101"
        assert result["faculty_name"] == "Dr. Smith"
        assert result["roster_count"] == 30

    def test_create_session_otp_is_six_digits(self):
        import asyncio
        result = asyncio.run(
            SessionService.create_session({"slot_id": "slot_001"}, db=None)
        )
        otp = result["otp"]
        assert len(otp) == 6
        assert otp.isdigit()

    def test_create_session_half1_is_valid_base64(self):
        import asyncio, base64
        result = asyncio.run(
            SessionService.create_session({"slot_id": "slot_001"}, db=None)
        )
        try:
            base64.urlsafe_b64decode(result["session_secret_half1"] + "==")
        except Exception:
            pytest.fail("session_secret_half1 is not valid base64")


# ===========================================================================
# Alert Service Tests
# ===========================================================================

class TestAlertService:
    def test_notify_security_violation_no_webhook(self):
        import asyncio
        original = os.environ.get("SLACK_WEBHOOK_URL")
        if "SLACK_WEBHOOK_URL" in os.environ:
            del os.environ["SLACK_WEBHOOK_URL"]
        try:
            asyncio.run(AlertService.notify_security_violation("board-001", "test violation"))
        except Exception:
            pytest.fail("Alert service raised on missing webhook")
        finally:
            if original is not None:
                os.environ["SLACK_WEBHOOK_URL"] = original

    def test_notify_stale_board_no_webhook(self):
        import asyncio
        from datetime import datetime, timezone
        original = os.environ.get("SLACK_WEBHOOK_URL")
        if "SLACK_WEBHOOK_URL" in os.environ:
            del os.environ["SLACK_WEBHOOK_URL"]
        try:
            now = datetime.now(timezone.utc)
            asyncio.run(AlertService.notify_stale_board("board-001", now))
        except Exception:
            pytest.fail("Alert service raised on missing webhook")
        finally:
            if original is not None:
                os.environ["SLACK_WEBHOOK_URL"] = original
