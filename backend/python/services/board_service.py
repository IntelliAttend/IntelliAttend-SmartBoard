from fastapi import Header, HTTPException, status
from firebase_admin import firestore


class BoardService:
    COLLECTION = "RegisteredDevices"

    @classmethod
    def get_board_data(cls, db: firestore.client):
        async def _verify(x_device_id: str = Header(alias="X-Device-ID", default=None)) -> dict:
            if not x_device_id:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Hardware Identity Breach: X-Device-ID missing"
                )
            if db:
                doc = db.collection(cls.COLLECTION).document(x_device_id).get()
                if not doc.exists:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Unregistered Hardware Signature"
                    )
                board_data = doc.to_dict()
                board_data["device_id"] = x_device_id
                return board_data
            return {
                "device_id": x_device_id,
                "room_id": "ROOM_CSE_402",
                "room_name": "CSE Seminar Hall 402",
                "roster_count": 55,
                "status": "ACTIVE",
            }
        return _verify
