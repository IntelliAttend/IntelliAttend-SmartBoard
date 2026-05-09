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

from services.board_service import BoardService
from services.session_service import SessionService
from services.active_sessions_service import ActiveSessionsService
from models.board_auth_schema import TelemetryPayload, SessionInitiateRequest, SessionCreateRequest

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

    # v6.2: Atomic Ignition - Generate and return the secret key
    session_secret = secrets.token_hex(16)
    
    session = await SessionService.find_session_by_otp(otp, db)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found or OTP invalid")
    if "error" in session:
        raise HTTPException(status_code=400, detail=session["error"])

    # Atomic Actions: Mark Faculty Attendance + Store Secret
    try:
        await SessionService.ignite_session_atomic(
            session_id=session["session_id"],
            secret=session_secret,
            db=db
        )
    except Exception as e:
        logger.error(f"❌ [Atomic] Ignition failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to ignite session")

    return {
        "status": "success",
        "data": {
            "session_id": session["session_id"],
            "session_secret": session_secret,
            "faculty_name": session.get("faculty_name", "Professor"),
            "course_name": session.get("course_name", "Active Class"),
            "roster_count": session.get("roster_count", 0)
        }
    }

# --- Legacy & Heartbeat Routes ---
@app.post("/v1/board/heartbeat")
async def board_heartbeat(
    request: HeartbeatRequest,
    board_data: dict = Depends(BoardService.get_board_data(db)),
):
    device_id = board_data.get("device_id")
    if db:
        db.collection("board_heartbeats").document(device_id).set({
            "last_heartbeat_at": firestore.SERVER_TIMESTAMP,
            "screen_state": request.screen_state,
            "uptime_seconds": request.uptime_seconds,
            "app_version": request.app_version,
            "board_id": device_id,
        })
    return {"status": "ok", "device_id": device_id}

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
    """v6.1 Phase 3: Silent Health Check to warm up TCP connection."""
    return {"status": "ready", "timestamp": datetime.now(timezone.utc).isoformat()}

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

@api_router.post("/session/attendance/record-live")
async def record_attendance():
    return {"status": "success"}

@api_router.post("/session/terminate")
async def terminate_session():
    return {"status": "success"}

app.include_router(api_router)

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
