from firebase_admin import firestore
from sqlalchemy.ext.asyncio import AsyncSession

from models.sql_models import ActiveSession, SessionStatus


class ActiveSessionsService:
    SESSION_TTL_SECONDS = 10860

    @classmethod
    def _redis_key(cls, session_id: str) -> str:
        return f"session_secret:{session_id}"

    # ─── DEPRECATED: Firestore version ───────────────────────────────────────

    @classmethod
    async def create_active_session(
        cls,
        session_id: str,
        session_secret_half1: str,
        db: firestore.AsyncClient,
    ) -> None:
        """DEPRECATED — Firestore version. Use create_active_session_pg() instead."""
        if not db:
            return
        doc_data = {
            "session_secret_half1": session_secret_half1,
            "status": "pending",
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        await db.collection("ActiveSessions").document(session_id).set(doc_data)

    # ─── NEW: PostgreSQL version ─────────────────────────────────────────────

    @classmethod
    async def create_active_session_pg(
        cls,
        session_id: str,
        session_secret_half1: str,
        session: AsyncSession,
        room_id: str = "",
        course_name: str = "",
        faculty_name: str = "",
        section_id: str = "",
        roster_count: int = 0,
    ) -> None:
        db_session = ActiveSession(
            session_id=session_id,
            session_secret_half1=session_secret_half1,
            status=SessionStatus.PRE_ALLOCATED,
            room_id=room_id,
            course_name=course_name,
            faculty_name=faculty_name,
            section_id=section_id,
            roster_count=roster_count,
        )
        session.add(db_session)
