import secrets
import base64
import hashlib
from datetime import datetime, timezone
from typing import Optional

from firebase_admin import firestore
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from models.sql_models import ActiveSession, SessionStatus
from .cache_service import CacheService


class SessionService:
    OTP_CACHE_TTL = 300  # 5 minutes

    @staticmethod
    def generate_deterministic_id(slot_id: str) -> str:
        """v6.0 Protocol: session_id = hash(slot_id + today_date)"""
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        seed = f"{slot_id}_{today}"
        return hashlib.sha256(seed.encode()).hexdigest()[:20]

    @staticmethod
    def _otp_cache_key(otp: str) -> str:
        return f"otp:{otp}"

    # ─── DEPRECATED: Firestore versions ───────────────────────────────────────

    @staticmethod
    async def create_session(
        course_data: dict,
        db: firestore.AsyncClient
    ) -> dict:
        """DEPRECATED — Firestore version. Use create_session_pg() instead."""
        slot_id = course_data.get("slot_id")
        if slot_id:
            session_id = SessionService.generate_deterministic_id(slot_id)
        else:
            session_id = f"SESS_{secrets.token_hex(4).upper()}"

        half1_bytes = secrets.token_bytes(16)
        half1 = base64.urlsafe_b64encode(half1_bytes).decode().rstrip("=")
        otp = str(secrets.randbelow(900000) + 100000)

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
        """DEPRECATED — Firestore version. Use find_session_by_otp_pg() instead."""
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
        """DEPRECATED — Firestore version. Use ignite_session_atomic_pg() instead."""
        if not db:
            return
        await db.collection("Sessions").document(session_id).update({
            "status": "active",
            "activated_at": firestore.SERVER_TIMESTAMP
        })
        await db.collection("ActiveSessions").document(session_id).update({
            "status": "active",
            "activated_at": firestore.SERVER_TIMESTAMP
        })

    # ─── NEW: PostgreSQL versions ────────────────────────────────────────────

    @staticmethod
    async def create_session_pg(
        course_data: dict,
        session: AsyncSession,
        room_id: Optional[str] = None,
    ) -> dict:
        """PostgreSQL version — creates a pre-allocated session."""
        slot_id = course_data.get("slot_id")
        if slot_id:
            session_id = SessionService.generate_deterministic_id(slot_id)
        else:
            session_id = f"SESS_{secrets.token_hex(4).upper()}"

        half1_bytes = secrets.token_bytes(16)
        half1 = base64.urlsafe_b64encode(half1_bytes).decode().rstrip("=")
        otp = str(secrets.randbelow(900000) + 100000)

        db_session = ActiveSession(
            session_id=session_id,
            slot_id=slot_id or "",
            room_id=room_id or "",
            status=SessionStatus.PRE_ALLOCATED,
            session_secret_half1=half1,
            course_name=course_data.get("course_name", ""),
            faculty_name=course_data.get("faculty_name", ""),
            roster_count=course_data.get("roster_count", 0),
            section_id=course_data.get("section_id", ""),
        )
        session.add(db_session)

        await CacheService.set_json(
            SessionService._otp_cache_key(otp),
            {"session_id": session_id, "session_secret_half1": half1},
            ttl=SessionService.OTP_CACHE_TTL,
        )

        return {
            "session_id": session_id,
            "otp": otp,
            "session_secret_half1": half1,
            "course_name": db_session.course_name,
            "faculty_name": db_session.faculty_name,
            "roster_count": db_session.roster_count,
            "section_id": db_session.section_id,
        }

    @staticmethod
    async def find_session_by_otp_pg(
        otp: str,
        session: AsyncSession,
    ) -> Optional[dict]:
        """PostgreSQL version — looks up OTP in Redis cache, reads from PG."""
        cached = await CacheService.get_json(SessionService._otp_cache_key(otp))
        if not cached:
            return None

        session_id = cached.get("session_id")
        if not session_id:
            return None

        result = await session.execute(
            select(ActiveSession).where(ActiveSession.session_id == session_id)
        )
        db_session = result.scalar_one_or_none()
        if db_session is None:
            return None

        return {
            "session_id": db_session.session_id,
            "session_secret_half1": cached.get("session_secret_half1") or db_session.session_secret_half1 or "",
            "faculty_name": db_session.faculty_name,
            "course_name": db_session.course_name,
            "roster_count": db_session.roster_count,
            "section_id": db_session.section_id,
            "status": db_session.status.value,
            "error": None,
        }

    @staticmethod
    async def ignite_session_atomic_pg(
        session_id: str,
        session: AsyncSession,
    ) -> None:
        """PostgreSQL Atomic Ignition — activates a pre-allocated session."""
        now = datetime.now(timezone.utc)
        await session.execute(
            update(ActiveSession)
            .where(ActiveSession.session_id == session_id)
            .values(
                status=SessionStatus.ACTIVE,
                activated_at=now,
            )
        )
