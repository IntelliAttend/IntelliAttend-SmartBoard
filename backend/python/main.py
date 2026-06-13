import os
import secrets
import base64
import json
import logging
import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional
import uvicorn
import firebase_admin
from firebase_admin import credentials
from google.cloud import firestore
from fastapi import FastAPI, Depends, HTTPException, status, Request, Response, APIRouter, Header, WebSocket, WebSocketDisconnect
from fastapi.middleware.gzip import GZipMiddleware
from pydantic import BaseModel

from middleware.rate_limit_middleware import RateLimitMiddleware
from core.security import get_current_board
from services.board_service import HeartbeatService
from services.session_service import SessionService
from services.active_sessions_service import ActiveSessionsService
from services.auth_service import AuthService
from services.cache_service import CacheService
from services.alert_service import AlertService
from models.board_auth_schema import (
    TelemetryPayload,
    SessionInitiateRequest,
    SessionCreateRequest,
    VaultSyncRequest,
)

# Load JWT Secret — fail hard if not set
JWT_SECRET = os.environ.get("JWT_SECRET")
if not JWT_SECRET:
    raise RuntimeError(
        "JWT_SECRET environment variable is not set. "
        "The application cannot start securely without it."
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

# --- Background Task: Stale Board Monitor ---

async def stale_board_monitor():
    """
    Periodically checks for boards that haven't sent a heartbeat within the threshold.
    Auto-terminates active sessions belonging to stale boards.
    """
    while True:
        try:
            if db:
                statuses = await HeartbeatService.get_all_status(db)
                for s in statuses:
                    if s["stale"]:
                        last_seen = datetime.fromisoformat(s["last_heartbeat_at"]) if s["last_heartbeat_at"] else datetime.now(timezone.utc)
                        await AlertService.notify_stale_board(s["board_id"], last_seen)

                        active_sessions = db.collection("ActiveSessions").where("room_id", "==", s["board_id"]).where("status", "==", "active").limit(1).stream()
                        async for sess in active_sessions:
                            sess_id = sess.to_dict().get("session_id")
                            if sess_id:
                                logger.warning(f"🔌 [Monitor] Auto-terminating session {sess_id} for stale board {s['board_id']}")
                                await db.collection("Sessions").document(sess_id).update({
                                    "status": "ended",
                                    "ended_at": firestore.SERVER_TIMESTAMP,
                                })
                                await db.collection("ActiveSessions").document(sess_id).update({
                                    "status": "completed",
                                    "ended_at": firestore.SERVER_TIMESTAMP,
                                })
        except Exception as e:
            logger.error(f"❌ [Monitor] Stale board check failed: {e}")
        
        await asyncio.sleep(300) # Run every 5 minutes

@app.on_event("startup")
async def startup_event():
    # Start the monitor in the background
    asyncio.create_task(stale_board_monitor())
    logger.info("🚀 [The Brain] Stale Board Monitor started.")

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
    
    # v5.4: Use AsyncClient to prevent blocking the event loop
    db = firestore.AsyncClient()
    logger.info("[The Brain] Firebase AsyncClient initialized.")
except Exception as e:
    logger.error(f"[The Brain] Firebase Init Error: {e}")
    db = None

# ─── v2.0 Heartbeat Model ──────────────────────────────────────────────────

class HeartbeatV2Request(BaseModel):
    boardId: str
    screenState: str = "unknown"
    uptimeSeconds: int = 0
    appVersion: str = "unknown"
    timestamp: str = ""

# ─── WebSocket Ticket (in-memory store) ────────────────────────────────────

_tickets: dict[str, dict] = {}

def _generate_ticket() -> str:
    return f"tkt_{secrets.token_hex(16)}"

class ConnectionManager:
    def __init__(self):
        self._connections: dict[str, set[WebSocket]] = {}

    async def connect(self, session_id: str, ws: WebSocket):
        await ws.accept()
        if session_id not in self._connections:
            self._connections[session_id] = set()
        self._connections[session_id].add(ws)

    async def disconnect(self, session_id: str, ws: WebSocket):
        self._connections.get(session_id, set()).discard(ws)
        if not self._connections.get(session_id):
            self._connections.pop(session_id, None)

    async def broadcast(self, session_id: str, message: dict):
        payload = json.dumps(message)
        for ws in list(self._connections.get(session_id, set())):
            try:
                await ws.send_text(payload)
            except Exception:
                self._connections.get(session_id, set()).discard(ws)

manager = ConnectionManager()

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
            "roster_count": session.get("roster_count", 0),
            "section_id": session.get("section_id", ""),
        }
    }

# ─── v2.0 Endpoints ─────────────────────────────────────────────────────────

@app.post("/api/v1/board/heartbeat")
async def board_heartbeat_v2(
    request: HeartbeatV2Request,
    board_data: dict = Depends(get_current_board(db)),
):
    authenticated_id = board_data.get("smart_board_id") or board_data.get("board_id") or board_data.get("device_id", "")
    if request.boardId != authenticated_id:
        logger.warning(f"⚠️ [Heartbeat] boardId mismatch: client={request.boardId} auth={authenticated_id}")
        raise HTTPException(status_code=403, detail="Board ID does not match authenticated board")
    board_id = request.boardId
    if db:
        await db.collection("board_heartbeats").document(board_id).set({
            "last_heartbeat_at": firestore.SERVER_TIMESTAMP,
            "screen_state": request.screenState,
            "uptime_seconds": request.uptimeSeconds,
            "app_version": request.appVersion,
            "timestamp": request.timestamp,
        }, merge=True)

        session_docs = db.collection("ActiveSessions").where("room_id", "==", board_id).where("status", "in", ["active", "completed"]).limit(1).stream()
        async for doc in session_docs:
            data = doc.to_dict()
            return {
                "status": "ok",
                "server_time": datetime.now(timezone.utc).isoformat(),
                "session": {
                    "session_id": data.get("session_id"),
                    "status": data.get("status", "active"),
                }
            }

    return {
        "status": "ok",
        "server_time": datetime.now(timezone.utc).isoformat(),
        "session": None
    }

@app.post("/api/v1/board/verify-otp")
async def verify_otp_v2(
    request: SessionInitiateRequest,
    board_data: dict = Depends(get_current_board(db)),
):
    return await _initiate_session_logic(request, board_data)

@app.post("/api/v1/websocket/ticket")
async def get_websocket_ticket(request: Request):
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

    firebase_id_token = auth.split(" ")[1]
    decoded = await AuthService.verify_firebase_token(firebase_id_token)
    if not decoded:
        raise HTTPException(status_code=401, detail="Invalid Firebase ID token")

    ticket = _generate_ticket()
    _tickets[ticket] = {
        "board_id": decoded.get("uid", "unknown"),
        "expires_at": datetime.now(timezone.utc) + timedelta(seconds=10),
    }
    logger.info(f"🔑 [Ticket] Issued ticket {ticket[:16]}... for board {decoded.get('uid', 'unknown')}")
    return {"ticket": ticket, "expires_in": 10}

@app.websocket("/api/v1/websocket/session/{session_id}")
async def session_websocket(websocket: WebSocket, session_id: str, ticket: str = ""):
    ticket_data = _tickets.pop(ticket, None)
    if ticket_data is None:
        await websocket.close(code=1008, reason="Invalid or expired ticket")
        return

    if datetime.now(timezone.utc) > ticket_data["expires_at"]:
        await websocket.close(code=1008, reason="Ticket expired")
        return

    await manager.connect(session_id, websocket)
    logger.info(f"🔌 [WS] Board connected to session {session_id}")

    try:
        present_students = []
        if db:
            attendees = db.collection("ActiveSessions").document(session_id).collection("attendees").stream()
            async for doc in attendees:
                data = doc.to_dict()
                present_students.append({
                    "student_id": data.get("student_id", ""),
                    "student_name": data.get("student_name", ""),
                    "status": "PRESENT",
                    "recorded_at": data.get("recorded_at", datetime.now(timezone.utc).isoformat()),
                })

        await websocket.send_json({
            "type": "full_state_sync",
            "session_id": session_id,
            "total_present": len(present_students),
            "present_students": present_students,
            "message": "Connected and state synchronized",
        })

        while True:
            raw = await asyncio.wait_for(websocket.receive_text(), timeout=300)
            try:
                data = json.loads(raw)
                if data.get("type") == "ping":
                    await websocket.send_json({"type": "pong"})
            except json.JSONDecodeError:
                pass
    except asyncio.TimeoutError:
        logger.warning(f"🔌 [WS] Client timeout — closing connection to session {session_id}")
    except WebSocketDisconnect:
        logger.info(f"🔌 [WS] Board disconnected from session {session_id}")
    finally:
        await manager.disconnect(session_id, websocket)

# ─── DEPRECATED: Legacy /v1/board/session/initiate ────────────────────────
#
# Replaced by /api/v1/board/session/initiate (defined in the api_router below).
# The board should use the /api/v1/board/* endpoints with Firebase Auth.
# ─────────────────────────────────────────────────────────────────────────
# @app.post("/v1/board/session/initiate")
# async def initiate_session_legacy(
#     request: SessionInitiateRequest,
#     board_data: dict = Depends(get_current_board(db)),
# ):
#     return await _initiate_session_logic(request, board_data)

# --- Standard API Router (api/v1/board) ---
api_router = APIRouter(prefix="/api/v1/board")

@api_router.get("/time")
async def get_server_time():
    return {
        "status": "success",
        "server_timestamp_ms": int(datetime.now(timezone.utc).timestamp() * 1000)
    }

@api_router.get("/ready")
async def board_ready(board_data: dict = Depends(get_current_board(db))):
    """Boot canary — confirms board is registered in smart_boards collection."""
    board_id = board_data.get("smart_board_id") or board_data.get("board_id") or board_data.get("device_id", "unknown")
    return {"status": "registered", "board_id": board_id}

@api_router.get("/preflight")
async def get_preflight(
    response: Response,
    slot_id: str,
    x_retry_attempt: Optional[int] = Header(None, alias="X-Retry-Attempt"),
    board_data: dict = Depends(get_current_board(db))
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
    slot_doc = await db.collection("timetable_slots").document(slot_id).get()
    if not slot_doc.exists:
        raise HTTPException(status_code=404, detail="Slot not found")
    
    slot_data = slot_doc.to_dict()
    session_id = SessionService.generate_deterministic_id(slot_id)
    session_doc = await db.collection("Sessions").document(session_id).get()

    if not session_doc.exists:
        half1 = base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip("=")
        section_id = slot_data.get("section_id", "")
        session_data = {
            "session_secret_half1": half1,
            "status": "pre_allocated",
            "slot_id": slot_id,
            "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "course_name": slot_data.get("subject_name", ""),
            "faculty_name": slot_data.get("faculty_name", ""),
            "section_id": section_id,
            "created_at": firestore.SERVER_TIMESTAMP,
        }
        await db.collection("Sessions").document(session_id).set(session_data)
        await db.collection("ActiveSessions").document(session_id).set({
            "session_id": session_id,
            "room_id": room_id,
            "status": "pre_allocated",
            "course_name": session_data["course_name"],
            "faculty_name": session_data["faculty_name"],
            "section_id": section_id,
            "created_at": firestore.SERVER_TIMESTAMP,
        })
    else:
        session_data = session_doc.to_dict()

    return {
        "status": "ready",
        "server_timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        "pre_allocated_session_id": session_id,
        "slot_verification": {
            "subject_name": slot_data.get("subject_name", "Unknown"),
            "faculty_name": slot_data.get("faculty_name", "Unknown"),
        }
    }

@api_router.post("/telemetry")
async def receive_telemetry(payload: TelemetryPayload, board_data: dict = Depends(get_current_board(db))):
    if db:
        await db.collection("smart_boards").document(board_data["smart_board_id"]).update({
            "health": {**payload.model_dump(), "last_seen": firestore.SERVER_TIMESTAMP}
        })
    return {"status": "success"}

@api_router.get("/sync-context")
async def sync_context(board_data: dict = Depends(get_current_board(db))):
    return {"status": "success", "data": board_data}

@api_router.post("/session/initiate")
async def initiate_session_api(request: SessionInitiateRequest, board_data: dict = Depends(get_current_board(db))):
    return await _initiate_session_logic(request, board_data)

@api_router.post("/session/terminate")
async def terminate_session(request: Request):
    body = await request.json()
    session_id = body.get("session_id", "")

    if db and session_id:
        await db.collection("Sessions").document(session_id).update({
            "status": "ended",
            "ended_at": firestore.SERVER_TIMESTAMP,
        })
        await db.collection("ActiveSessions").document(session_id).update({
            "status": "completed",
            "ended_at": firestore.SERVER_TIMESTAMP,
        })

        await manager.broadcast(session_id, {
            "type": "session_ended",
            "session_id": session_id,
            "status": "ended",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

    return {"status": "success"}

@api_router.post("/session/attendance/record-live")
async def record_attendance(request: Request):
    body = await request.json()
    session_id = body.get("session_id", "")
    student_id = body.get("student_id", "")
    student_name = body.get("student_name", body.get("student_id", ""))

    if db and session_id and student_id:
        attendee_ref = db.collection("ActiveSessions").document(session_id).collection("attendees").document(student_id)
        await attendee_ref.set({
            "student_id": student_id,
            "student_name": student_name,
            "status": "PRESENT",
            "recorded_at": datetime.now(timezone.utc).isoformat(),
        })

        await manager.broadcast(session_id, {
            "type": "ATTENDANCE_MARKED",
            "student_id": student_id,
            "studentName": student_name,
            "status": "PRESENT",
            "trust_score": 100,
            "recorded_at": datetime.now(timezone.utc).isoformat(),
        })

    return {"status": "success"}

@api_router.post("/sync/vault")
async def sync_vault(
    request: VaultSyncRequest,
    board_data: dict = Depends(get_current_board(db)),
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
                "board_id": board_data.get("smart_board_id", "unknown"),
            })
        await batch.commit()
        logger.info(f"📤 [VaultSync] Synced {len(request.queued_scans)} scans for session {request.session_id}")
    return {"status": "success", "synced_count": len(request.queued_scans)}

# ─── DEPRECATED: Legacy OTP Registration Router ───────────────────────────
#
# The /api/v1/device/register/* endpoints implemented OTP-based board
# registration (initiate -> verify -> complete) with custom JWT issuance
# and refresh token rotation.
#
# SmartBoard now authenticates using Firebase Auth email/password, the
# same as the Faculty and Student mobile apps. Board accounts are
# provisioned via Firebase Auth Admin at install time.
#
# Key replacements:
#   POST /login             -> Firebase Auth signInWithEmailAndPassword()
#   POST /verify            -> (not needed - no OTP flow)
#   POST /complete          -> (not needed - no hardware binding)
#   POST /token/refresh     -> Firebase SDK auto-refresh (user.getIdToken())
#   POST /deregister        -> (not needed - managed via Firebase Auth Admin)
#
# Preserved for reference in case re-registration flows are revisited.
# ─────────────────────────────────────────────────────────────────────────
# auth_router = APIRouter(prefix="/api/v1/device/register")
#
# _otp_attempts: dict[str, dict] = {}
# _OTP_MAX_ATTEMPTS = 10
# _OTP_LOCKOUT_MINUTES = 15
#
# def _check_otp_rate_limit(board_id: str):
#     now = datetime.now(timezone.utc)
#     state = _otp_attempts.get(board_id)
#     if state:
#         lockout_until = state.get("lockout_until")
#         if lockout_until and now < lockout_until:
#             remaining = int((lockout_until - now).total_seconds())
#             raise HTTPException(status_code=429, detail=f"Too many OTP attempts. Try again in {remaining} seconds.")
#         if lockout_until and now >= lockout_until:
#             _otp_attempts.pop(board_id, None)
#
# def _record_otp_attempt(board_id: str, success: bool):
#     now = datetime.now(timezone.utc)
#     state = _otp_attempts.get(board_id, {"count": 0, "lockout_until": None})
#     if success:
#         _otp_attempts.pop(board_id, None)
#         return
#     state["count"] += 1
#     if state["count"] >= _OTP_MAX_ATTEMPTS:
#         state["lockout_until"] = now + timedelta(minutes=_OTP_LOCKOUT_MINUTES)
#         logger.warning(f"[RateLimit] Board {board_id} locked out for {_OTP_LOCKOUT_MINUTES} min")
#     _otp_attempts[board_id] = state
#
# def _extract_bearer_token(request: Request) -> Optional[str]:
#     auth_header = request.headers.get("Authorization")
#     if auth_header and auth_header.startswith("Bearer "):
#         return auth_header.split(" ")[1]
#     return None
#
# @auth_router.post("/login")
# async def initiate_device_registration(request: DeviceRegisterInitiateRequest):
#     if not db:
#         return {"status": "error", "message": "Database not initialized"}
#     result = await AuthService.initiate_registration(request.smart_board_id, db)
#     if not result:
#         raise HTTPException(status_code=400, detail="Board ID not provisioned")
#     return result
#
# @auth_router.post("/verify")
# async def verify_device_registration(request: DeviceRegisterVerifyRequest):
#     if not db:
#         return {"status": "error", "message": "Database not initialized"}
#     _check_otp_rate_limit(request.smart_board_id)
#     result = await AuthService.verify_otp(request.smart_board_id, request.otp, db)
#     if not result:
#         _record_otp_attempt(request.smart_board_id, success=False)
#         raise HTTPException(status_code=400, detail="Invalid OTP or Session Expired")
#     _record_otp_attempt(request.smart_board_id, success=True)
#     return result
#
# @auth_router.post("/complete")
# async def complete_device_registration(http_request: Request, request: DeviceRegisterCompleteRequest):
#     if not db:
#         return {"status": "error", "message": "Database not initialized"}
#     firebase_id_token = _extract_bearer_token(http_request)
#     firebase_uid = None
#     if firebase_id_token:
#         decoded = await AuthService.verify_firebase_token(firebase_id_token)
#         if decoded:
#             firebase_uid = decoded.get("uid")
#     result = await AuthService.complete_registration(
#         board_id=request.smart_board_id,
#         verification_token=request.verification_token,
#         hardware_id=request.hardware_id,
#         db=db,
#         firebase_uid=firebase_uid
#     )
#     if not result:
#         raise HTTPException(status_code=400, detail="Registration Failed: Invalid Token or Board ID")
#     return result
#
# @auth_router.post("/token/refresh")
# async def refresh_board_token(refresh_token: str = Header(alias="X-Refresh-Token")):
#     if not db:
#         return {"status": "error", "message": "Database not initialized"}
#     result = await AuthService.refresh_access_token(refresh_token, db)
#     if not result:
#         raise HTTPException(status_code=401, detail="INVALID_REFRESH_TOKEN")
#     return result
#
# @auth_router.post("/deregister")
# async def deregister_board(board_data: dict = Depends(get_current_board(db))):
#     if not db:
#         return {"status": "error", "message": "Database not initialized"}
#     board_id = board_data.get("smart_board_id")
#     device_id = board_data.get("device_id")
#     tokens = db.collection("refresh_tokens").where("board_id", "==", board_id).where("device_id", "==", device_id).stream()
#     async for token in tokens:
#         await token.reference.delete()
#     await db.collection("smart_boards").document(board_id).update({
#         "is_registered": False,
#         "device_id": None,
#         "status": "PROVISIONED",
#         "last_deregistered_at": firestore.SERVER_TIMESTAMP
#     })
#     logger.info(f"[Auth] Board {board_id} deregistered successfully.")
#     return {"status": "success", "message": "Board deregistered and tokens revoked"}
#
# app.include_router(auth_router)

app.include_router(api_router)

# ─── Admin / IT Dashboard Routes (O1/O2) ──────────────────────────────────────

admin_router = APIRouter(prefix="/api/v1/admin")

@admin_router.get("/heartbeats", dependencies=[Depends(AuthService.require_role(["admin"]))])
async def get_heartbeat_status():
    """Return heartbeat status for all boards (O1: IT Dashboard data source)."""
    statuses = await HeartbeatService.get_all_status(db)
    stale_count = sum(1 for s in statuses if s["stale"])
    return {
        "status": "ok",
        "total_boards": len(statuses),
        "stale_boards": stale_count,
        "healthy_boards": len(statuses) - stale_count,
        "boards": statuses,
    }

@admin_router.get("/heartbeats/stale", dependencies=[Depends(AuthService.require_role(["admin"]))])
async def get_stale_boards():
    """Return only boards with missing heartbeats (O2: Alerting trigger)."""
    statuses = await HeartbeatService.get_all_status(db)
    stale = [s for s in statuses if s["stale"]]
    return {
        "status": "ok",
        "stale_count": len(stale),
        "boards": stale,
    }

app.include_router(admin_router)

# --- Faculty Control ---
@app.post("/v1/board/session/create", dependencies=[Depends(AuthService.require_role(["faculty", "admin"]))])
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
