from firebase_admin import firestore


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
        db: firestore.AsyncClient,
    ) -> None:
        if not db:
            return

        doc_data = {
            "session_secret_half1": session_secret_half1,
            "status": "pending",
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        await db.collection("ActiveSessions").document(session_id).set(doc_data)


