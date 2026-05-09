import secrets
import hashlib
import hmac as hmac_mod
from datetime import datetime, timezone, timedelta
from typing import Optional


class TokenGenerator:
    @staticmethod
    def generate_token(session_id: str, session_secret: str, timestamp: Optional[datetime] = None) -> str:
        ts = timestamp or datetime.now(timezone.utc)
        ts_ms = int(ts.timestamp() * 1000)
        raw = f"{session_id}:{session_secret}:{ts_ms}"
        return hashlib.sha256(raw.encode()).hexdigest()

    @staticmethod
    def validate_token(token: str, session_id: str, session_secret: str, max_age_ms: int = 30000) -> bool:
        now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
        for offset in range(0, max_age_ms + 1, 1000):
            candidate = hashlib.sha256(f"{session_id}:{session_secret}:{now_ms - offset}".encode()).hexdigest()
            if hmac_mod.compare_digest(candidate, token):
                return True
        return False


class TokenRotationService:
    @staticmethod
    def generate_rotated_token(session_id: str, session_secret: str, rotation_count: int) -> str:
        raw = f"{session_id}:{session_secret}:rot:{rotation_count}"
        return hashlib.sha256(raw.encode()).hexdigest()

    @staticmethod
    def validate_rotated_token(token: str, session_id: str, session_secret: str, rotation_count: int) -> bool:
        candidate = hashlib.sha256(f"{session_id}:{session_secret}:rot:{rotation_count}".encode()).hexdigest()
        return hmac_mod.compare_digest(candidate, token)
