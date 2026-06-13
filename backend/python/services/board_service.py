import logging
from datetime import datetime, timezone, timedelta
from google.cloud import firestore

from core.security import get_current_board

logger = logging.getLogger("IntelliAttend")


class BoardService:
    """
    DEPRECATED — Legacy custom JWT + X-Device-ID auth preserved for reference.

    The SmartBoard now authenticates exactly like the Faculty and Student mobile
    apps — using Firebase Auth with email/password. See core/security.py for the
    current get_current_board() dependency.

    Key changes:
      - Token type: HMAC-signed JWT (HS256) → Firebase ID Token (RS256)
      - Token expiry: 2 hours → ~1 hour (Google-managed, auto-refreshed by SDK)
      - Refresh mechanism: Manual POST /board/refresh → Automatic (Firebase SDK)
      - Registration: OTP + fingerprint → Firebase Auth email/password
      - Board lookup: By board_id field → By email field in smart_boards collection
    """
    COLLECTION = "smart_boards"

    @classmethod
    def get_board_data(cls, db: firestore.AsyncClient):
        """
        DEPRECATED — Use core.security.get_current_board() instead.

        This method previously validated custom JWTs signed with JWT_SECRET,
        enforced X-Device-ID / token device_id binding, and fell back to
        Firebase token verification by firebase_uid lookup.

        Replaced by get_current_board() which:
          1. Extracts Firebase ID Token from Authorization: Bearer header
          2. Verifies via firebase_admin.auth.verify_id_token()
          3. Looks up board by email field in smart_boards collection
          4. Returns board data (same shape as before)
        """
        return get_current_board(db)


class HeartbeatService:
    COLLECTION = "board_heartbeats"
    STALE_THRESHOLD_MINUTES = 5

    @classmethod
    async def get_all_status(cls, db: firestore.AsyncClient) -> list:
        if not db:
            return []
        
        docs = db.collection(cls.COLLECTION).stream()
        now = datetime.now(timezone.utc)
        results = []
        
        async for doc in docs:
            data = doc.to_dict() or {}
            last_hb = data.get("last_heartbeat_at")
            stale = True
            if last_hb:
                # Ensure last_hb is timezone-aware
                if last_hb.tzinfo is None:
                    last_hb = last_hb.replace(tzinfo=timezone.utc)
                
                diff = now - last_hb
                stale = diff > timedelta(minutes=cls.STALE_THRESHOLD_MINUTES)
            
            results.append({
                "board_id": doc.id,
                "last_heartbeat_at": last_hb.isoformat() if last_hb else None,
                "screen_state": data.get("screen_state", "unknown"),
                "app_version": data.get("app_version", "unknown"),
                "uptime_seconds": data.get("uptime_seconds", 0),
                "stale": stale,
            })
        return results
