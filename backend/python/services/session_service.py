import secrets
import base64
import hashlib
from datetime import datetime, timezone
from typing import Optional
from firebase_admin import firestore

from .cache_service import CacheService


class SessionService:
    OTP_CACHE_TTL = 300  # 5 minutes

    @staticmethod
    def generate_deterministic_id(slot_id: str) -> str:
        """v6.0 Protocol: session_id = hash(slot_id + today_date)"""
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        seed = f"{slot_id}_{today}"
        return hashlib.sha256(seed.encode()).hexdigest()[:20] # Aligned with hand-off length

    @staticmethod
    def _otp_cache_key(otp: str) -> str:
        return f"otp:{otp}"

    @staticmethod
    async def create_session(
        course_data: dict,
        db: firestore.AsyncClient
    ) -> dict:
        slot_id = course_data.get("slot_id")
        if slot_id:
            session_id = SessionService.generate_deterministic_id(slot_id)
        else:
            session_id = f"SESS_{secrets.token_hex(4).upper()}"
        
        half1_bytes = secrets.token_bytes(16)
        half1 = base64.urlsafe_b64encode(half1_bytes).decode().rstrip("=")

        otp = str(secrets.randbelow(900000) + 100000)

        # Zero Storage OTP: OTP is NEVER written to Firestore.
        doc_data = {
            "session_secret_half1": half1,
            "status": "pre_allocated",
            "course_name": course_data.get("course_name", ""),
            "faculty_name": course_data.get("faculty_name", ""),
            "roster_count": course_data.get("roster_count", 0),
            "section_id": course_data.get("section_id", ""),
            "created_at": firestore.SERVER_TIMESTAMP,
        }

        if db:
            await db.collection("Sessions").document(session_id).set(doc_data)

        # Store OTP mapping in ephemeral cache only
        await CacheService.set_json(
            SessionService._otp_cache_key(otp),
            {"session_id": session_id, "session_secret_half1": half1},
            ttl=SessionService.OTP_CACHE_TTL,
        )

        return {
            "session_id": session_id,
            "otp": otp,
            "session_secret_half1": half1,
            "course_name": doc_data["course_name"],
            "faculty_name": doc_data["faculty_name"],
            "roster_count": doc_data["roster_count"],
            "section_id": doc_data["section_id"],
        }

    @staticmethod
    async def find_session_by_otp(
        otp: str,
        db: firestore.AsyncClient,
    ) -> Optional[dict]:
        # Zero Storage OTP: look up OTP in ephemeral cache, NOT Firestore
        cached = await CacheService.get_json(SessionService._otp_cache_key(otp))
        if not cached:
            return None

        session_id = cached.get("session_id")
        if not session_id or not db:
            return None

        session_doc = await db.collection("Sessions").document(session_id).get()
        if not session_doc.exists:
            return None

        data = session_doc.to_dict()
        data["session_id"] = session_doc.id
        data["session_secret_half1"] = cached.get("session_secret_half1") or data.get("session_secret_half1")

        return data

    @staticmethod
    async def ignite_session_atomic(
        session_id: str,
        db: firestore.AsyncClient,
    ) -> None:
        """v6.2 Atomic Ignition: Activate session — NO secret written to Firestore.
        
        Split-knowledge design: the full session secret is derived on-device
        from session_secret_half1 + hardware fingerprint. The server never
        holds or persists the full secret.
        """
        if not db:
            return

        # 1. Activate master session record
        await db.collection("Sessions").document(session_id).update({
            "status": "active",
            "activated_at": firestore.SERVER_TIMESTAMP
        })
        
        # 2. Sync status to ActiveSessions for SmartBoard listeners
        await db.collection("ActiveSessions").document(session_id).update({
            "status": "active",
            "activated_at": firestore.SERVER_TIMESTAMP
        })
