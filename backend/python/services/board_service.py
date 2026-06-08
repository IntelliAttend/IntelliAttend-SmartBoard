import logging
import jwt
import os
from datetime import datetime, timezone, timedelta
from fastapi import Header, HTTPException, status, Request
from google.cloud import firestore

from services.alert_service import AlertService

logger = logging.getLogger("IntelliAttend")

# Fallback for dev, should be consistent with AuthService
JWT_SECRET = os.environ.get("JWT_SECRET", "dev_secret_key_change_me_in_production")

class BoardService:
    COLLECTION = "smart_boards"

    @classmethod
    def get_board_data(cls, db: firestore.AsyncClient):
        async def _verify(
            request: Request,
            x_device_id: str = Header(alias="X-Device-ID", default=None),
            authorization: str = Header(default=None)
        ) -> dict:
            # 1. Identity Check: Hardware ID must be present
            if not x_device_id:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="AUTH_FAILED: Hardware Identity Breach - X-Device-ID missing"
                )
            
            # 2. Authentication Check: JWT Bearer token required (v5.4)
            if not authorization or not authorization.startswith("Bearer "):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="AUTH_FAILED: Missing or invalid Authorization header"
                )
            
            token = authorization.split(" ")[1]
            try:
                # 3. Cryptographic Validation: Verify token signature and expiry
                payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
                
                # 4. Strict Binding: Token's device_id MUST match the physical X-Device-ID header
                token_device_id = payload.get("device_id")
                if token_device_id != x_device_id:
                    reason = f"Hardware ID Mismatch. Header: {x_device_id} vs Token: {token_device_id}"
                    await AlertService.notify_security_violation(payload.get("sub", "unknown"), reason)
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="AUTH_FAILED: Token/Hardware Mismatch (Spoofing detected)"
                    )
                
                # 5. RBAC: Ensure the token has the correct role
                if payload.get("role") != "smart_board":
                    await AlertService.notify_security_violation(payload.get("sub", "unknown"), "Invalid role for board endpoint")
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="AUTH_FAILED: Insufficient permissions for this role"
                    )

                board_id = payload.get("sub")
                
            except jwt.ExpiredSignatureError:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="AUTH_FAILED: Token expired")
            except jwt.InvalidTokenError as e:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"AUTH_FAILED: {str(e)}")

            # 6. Database Verification: Confirm board is still ACTIVE in Firestore
            if db:
                board_ref = db.collection(cls.COLLECTION).document(board_id)
                board_doc = await board_ref.get()
                
                if not board_doc.exists:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="BOARD_NOT_FOUND: Board not found in smart_boards collection"
                    )
                
                board_data = board_doc.to_dict()
                if board_data.get("status") != "ACTIVE":
                     raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="BOARD_SUSPENDED: This board has been deactivated by an administrator"
                    )
                
                board_data["smart_board_id"] = board_doc.id
                board_data["device_id"] = x_device_id
                return board_data
                
            # Mock for local dev without Firebase
            return {
                "smart_board_id": board_id,
                "device_id": x_device_id,
                "room_id": "ROOM_CSE_402",
                "status": "ACTIVE",
            }
        return _verify


class HeartbeatService:
    COLLECTION = "board_heartbeats"
    STALE_THRESHOLD_MINUTES = 5

    @classmethod
    async def get_all_status(cls, db: firestore.AsyncClient) -> list:
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
                # Ensure last_hb is timezone-aware
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
