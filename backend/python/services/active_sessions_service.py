from datetime import datetime, timezone, timedelta
from firebase_admin import firestore

from .cache_service import CacheService
from .token_validator import TokenGenerator


class ActiveSessionsService:
    SESSION_TTL_SECONDS = 10860

    @classmethod
    def _redis_key(cls, session_id: str) -> str:
        return f"session_secret:{session_id}"

    @classmethod
    async def create_active_session(
        cls,
        session_id: str,
        session_secret_half1: str,
        db: firestore.client,
    ) -> None:
        if not db:
            return

        doc_data = {
            "session_secret_half1": session_secret_half1,
            "status": "pending",
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        db.collection("ActiveSessions").document(session_id).set(doc_data)

    @classmethod
    async def activate_session(
        cls,
        session_id: str,
        full_secret: str,
        db: firestore.client,
    ) -> dict:
        token = TokenGenerator.generate_token(session_id, full_secret)
        now = datetime.now(timezone.utc)

        if db:
            updates = {
                "session_secret": full_secret,
                "status": "active",
                "activated_at": firestore.SERVER_TIMESTAMP,
                "token": token,
                "token_generated_at": now.isoformat(),
                "expires_at": (now + timedelta(seconds=cls.SESSION_TTL_SECONDS)).isoformat(),
            }
            db.collection("ActiveSessions").document(session_id).update(updates)

        cache_data = {
            "session_secret": full_secret,
            "status": "active",
            "token": token,
        }
        await CacheService.set_json(cls._redis_key(session_id), cache_data, cls.SESSION_TTL_SECONDS)

        return {"token": token, "expires_at": now.isoformat()}

    @classmethod
    async def get_active_session(
        cls,
        session_id: str,
        db: firestore.client,
    ) -> dict | None:
        cached = await CacheService.get_json(cls._redis_key(session_id))
        if cached and cached.get("status") == "active":
            return cached

        if not db:
            return None

        doc = db.collection("ActiveSessions").document(session_id).get()
        if doc.exists:
            data = doc.to_dict()
            data["session_id"] = doc.id
            if data.get("session_secret"):
                await CacheService.set_json(cls._redis_key(session_id), data, cls.SESSION_TTL_SECONDS)
            return data
        return None

    @classmethod
    async def end_session(
        cls,
        session_id: str,
        db: firestore.client,
    ) -> None:
        if db:
            db.collection("ActiveSessions").document(session_id).update({
                "status": "ended",
                "ended_at": firestore.SERVER_TIMESTAMP,
            })
        await CacheService.delete(cls._redis_key(session_id))
