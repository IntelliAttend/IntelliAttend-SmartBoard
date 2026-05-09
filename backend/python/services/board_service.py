from fastapi import Header, HTTPException, status
from firebase_admin import firestore


class BoardService:
    COLLECTION = "smart_boards"

    @classmethod
    def get_board_data(cls, db: firestore.client):
        async def _verify(x_device_id: str = Header(alias="X-Device-ID", default=None)) -> dict:
            if not x_device_id:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Hardware Identity Breach: X-Device-ID missing"
                )
            if db:
                # In the new model, we can look up by hardware ID (device_id field)
                # or find the board by its hardware binding.
                boards = db.collection(cls.COLLECTION).where("device_id", "==", x_device_id).limit(1).get()
                
                if not boards:
                    # Fallback to legacy RegisteredDevices check
                    doc = db.collection("RegisteredDevices").document(x_device_id).get()
                    if not doc.exists:
                        raise HTTPException(
                            status_code=status.HTTP_403_FORBIDDEN,
                            detail="Unregistered Hardware Signature"
                        )
                    board_data = doc.to_dict()
                    # Link back to smart_boards if possible
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
