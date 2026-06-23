import hashlib
import hmac as hmac_mod
import base64
from datetime import datetime, timezone
from typing import Optional


class TokenGenerator:
    @staticmethod
    def generate_token(session_id: str, session_secret: str, timestamp: Optional[datetime] = None) -> str:
        ts = timestamp or datetime.now(timezone.utc)
        ts_ms = int(ts.timestamp() * 1000)
        raw = f"{session_id}:{session_secret}:{ts_ms}"
        return hashlib.sha256(raw.encode()).hexdigest()

    @staticmethod
    def validate_qr_token(
        token: str,
        session_secret: str,
        max_age_ms: int = 30000,
    ) -> bool:
        """
        Validate an IATT-format QR token — matches the Dart TotpEngine exactly.

        Gate 1 of the Trust Engine — 3-part payload with 16-char truncated HMAC.
        """
        if not token.startswith("IATT::"):
            return False

        parts = token.split("::")
        if len(parts) != 3:
            return False

        base64_payload = parts[1]
        provided_signature = parts[2]

        # Gate 1a: HMAC-SHA256 signature (16-char truncated)
        key = session_secret.encode("utf-8")
        message = base64_payload.encode("utf-8")
        expected = hmac_mod.new(key, message, hashlib.sha256).hexdigest()[:16]

        if not hmac_mod.compare_digest(expected, provided_signature):
            return False

        # Gate 1b: timestamp freshness
        try:
            decoded = base64.b64decode(base64_payload).decode("utf-8")
        except Exception:
            return False

        inner = decoded.split("|")
        if len(inner) < 2:
            return False

        try:
            ts_ms = int(inner[1])
        except (ValueError, IndexError):
            return False

        now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
        if abs(now_ms - ts_ms) > max_age_ms:
            return False

        return True


