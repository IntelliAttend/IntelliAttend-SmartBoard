import os
import hmac
import hashlib
import secrets
import base64
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional
import uvicorn
import firebase_admin
from firebase_admin import credentials, firestore
from fastapi import FastAPI, Depends, HTTPException, status, Request, Response, APIRouter, Header
from fastapi.middleware.gzip import GZipMiddleware
from pydantic import BaseModel, Field

from middleware.rate_limit_middleware import RateLimitMiddleware
from services.board_service import BoardService, HeartbeatService
from services.session_service import SessionService
from services.active_sessions_service import ActiveSessionsService
from services.auth_service import AuthService
from services.cache_service import CacheService
from models.board_auth_schema import (
    TelemetryPayload, 
    SessionInitiateRequest, 
    SessionCreateRequest,
    DeviceRegisterInitiateRequest,
    DeviceRegisterVerifyRequest,
    DeviceRegisterCompleteRequest,
    VaultSyncRequest,
)

# Configure Logging (v6.0 Measurement Requirement)
LOG_DIR = os.path.join(os.path.dirname(__file__), "logs")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "app.log")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("IntelliAttend")

app = FastAPI(title="IntelliAttend SmartBoard Engine")

# v6.1: Bandwidth Saving - Enable Gzip Compression
app.add_middleware(GZipMiddleware, minimum_size=1000)

# O10: Server-side rate limiting (60 requests/min per IP+device)
app.add_middleware(RateLimitMiddleware, max_requests=60, window_seconds=60)

@app.middleware("http")
async def correlation_id_middleware(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", "internal-v1")
    response: Response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    logger.info(f"{request.method} {request.url.path} | ID: {request_id} | Status: {response.status_code}")
    return response

SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")

try:
    if os.path.exists(SERVICE_ACCOUNT_PATH):
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred)
    else:
        firebase_admin.initialize_app()
    db = firestore.client()
    logger.info("[The Brain] Firebase initialized.")
except Exception as e:
    logger.error(f"[The Brain] Firebase Init Error: {e}")
    db = None

class HeartbeatRequest(BaseModel):
    screen_state: str = "unknown"
    uptime_seconds: int = 0
    app_version: str = "unknown"
    timestamp_ms: int = 0

# --- Shared Logic ---
async def _initiate_session_logic(request: SessionInitiateRequest, board_data: dict, is_offline_fallback: bool = False):
    device_id = board_data.get("device_id")
    
    # v6.1: Trust Engine Handling for Offline Fallback
    otp = request.otp
    if otp.endswith("_offline_generated"):
        logger.warning(f"⚠️ [TrustEngine] Offline Fallback detected for device {device_id}. Loosening timestamp validation.")
        otp = otp.replace("_offline_generated", "")

    session = await SessionService.find_session_by_otp(otp, db)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found or OTP invalid")
    if "error" in session:
        raise HTTPException(status_code=400, detail=session["error"])

    # Atomic Ignition: Activate session — no full secret stored on server.
    # Full secret derived on-device via split-knowledge (half1 + hardware fingerprint).
    try:
        await SessionService.ignite_session_atomic(
            session_id=session["session_id"],
            db=db
        )
    except Exception as e:
        logger.error(f"❌ [Atomic] Ignition failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to ignite session")

    # Strict OTP Protocol: delete OTP from cache immediately after use (single-use)
    await CacheService.delete(SessionService._otp_cache_key(otp))

    return {
        "status": "success",
        "data": {
            "session_id": session["session_id"],
            "session_secret_half1": session.get("session_secret_half1"),
            "faculty_name": session.get("faculty_name", "Professor"),
            "course_name": session.get("course_name", "Active Class"),
            "roster_count": session.get("roster_count", 0)
        }
    }

# --- Heartbeat (shared between two path aliases) ---

async def _handle_heartbeat(request: HeartbeatRequest, board_data: dict) -> dict:
    device_id = board_data.get("device_id")
    if db:
        db.collection("board_heartbeats").document(device_id).set({
            "last_heartbeat_at": firestore.SERVER_TIMESTAMP,
            "screen_state": request.screen_state,
            "uptime_seconds": request.uptime_seconds,
            "app_version": request.app_version,
            "board_id": device_id,
            "timestamp_ms": request.timestamp_ms
        })
    return {"status": "ok", "device_id": device_id}

@app.post("/api/v1/device/heartbeat")
async def board_heartbeat_device(
    request: HeartbeatRequest,
    board_data: dict = Depends(BoardService.get_board_data(db)),
):
    return await _handle_heartbeat(request, board_data)

@app.post("/v1/board/session/initiate")
async def initiate_session_legacy(
    request: SessionInitiateRequest,
    board_data: dict = Depends(BoardService.get_board_data(db)),
):
    return await _initiate_session_logic(request, board_data)

# --- Standard API Router (api/v1/board) ---
api_router = APIRouter(prefix="/api/v1/board")

@api_router.get("/time")
async def get_server_time():
    return {
        "status": "success",
        "server_timestamp_ms": int(datetime.now(timezone.utc).timestamp() * 1000)
    }

@api_router.get("/ready")
async def board_ready(board_data: dict = Depends(BoardService.get_board_data(db))):
    """Boot canary — confirms board is registered in smart_boards collection."""
    board_id = board_data.get("smart_board_id") or board_data.get("board_id") or board_data.get("device_id", "unknown")
    return {"status": "registered", "board_id": board_id}

@api_router.post("/heartbeat")
async def board_heartbeat(
    request: HeartbeatRequest,
    board_data: dict = Depends(BoardService.get_board_data(db)),
):
    """Alias at /api/v1/board/heartbeat (canonical: /api/v1/device/heartbeat)."""
    return await _handle_heartbeat(request, board_data)

@api_router.get("/preflight")
async def get_preflight(
    response: Response,
    slot_id: str,
    x_retry_attempt: Optional[int] = Header(None, alias="X-Retry-Attempt"),
    board_data: dict = Depends(BoardService.get_board_data(db))
):
    if x_retry_attempt and x_retry_attempt > 1:
        logger.warning(f"⚡ [PreFlight] High-priority retry detected (Attempt: {x_retry_attempt}) for slot {slot_id}")
    
    logger.info(f"⚡ [PreFlight] Request for slot: {slot_id}")
    
    # v6.1: Idempotency & Caching
    response.headers["Cache-Control"] = "public, max-age=120"
    
    if not db:
        return {
            "status": "ready",
            "server_timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "pre_allocated_session_id": SessionService.generate_deterministic_id(slot_id),
            "session_secret_half1": "MOCK_HALF_1",
            "slot_verification": {"subject_name": "Mock Class", "faculty_name": "Mock Prof"}
        }
    
    room_id = board_data.get("room_id")
    slot_doc = db.collection("timetable_slots").document(slot_id).get()
    if not slot_doc.exists:
        raise HTTPException(status_code=404, detail="Slot not found")
    
    slot_data = slot_doc.to_dict()
    session_id = SessionService.generate_deterministic_id(slot_id)
    session_doc = db.collection("Sessions").document(session_id).get()

    if not session_doc.exists:
        half1 = base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip("=")
        session_data = {
            "session_secret_half1": half1,
            "status": "pre_allocated",
            "slot_id": slot_id,
            "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "course_name": slot_data.get("subject_name", ""),
            "faculty_name": slot_data.get("faculty_name", ""),
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        db.collection("Sessions").document(session_id).set(session_data)
        db.collection("ActiveSessions").document(session_id).set({
            "session_id": session_id,
            "room_id": room_id,
            "status": "pre_allocated",
            "course_name": session_data["course_name"],
            "faculty_name": session_data["faculty_name"],
            "created_at": firestore.SERVER_TIMESTAMP,
        })
    else:
        session_data = session_doc.to_dict()

    return {
        "status": "ready",
        "server_timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        "pre_allocated_session_id": session_id,
        "session_secret_half1": session_data.get("session_secret_half1"),
        "slot_verification": {
            "subject_name": slot_data.get("subject_name", "Unknown"),
            "faculty_name": slot_data.get("faculty_name", "Unknown"),
        }
    }

@api_router.post("/telemetry")
async def receive_telemetry(payload: TelemetryPayload, board_data: dict = Depends(BoardService.get_board_data(db))):
    if db:
        db.collection("smart_boards").document(board_data["device_id"]).update({
            "health": {**payload.model_dump(), "last_seen": firestore.SERVER_TIMESTAMP}
        })
    return {"status": "success"}

@api_router.get("/sync-context")
async def sync_context(board_data: dict = Depends(BoardService.get_board_data(db))):
    return {"status": "success", "data": board_data}

@api_router.post("/session/initiate")
async def initiate_session_api(request: SessionInitiateRequest, board_data: dict = Depends(BoardService.get_board_data(db))):
    return await _initiate_session_logic(request, board_data)

@api_router.post("/session/terminate")
async def terminate_session():
    return {"status": "success"}

@api_router.post("/session/attendance/record-live")
async def record_attendance():
    return {"status": "success"}

@api_router.post("/sync/vault")
async def sync_vault(
    request: VaultSyncRequest,
    board_data: dict = Depends(BoardService.get_board_data(db)),
):
    """Flush offline attendance scans from the board's local Isar vault."""
    if db:
        batch = db.batch()
        vault_ref = db.collection("attendance_vault")
        for scan in request.queued_scans:
            doc_ref = vault_ref.document()
            batch.set(doc_ref, {
                "session_id": request.session_id,
                "student_id": scan.student_id,
                "qr_payload": scan.qr_payload,
                "timestamp": scan.timestamp,
                "synced_at": firestore.SERVER_TIMESTAMP,
                "board_id": board_data.get("device_id", "unknown"),
            })
        batch.commit()
        logger.info(f"📤 [VaultSync] Synced {len(request.queued_scans)} scans for session {request.session_id}")
    return {"status": "success", "synced_count": len(request.queued_scans)}

# --- Registration API Router (api/v1/device/register) ---
auth_router = APIRouter(prefix="/api/v1/device/register")

def _extract_bearer_token(request: Request) -> Optional[str]:
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        return auth_header.split(" ")[1]
    return None

@auth_router.post("/login")
async def initiate_device_registration(request: DeviceRegisterInitiateRequest):
    """Phase 2: Ignition Login (Trigger OTP)"""
    if not db:
        return {"status": "error", "message": "Database not initialized"}
    
    result = await AuthService.initiate_registration(request.smart_board_id, db)
    if not result:
        raise HTTPException(status_code=400, detail="Board ID not provisioned")
        
    return result

@auth_router.post("/verify")
async def verify_device_registration(request: DeviceRegisterVerifyRequest):
    """Phase 2.5: OTP Verification"""
    if not db:
        return {"status": "error", "message": "Database not initialized"}
    
    result = await AuthService.verify_otp(request.smart_board_id, request.otp, db)
    if not result:
        raise HTTPException(status_code=400, detail="Invalid OTP or Session Expired")
        
    return result

@auth_router.post("/complete")
async def complete_device_registration(http_request: Request, request: DeviceRegisterCompleteRequest):
    """Phase 3: Hardware Binding"""
    if not db:
        return {"status": "error", "message": "Database not initialized"}
    
    # Optional: Extract Firebase UID from token to link accounts
    firebase_id_token = _extract_bearer_token(http_request)
    firebase_uid = None
    if firebase_id_token:
        decoded = await AuthService.verify_firebase_token(firebase_id_token)
        if decoded:
            firebase_uid = decoded.get("uid")

    result = await AuthService.complete_registration(
        board_id=request.smart_board_id,
        verification_token=request.verification_token,
        hardware_id=request.hardware_id,
        db=db,
        firebase_uid=firebase_uid
    )
    
    if not result:
        raise HTTPException(status_code=400, detail="Registration Failed: Invalid Token or Board ID")
        
    return result

app.include_router(auth_router)
app.include_router(api_router)

# ─── Admin / IT Dashboard Routes (O1/O2) ──────────────────────────────────────

admin_router = APIRouter(prefix="/api/v1/admin")

@admin_router.get("/heartbeats")
async def get_heartbeat_status():
    """Return heartbeat status for all boards (O1: IT Dashboard data source)."""
    statuses = HeartbeatService.get_all_status(db)
    stale_count = sum(1 for s in statuses if s["stale"])
    return {
        "status": "ok",
        "total_boards": len(statuses),
        "stale_boards": stale_count,
        "healthy_boards": len(statuses) - stale_count,
        "boards": statuses,
    }

@admin_router.get("/heartbeats/stale")
async def get_stale_boards():
    """Return only boards with missing heartbeats (O2: Alerting trigger)."""
    statuses = HeartbeatService.get_all_status(db)
    stale = [s for s in statuses if s["stale"]]
    return {
        "status": "ok",
        "stale_count": len(stale),
        "boards": stale,
    }

app.include_router(admin_router)

# --- Faculty Control ---
@app.post("/v1/board/session/create")
async def create_session_endpoint(request: SessionCreateRequest):
    logger.info(f"🚀 [Faculty] Creating session for: {request.course_name}")
    if not db:
        # Mock for measurement if DB is down
        sid = SessionService.generate_deterministic_id(request.slot_id or "MOCK")
        return {"status": "success", "session_id": sid, "data": {"session_id": sid, "otp": "123456"}}
    
    session = await SessionService.create_session(request.model_dump(), db)
    await ActiveSessionsService.create_active_session(session["session_id"], session["session_secret_half1"], db)
    return {"status": "success", "session_id": session["session_id"], "data": {"session_id": session["session_id"], "otp": session["otp"]}}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
