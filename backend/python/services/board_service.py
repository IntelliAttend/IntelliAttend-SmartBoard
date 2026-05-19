import logging
from datetime import datetime, timezone, timedelta
from fastapi import Header, HTTPException, status
from firebase_admin import firestore

logger = logging.getLogger("IntelliAttend")


class BoardService:
    COLLECTION = "smart_boards"

    @classmethod
    def get_board_data(cls, db: firestore.client):
        async def _verify(x_device_id: str = Header(alias="X-Device-ID", default=None)) -> dict:
            if not x_device_id:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="AUTH_FAILED: Hardware Identity Breach - X-Device-ID missing"
                )
            if db:
                boards = db.collection(cls.COLLECTION).where("device_id", "==", x_device_id).limit(1).get()
                
                if not boards:
                    doc = db.collection("RegisteredDevices").document(x_device_id).get()
                    if not doc.exists:
                        raise HTTPException(
                            status_code=status.HTTP_403_FORBIDDEN,
                            detail="BOARD_NOT_FOUND: Board not registered in smart_boards collection"
                        )
                    board_data = doc.to_dict()
                    if "board_id" in board_data:
                        sb_doc = db.collection(cls.COLLECTION).document(board_data["board_id"]).get()
                        if sb_doc.exists:
                            return {**sb_doc.to_dict(), "device_id": x_device_id}
                    return board_data
                
                board_doc = boards[0]
                board_data = board_doc.to_dict()
                board_data["smart_board_id"] = board_doc.id
                return board_data
            return {
                "device_id": x_device_id,
                "room_id": "ROOM_CSE_402",
                "room_name": "CSE Seminar Hall 402",
                "roster_count": 55,
                "status": "ACTIVE",
            }
        return _verify


class HeartbeatService:
    COLLECTION = "board_heartbeats"
    STALE_THRESHOLD_MINUTES = 5

    @classmethod
    def get_all_status(cls, db: firestore.client) -> list:
        if not db:
            return []
        docs = db.collection(cls.COLLECTION).stream()
        now = datetime.now(timezone.utc)
        results = []
        for doc in docs:
            data = doc.to_dict() or {}
            last_hb = data.get("last_heartbeat_at")
            stale = True
            if last_hb:
                diff = now - last_hb.replace(tzinfo=timezone.utc)
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
