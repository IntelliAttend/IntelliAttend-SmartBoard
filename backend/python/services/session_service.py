import secrets
import base64
import hashlib
from datetime import datetime, timezone, timedelta
from typing import Optional
from firebase_admin import firestore


class SessionService:
    @staticmethod
    def generate_deterministic_id(slot_id: str) -> str:
        """v6.0 Protocol: session_id = hash(slot_id + today_date)"""
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        seed = f"{slot_id}_{today}"
        return hashlib.sha256(seed.encode()).hexdigest()[:20] # Aligned with hand-off length

    @staticmethod
    async def create_session(
        course_data: dict,
        db: firestore.client
    ) -> dict:
        slot_id = course_data.get("slot_id")
        if slot_id:
            session_id = SessionService.generate_deterministic_id(slot_id)
        else:
            session_id = f"SESS_{secrets.token_hex(4).upper()}"
        
        half1_bytes = secrets.token_bytes(16)
        half1 = base64.urlsafe_b64encode(half1_bytes).decode().rstrip("=")

        otp = str(secrets.randbelow(900000) + 100000)
        otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)

        doc_data = {
            "session_secret_half1": half1,
            "otp": otp,
            "status": "otp_pending",
            "course_name": course_data.get("course_name", ""),
            "faculty_name": course_data.get("faculty_name", ""),
            "roster_count": course_data.get("roster_count", 0),
            "section_id": course_data.get("section_id", ""),
            "created_at": firestore.SERVER_TIMESTAMP,
            "otp_expires_at": otp_expires_at.isoformat(),
        }

        if db:
            db.collection("Sessions").document(session_id).set(doc_data)

        return {
            "session_id": session_id,
            "otp": otp,
            "session_secret_half1": half1,
        }

    @staticmethod
    async def find_session_by_otp(
        otp: str,
        db: firestore.client,
    ) -> Optional[dict]:
        if not db:
            return None

        sessions = (
            db.collection("Sessions")
            .where("otp", "==", otp)
            .where("status", "==", "otp_pending")
            .limit(1)
            .get()
        )

        if not sessions:
            return None

        doc = sessions[0]
        data = doc.to_dict()

        now = datetime.now(timezone.utc)
        expires = datetime.fromisoformat(data.get("otp_expires_at", "2000-01-01"))
        if now > expires.replace(tzinfo=None) if not expires.tzinfo else now > expires:
            return {"error": "OTP expired"}

        half1 = data.get("session_secret_half1")
        if not half1:
            half1 = (data.get("session_secret") or "")[:22]

        data["session_id"] = doc.id
        data["session_secret_half1"] = half1
        return data

    @staticmethod
    async def verify_otp_and_mark_faculty(
        session_id: str,
        db: firestore.client,
    ) -> dict:
        session_ref = db.collection("Sessions").document(session_id)
        session_doc = session_ref.get()

        if not session_doc.exists:
            return {"error": "Session not found"}

        data = session_doc.to_dict()
        if data.get("status") != "otp_pending":
            return {"error": "Session already activated or expired"}

        session_ref.update({
            "otp_verified": True,
            "otp_verified_at": firestore.SERVER_TIMESTAMP,
        })

        half1 = data.get("session_secret_half1")
        if not half1:
            half1 = (data.get("session_secret") or "")[:22]

        return {
            "session_secret_half1": half1,
            "session_id": session_id,
            "course_name": data.get("course_name", ""),
            "faculty_name": data.get("faculty_name", ""),
            "roster_count": data.get("roster_count", 0),
        }

    @staticmethod
    async def ignite_session_atomic(
        session_id: str,
        secret: str,
        db: firestore.client,
    ) -> None:
        """v6.2 Atomic Ignition: Store secret and activate session only."""
        if not db:
            return

        session_ref = db.collection("Sessions").document(session_id)
        
        # 1. Update master session record - Pure Activation
        session_ref.update({
            "session_secret": secret,
            "status": "active",
            "activated_at": firestore.SERVER_TIMESTAMP
        })
        
        # 2. Sync to ActiveSessions for SmartBoard listeners
        session_doc = session_ref.get()
        if session_doc.exists:
            db.collection("ActiveSessions").document(session_id).set({
                **session_doc.to_dict(),
                "session_secret": secret,
                "status": "active",
            })
