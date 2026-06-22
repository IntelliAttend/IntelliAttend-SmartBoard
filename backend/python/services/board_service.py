import logging
from datetime import datetime, timezone, timedelta
from typing import Optional

from google.cloud import firestore
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.security import get_current_board
from models.sql_models import BoardHeartbeat, User

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
        """
        return get_current_board(db)


class HeartbeatService:
    COLLECTION = "board_heartbeats"
    STALE_THRESHOLD_MINUTES = 5

    @classmethod
    async def get_all_status(cls, db: firestore.AsyncClient) -> list:
        """DEPRECATED — Firestore version. Use get_all_status_pg() instead."""
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

    @classmethod
    async def get_all_status_pg(cls, session: AsyncSession) -> list:
        """PostgreSQL version — reads from board_heartbeats table."""
        now = datetime.now(timezone.utc)
        threshold = timedelta(minutes=cls.STALE_THRESHOLD_MINUTES)

        result = await session.execute(
            select(BoardHeartbeat).order_by(BoardHeartbeat.last_heartbeat_at.desc())
        )
        heartbeats = result.scalars().all()

        board_ids = {h.board_id for h in heartbeats}
        boards_map: dict[str, User] = {}
        if board_ids:
            board_result = await session.execute(
                select(User).where(User.id.in_(board_ids))
            )
            boards_map = {u.id: u for u in board_result.scalars().all()}

        output = []
        for hb in heartbeats:
            last_hb = hb.last_heartbeat_at
            if last_hb.tzinfo is None:
                last_hb = last_hb.replace(tzinfo=timezone.utc)
            diff = now - last_hb
            stale = diff > threshold

            board = boards_map.get(hb.board_id)
            output.append({
                "board_id": hb.board_id,
                "board_name": board.name if board else "Unknown",
                "email": board.email if board else "",
                "last_heartbeat_at": last_hb.isoformat(),
                "screen_state": hb.screen_state or "unknown",
                "app_version": hb.app_version or "unknown",
                "uptime_seconds": hb.uptime_seconds or 0,
                "stale": stale,
            })

        return output
