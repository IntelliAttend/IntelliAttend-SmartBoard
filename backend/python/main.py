import os
import secrets
import base64
import json
import logging
import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
import uvicorn
from fastapi import FastAPI, Depends, HTTPException, status, Request, Response, APIRouter, Header, WebSocket, WebSocketDisconnect
from fastapi.middleware.gzip import GZipMiddleware
from pydantic import BaseModel

from middleware.rate_limit_middleware import RateLimitMiddleware
from core.security import get_current_board_pg
from core.database import get_db as get_pg_session, async_session_factory
from models.sql_models import (
    BoardHeartbeat,
    ActiveSession,
    SessionStatus,
    SessionAttendee,
    AttendeeStatus,
    AttendanceVault,
)
from services.board_service import HeartbeatService
from services.session_service import SessionService
from services.auth_service import AuthService
from services.cache_service import CacheService
from services.alert_service import AlertService
from services.hydration_service import BoardHydrationService
from models.board_auth_schema import (
    TelemetryPayload,
    SessionInitiateRequest,
    SessionCreateRequest,
    VaultSyncRequest,
    DeviceRegisterInitiateRequest,
    DeviceRegisterVerifyRequest,
    DeviceRegisterCompleteRequest,
)

# Initialize Firebase Admin SDK (required for token verification + custom tokens)
import firebase_admin
from firebase_admin import credentials

if not firebase_admin._apps:
    cred_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT_KEY")
    if cred_path:
        cred = credentials.Certificate(cred_path)
    else:
        cred = credentials.ApplicationDefault()
    firebase_admin.initialize_app(cred)

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

STALE_THRESHOLD = timedelta(minutes=30)

async def stale_board_monitor():
    """
    Periodically checks for boards that haven't sent a heartbeat within the threshold.
    Auto-terminates active sessions belonging to stale boards.
    """
    while True:
        try:
            async with async_session_factory() as session:
                now = datetime.now(timezone.utc)
                cutoff = now - STALE_THRESHOLD

                # Find boards with stale heartbeats (no heartbeat within threshold)
                # Get latest heartbeat per board
                result = await session.execute(
                    select(BoardHeartbeat.board_id, BoardHeartbeat.last_heartbeat_at)
                    .distinct(BoardHeartbeat.board_id)
                    .order_by(BoardHeartbeat.board_id, BoardHeartbeat.last_heartbeat_at.desc())
                )
                rows = result.all()

                # Group by board_id to get latest
                latest_hb: dict[str, datetime] = {}
                for board_id, last_hb in rows:
                    if board_id not in latest_hb:
                        latest_hb[board_id] = last_hb

                stale_board_ids = [
                    bid for bid, last_hb in latest_hb.items()
                    if last_hb < cutoff
                ]

                for board_id in stale_board_ids:
                    await AlertService.notify_stale_board(
                        board_id,
                        latest_hb[board_id],
                    )

                    # Auto-terminate active sessions for stale boards
                    active_result = await session.execute(
                        select(ActiveSession)
                        .where(ActiveSession.room_id == board_id)
                        .where(ActiveSession.status == SessionStatus.ACTIVE)
                        .limit(1)
                    )
                    stale_session = active_result.scalar_one_or_none()
                    if stale_session:
                        logger.warning(
                            f"🔌 [Monitor] Auto-terminating session {stale_session.session_id} "
                            f"for stale board {board_id}"
                        )
                        stale_session.status = SessionStatus.ENDED
                        stale_session.ended_at = now
                        await session.merge(stale_session)

                await session.commit()
        except Exception as e:
            logger.error(f"❌ [Monitor] Stale board check failed: {e}")

        await asyncio.sleep(1800)  # Run every 30 minutes

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(stale_board_monitor())
    logger.info("🚀 [The Brain] Stale Board Monitor started (PG).")

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

# ─── v2.0 Heartbeat Model ──────────────────────────────────────────────────

class HeartbeatV2Request(BaseModel):
    boardId: str
    screenState: str = "unknown"
    uptimeSeconds: int = 0
    appVersion: str = "unknown"
    timestamp: str = ""

class PowerCommandRequest(BaseModel):
    action: str = "shutdown"
    reason: str = ""
    delay_seconds: int = 60
    command_id: str = ""

class NotificationRequest(BaseModel):
    notification_type: str = "info"
    display_mode: str = "default"
    priority: str = "P3"
    title: str = ""
    body: str = ""
    duration_seconds: int | None = None
    requires_acknowledgement: bool = False
    notification_id: str = ""
    attachment_url: str = ""
    attachment_name: str = ""
    attachment_type: str = ""
    attachment_size: int = 0

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

class BoardConnectionManager:
    """Tracks board_id → WebSocket for admin commands (1-to-1)."""
    def __init__(self):
        self._connections: dict[str, WebSocket] = {}
        self._pending: dict[str, list[dict]] = {}

    async def connect(self, board_id: str, ws: WebSocket):
        await ws.accept()
        self._connections[board_id] = ws
        queued = self._pending.pop(board_id, [])
        for cmd in queued:
            try:
                await ws.send_json(cmd)
            except Exception:
                pass

    async def disconnect(self, board_id: str):
        self._connections.pop(board_id, None)

    async def send_command(self, board_id: str, command: dict) -> bool:
        ws = self._connections.get(board_id)
        if ws is None:
            return False
        try:
            await ws.send_json(command)
            return True
        except Exception:
            self._connections.pop(board_id, None)
            return False

    def queue_command(self, board_id: str, command: dict):
        if board_id not in self._pending:
            self._pending[board_id] = []
        self._pending[board_id].append(command)

board_manager = BoardConnectionManager()

# --- Shared Logic (PostgreSQL) ---
async def _initiate_session_logic_pg(request: SessionInitiateRequest, board_data: dict, pg_session: AsyncSession, is_offline_fallback: bool = False):
    otp = request.otp
    if otp.endswith("_offline_generated"):
        logger.warning(f"⚠️ [TrustEngine] Offline Fallback detected.")
        otp = otp.replace("_offline_generated", "")

    session = await SessionService.find_session_by_otp_pg(otp, pg_session)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found or OTP invalid")
    if "error" in session:
        raise HTTPException(status_code=400, detail=session["error"])

    try:
        await SessionService.ignite_session_atomic_pg(session_id=session["session_id"], session=pg_session)
    except Exception as e:
        logger.error(f"❌ [Atomic] Ignition failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to ignite session")

    await CacheService.delete(SessionService._otp_cache_key(otp))

    # Invalidate hydration cache so the board picks up the ignited
    # session state immediately rather than waiting for TTL expiry.
    room_id = board_data.get("room_id")
    if room_id:
        await BoardHydrationService.invalidate(room_id)

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
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    board_id = board_data.get("user_id", "")
    if request.boardId != board_id:
        logger.warning(f"⚠️ [Heartbeat] boardId mismatch: client={request.boardId} auth={board_id}")
        raise HTTPException(status_code=403, detail="Board ID does not match authenticated board")

    now = datetime.now(timezone.utc)

    # Record heartbeat in PostgreSQL
    hb = BoardHeartbeat(
        board_id=board_id,
        screen_state=request.screenState,
        uptime_seconds=request.uptimeSeconds,
        app_version=request.appVersion,
        last_heartbeat_at=now,
    )
    pg_session.add(hb)

    # Check for active session
    session_result = await pg_session.execute(
        select(ActiveSession)
        .where(ActiveSession.room_id == board_data.get("room_id", ""))
        .where(ActiveSession.status.in_([SessionStatus.ACTIVE, SessionStatus.COMPLETED]))
        .limit(1)
    )
    active = session_result.scalar_one_or_none()

    return {
        "status": "ok",
        "server_time": now.isoformat(),
        "session": {
            "session_id": active.session_id,
            "status": active.status.value,
        } if active else None,
    }

@app.post("/api/v1/board/verify-otp")
async def verify_otp_v2(
    request: SessionInitiateRequest,
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    return await _initiate_session_logic_pg(request, board_data, pg_session)

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

async def _handle_attendance_submit(session_id: str, data: dict, ws: WebSocket) -> None:
    """Process faculty-submitted attendance via WebSocket.

    Expects:
      - present_emails: list[str]
      - absent_emails:  list[str]

    Upserts SessionAttendee rows and broadcasts confirmation.
    """
    present_emails = data.get("present_emails", [])
    absent_emails = data.get("absent_emails", [])
    now = datetime.now(timezone.utc)

    logger.info(
        f"📋 [WS] attendance_submit for session {session_id}: "
        f"{len(present_emails)} present, {len(absent_emails)} absent"
    )

    try:
        async with async_session_factory() as pg_session:
            for email in present_emails:
                result = await pg_session.execute(
                    select(SessionAttendee)
                    .where(SessionAttendee.session_id == session_id)
                    .where(SessionAttendee.student_id == email)
                    .limit(1)
                )
                existing = result.scalar_one_or_none()
                if existing:
                    existing.status = AttendeeStatus.PRESENT
                    existing.recorded_at = now
                else:
                    pg_session.add(SessionAttendee(
                        session_id=session_id,
                        student_id=email,
                        student_name="",
                        status=AttendeeStatus.PRESENT,
                        recorded_at=now,
                    ))

            for email in absent_emails:
                result = await pg_session.execute(
                    select(SessionAttendee)
                    .where(SessionAttendee.session_id == session_id)
                    .where(SessionAttendee.student_id == email)
                    .limit(1)
                )
                existing = result.scalar_one_or_none()
                if existing:
                    existing.status = AttendeeStatus.ABSENT
                    existing.recorded_at = now
                else:
                    pg_session.add(SessionAttendee(
                        session_id=session_id,
                        student_id=email,
                        student_name="",
                        status=AttendeeStatus.ABSENT,
                        recorded_at=now,
                    ))

            await pg_session.commit()

        await manager.broadcast(session_id, {
            "type": "attendance_submitted",
            "session_id": session_id,
            "present_count": len(present_emails),
            "absent_count": len(absent_emails),
            "timestamp": now.isoformat(),
        })
        logger.info(f"✅ [WS] Attendance submitted for session {session_id}")
    except Exception as e:
        logger.error(f"❌ [WS] attendance_submit error for {session_id}: {e}")
        try:
            await ws.send_json({
                "type": "attendance_submit_error",
                "session_id": session_id,
                "error": str(e),
            })
        except Exception:
            pass


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
        async with async_session_factory() as ws_session:
            att_result = await ws_session.execute(
                select(SessionAttendee)
                .where(SessionAttendee.session_id == session_id)
                .where(SessionAttendee.status == AttendeeStatus.PRESENT)
            )
            for att in att_result.scalars().all():
                present_students.append({
                    "student_id": att.student_id,
                    "student_name": att.student_name or "",
                    "status": "PRESENT",
                    "recorded_at": att.recorded_at.isoformat(),
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
                msg_type = data.get("type")
                if msg_type == "ping":
                    await websocket.send_json({"type": "pong"})
                elif msg_type == "attendance_submit":
                    await _handle_attendance_submit(session_id, data, websocket)
            except json.JSONDecodeError:
                pass
    except asyncio.TimeoutError:
        logger.warning(f"🔌 [WS] Client timeout — closing connection to session {session_id}")
    except WebSocketDisconnect:
        logger.info(f"🔌 [WS] Board disconnected from session {session_id}")
    finally:
        await manager.disconnect(session_id, websocket)

@app.websocket("/api/v1/websocket/board/{board_id}")
async def board_websocket(websocket: WebSocket, board_id: str, ticket: str = ""):
    ticket_data = _tickets.pop(ticket, None)
    if ticket_data is None:
        await websocket.close(code=1008, reason="Invalid or expired ticket")
        return
    if datetime.now(timezone.utc) > ticket_data["expires_at"]:
        await websocket.close(code=1008, reason="Ticket expired")
        return
    if ticket_data.get("board_id") != board_id:
        await websocket.close(code=1008, reason="Board ID mismatch")
        return

    await board_manager.connect(board_id, websocket)
    logger.info(f"🔌 [BoardWS] Board {board_id} connected for admin commands")

    try:
        while True:
            raw = await asyncio.wait_for(websocket.receive_text(), timeout=300)
            try:
                data = json.loads(raw)
                msg_type = data.get("type")
                if msg_type == "ping":
                    await websocket.send_json({"type": "pong"})
                elif msg_type == "system_command_ack":
                    logger.info(f"🔌 [BoardWS] ACK from {board_id}: {data}")
            except json.JSONDecodeError:
                pass
    except asyncio.TimeoutError:
        logger.warning(f"🔌 [BoardWS] Client timeout — {board_id}")
    except WebSocketDisconnect:
        logger.info(f"🔌 [BoardWS] Board {board_id} disconnected")
    finally:
        await board_manager.disconnect(board_id)

# --- Device Registration Router (PostgreSQL-backed) ---
#
# Replaces the legacy Firestore OTP flow. Boards authenticate via
# Firebase Auth email/password (Identity Toolkit REST). Registration
# state is persisted in PostgreSQL.
#
# Flow: POST /login -> POST /verify -> POST /complete

from fastapi import APIRouter

auth_router = APIRouter(prefix="/api/v1/device/register")


@auth_router.post("/login")
async def initiate_device_registration(
    body: DeviceRegisterInitiateRequest,
    authorization: str = Header(default=None),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="AUTH_FAILED: Missing Firebase Authorization header",
        )
    id_token = authorization.split(" ")[1]

    decoded = await AuthService.verify_firebase_token(id_token)
    if not decoded:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="AUTH_FAILED: Invalid Firebase ID token",
        )

    firebase_uid = decoded.get("uid", "")
    email = decoded.get("email", "")

    try:
        result = await AuthService.register_initiate_pg(
            smart_board_id=body.smart_board_id,
            firebase_uid=firebase_uid,
            email=email,
            session=pg_session,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[Auth] Registration initiation failed: {e}")
        raise HTTPException(status_code=500, detail="Registration initiation failed")

    return result


@auth_router.post("/verify")
async def verify_device_registration(
    body: DeviceRegisterVerifyRequest,
    pg_session: AsyncSession = Depends(get_pg_session),
):
    try:
        result = await AuthService.register_verify_pg(
            smart_board_id=body.smart_board_id,
            otp=body.otp,
            session=pg_session,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[Auth] OTP verification failed: {e}")
        raise HTTPException(status_code=500, detail="OTP verification failed")

    return result


@auth_router.post("/complete")
async def complete_device_registration(
    http_request: Request,
    authorization: str = Header(default=None),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="AUTH_FAILED: Missing Firebase Authorization header",
        )
    id_token = authorization.split(" ")[1]

    decoded = await AuthService.verify_firebase_token(id_token)
    if not decoded:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="AUTH_FAILED: Invalid Firebase ID token",
        )

    body = await http_request.json()
    smart_board_id = body.get("smart_board_id", "")
    verification_token = body.get("verification_token", "")
    hardware_id = body.get("hardware_id", "")
    metadata = body.get("metadata")

    if not smart_board_id or not verification_token or not hardware_id:
        raise HTTPException(status_code=400, detail="Missing required fields")

    try:
        result = await AuthService.register_complete_pg(
            smart_board_id=smart_board_id,
            verification_token=verification_token,
            hardware_id=hardware_id,
            metadata=metadata,
            session=pg_session,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[Auth] Registration completion failed: {e}")
        raise HTTPException(status_code=500, detail="Registration completion failed")

    return result


# --- Standard API Router (api/v1/board) ---
api_router = APIRouter(prefix="/api/v1/board")

class TimeSyncRequest(BaseModel):
    client_timestamp_ms: int

@api_router.post("/time")
async def sync_server_time(
    request: TimeSyncRequest,
    board_data: dict = Depends(get_current_board_pg),
):
    server_received = datetime.now(timezone.utc)
    received_ms = int(server_received.timestamp() * 1000)

    # Simulate a tiny processing delay so the response timestamp is slightly
    # ahead of the received timestamp (realistic for actual DB/CPU work).
    server_sent_ms = received_ms + 1

    return {
        "server_timestamp_ms": server_sent_ms,
        "server_received_at_ms": received_ms,
        "client_timestamp_ms": request.client_timestamp_ms,
        "processing_duration_ms": server_sent_ms - received_ms,
        "realm": "UTC",
    }

@api_router.get("/ready")
async def board_ready(board_data: dict = Depends(get_current_board_pg)):
    """Boot canary — confirms board is registered in users table."""
    return {"status": "registered", "board_id": board_data.get("user_id", "unknown")}

@api_router.get("/preflight")
async def get_preflight(
    response: Response,
    slot_id: str,
    x_retry_attempt: Optional[int] = Header(None, alias="X-Retry-Attempt"),
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    if x_retry_attempt and x_retry_attempt > 1:
        logger.warning(f"⚡ [PreFlight] High-priority retry detected (Attempt: {x_retry_attempt}) for slot {slot_id}")
    
    logger.info(f"⚡ [PreFlight] Request for slot: {slot_id}")
    response.headers["Cache-Control"] = "public, max-age=120"
    
    room_id = board_data.get("room_id", "")
    session_id = SessionService.generate_deterministic_id(slot_id)

    # Check existing pre-allocated session
    existing = await pg_session.execute(
        select(ActiveSession).where(ActiveSession.session_id == session_id)
    )
    existing_session = existing.scalar_one_or_none()

    if existing_session is None:
        half1 = base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip("=")
        new_session = ActiveSession(
            session_id=session_id,
            slot_id=slot_id,
            room_id=room_id,
            status=SessionStatus.PRE_ALLOCATED,
            session_secret_half1=half1,
            course_name="",
            faculty_name="",
            section_id="",
        )
        pg_session.add(new_session)

        # Invalidate hydration cache so the board picks up the new
        # pre-allocated session state on next sync.
        if room_id:
            await BoardHydrationService.invalidate(room_id)
    else:
        half1 = existing_session.session_secret_half1 or ""
    
    return {
        "status": "ready",
        "server_timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        "pre_allocated_session_id": session_id,
        "session_secret_half1": half1,
        "slot_verification": {
            "subject_name": existing_session.course_name if existing_session else "",
            "faculty_name": existing_session.faculty_name if existing_session else "",
        }
    }

@api_router.post("/telemetry")
async def receive_telemetry(
    payload: TelemetryPayload,
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    now = datetime.now(timezone.utc)
    hb = BoardHeartbeat(
        board_id=board_data.get("user_id", ""),
        screen_state=payload.model_dump().get("screen_state", "telemetry"),
        uptime_seconds=payload.model_dump().get("uptime_seconds", 0),
        app_version=payload.model_dump().get("app_version", "unknown"),
        last_heartbeat_at=now,
    )
    pg_session.add(hb)
    return {"status": "success"}

@api_router.get("/sync-context")
async def sync_context(board_data: dict = Depends(get_current_board_pg)):
    return {"status": "success", "data": board_data}

@api_router.post("/session/initiate")
async def initiate_session_api(
    request: SessionInitiateRequest,
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    return await _initiate_session_logic_pg(request, board_data, pg_session)

@api_router.post("/session/terminate")
async def terminate_session(
    request: Request,
    pg_session: AsyncSession = Depends(get_pg_session),
):
    body = await request.json()
    session_id = body.get("session_id", "")
    now = datetime.now(timezone.utc)

    if session_id:
        result = await pg_session.execute(
            select(ActiveSession)
            .where(ActiveSession.session_id == session_id)
            .limit(1)
        )
        active_session = result.scalar_one_or_none()

        if active_session:
            active_session.status = SessionStatus.ENDED
            active_session.ended_at = now
            pg_session.add(active_session)

            # Invalidate hydration cache so the board picks up any
            # post-session timetable or roster changes on next sync.
            if active_session.room_id:
                await BoardHydrationService.invalidate(active_session.room_id)

        await manager.broadcast(session_id, {
            "type": "session_ended",
            "session_id": session_id,
            "status": "ended",
            "timestamp": now.isoformat(),
        })

    return {"status": "success"}

class AttendanceSubmitRequest(BaseModel):
    session_id: str
    present_emails: list[str] = []
    absent_emails: list[str] = []

@api_router.post("/session/attendance/submit")
async def submit_attendance_rest(
    request: AttendanceSubmitRequest,
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """REST fallback for attendance submission (primary path is WebSocket)."""
    now = datetime.now(timezone.utc)
    session_id = request.session_id
    logger.info(
        f"📋 [REST] attendance/submit for {session_id}: "
        f"{len(request.present_emails)} present, {len(request.absent_emails)} absent"
    )

    for email in request.present_emails:
        result = await pg_session.execute(
            select(SessionAttendee)
            .where(SessionAttendee.session_id == session_id)
            .where(SessionAttendee.student_id == email)
            .limit(1)
        )
        existing = result.scalar_one_or_none()
        if existing:
            existing.status = AttendeeStatus.PRESENT
            existing.recorded_at = now
        else:
            pg_session.add(SessionAttendee(
                session_id=session_id,
                student_id=email,
                student_name="",
                status=AttendeeStatus.PRESENT,
                recorded_at=now,
            ))

    for email in request.absent_emails:
        result = await pg_session.execute(
            select(SessionAttendee)
            .where(SessionAttendee.session_id == session_id)
            .where(SessionAttendee.student_id == email)
            .limit(1)
        )
        existing = result.scalar_one_or_none()
        if existing:
            existing.status = AttendeeStatus.ABSENT
            existing.recorded_at = now
        else:
            pg_session.add(SessionAttendee(
                session_id=session_id,
                student_id=email,
                student_name="",
                status=AttendeeStatus.ABSENT,
                recorded_at=now,
            ))

    await pg_session.commit()

    await manager.broadcast(session_id, {
        "type": "attendance_submitted",
        "session_id": session_id,
        "present_count": len(request.present_emails),
        "absent_count": len(request.absent_emails),
        "timestamp": now.isoformat(),
    })

    return {"status": "success", "present": len(request.present_emails), "absent": len(request.absent_emails)}

@api_router.post("/sync/vault")
async def sync_vault(
    request: VaultSyncRequest,
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Flush offline attendance scans from the board's local Isar vault."""
    now = datetime.now(timezone.utc)
    for scan in request.queued_scans:
        entry = AttendanceVault(
            session_id=request.session_id,
            student_id=scan.student_id,
            qr_payload=scan.qr_payload,
            timestamp=scan.timestamp,
            synced_at=now,
            board_id=board_data.get("user_id", "unknown"),
        )
        pg_session.add(entry)

    logger.info(f"📤 [VaultSync] Synced {len(request.queued_scans)} scans for session {request.session_id}")
    return {"status": "success", "synced_count": len(request.queued_scans)}

@api_router.get("/hydrate")
async def board_hydrate(
    board_data: dict = Depends(get_current_board_pg),
    session: AsyncSession = Depends(get_pg_session),
):
    """Primary hydration — full board context download.

    Returns profile, weekly schedule, rosters, and manifest_hash.
    Cached server-side in Redis for 300s (hydrate:board:{room_id}).
    """
    room_id = board_data.get("room_id")
    if not room_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Board not bound to a room",
        )

    payload = await BoardHydrationService.get_hydration_payload(
        board_data, session
    )

    if "error" in payload:
        raise HTTPException(
            status_code=payload.get("code", 500),
            detail=payload["error"],
        )

    return payload

app.include_router(auth_router)
app.include_router(api_router)

# ─── Admin / IT Dashboard Routes (O1/O2) ──────────────────────────────────────

admin_router = APIRouter(prefix="/api/v1/admin")

@admin_router.get("/heartbeats", dependencies=[Depends(AuthService.require_role(["admin"]))])
async def get_heartbeat_status(
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Return heartbeat status for all boards (PG-backed)."""
    statuses = await HeartbeatService.get_all_status_pg(pg_session)
    stale_count = sum(1 for s in statuses if s["stale"])
    return {
        "status": "ok",
        "total_boards": len(statuses),
        "stale_boards": stale_count,
        "healthy_boards": len(statuses) - stale_count,
        "boards": statuses,
    }

@admin_router.get("/heartbeats/stale", dependencies=[Depends(AuthService.require_role(["admin"]))])
async def get_stale_boards(
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Return only boards with missing heartbeats (PG-backed)."""
    statuses = await HeartbeatService.get_all_status_pg(pg_session)
    stale = [s for s in statuses if s["stale"]]
    return {
        "status": "ok",
        "stale_count": len(stale),
        "boards": stale,
    }

@admin_router.post("/board/{board_id}/power")
async def admin_board_power(
    board_id: str,
    command: PowerCommandRequest,
    admin_data: dict = Depends(AuthService.require_role(["admin"])),
):
    """Send a shutdown/restart command to a smart board."""
    import uuid
    cmd_id = command.command_id or str(uuid.uuid4())
    payload = {
        "type": "system_command",
        "command_id": cmd_id,
        "action": command.action,
        "reason": command.reason or "",
        "delay_seconds": max(5, min(600, command.delay_seconds)),
        "issued_at": datetime.now(timezone.utc).isoformat(),
    }

    sent = await board_manager.send_command(board_id, payload)
    if sent:
        logger.info(f"⚡ [Admin] Power command {cmd_id} sent to board {board_id}")
        return {
            "status": "sent",
            "command_id": cmd_id,
            "board_id": board_id,
            "board_online": True,
        }
    else:
        board_manager.queue_command(board_id, payload)
        logger.info(f"⚡ [Admin] Power command {cmd_id} queued for offline board {board_id}")
        return {
            "status": "queued",
            "command_id": cmd_id,
            "board_id": board_id,
            "board_online": False,
        }

@admin_router.post("/board/{board_id}/notification")
async def admin_board_notification(
    board_id: str,
    notification: NotificationRequest,
    admin_data: dict = Depends(AuthService.require_role(["admin"])),
):
    """Send a notification to a smart board.

    The notification is delivered via the board's existing WebSocket
    connection using the Contract v1 notification schema. If the board
    is offline, the notification is queued and delivered on reconnection.
    """
    import uuid

    nid = notification.notification_id or str(uuid.uuid4())
    payload_payload = {
        "notification_id": nid,
        "version": 1,
        "priority": notification.priority,
        "notification_type": notification.notification_type,
        "display_mode": notification.display_mode,
        "title": notification.title,
        "body": notification.body,
        "duration_seconds": notification.duration_seconds,
        "requires_acknowledgement": notification.requires_acknowledgement,
    }

    # Include attachment metadata in the 'data' field if provided
    if notification.attachment_url:
        payload_payload["data"] = {
            "attachment_url": notification.attachment_url,
            "attachment_name": notification.attachment_name,
            "attachment_type": notification.attachment_type,
            "attachment_size": notification.attachment_size,
        }

    payload = {
        "event_type": "notification",
        "event_id": str(uuid.uuid4()),
        "version": 1,
        "institution_id": "",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "payload": payload_payload,
    }

    sent = await board_manager.send_command(board_id, payload)
    if sent:
        logger.info(f"🔔 [Admin] Notification {nid} sent to board {board_id}")
        return {
            "status": "sent",
            "notification_id": nid,
            "board_id": board_id,
            "board_online": True,
        }
    else:
        board_manager.queue_command(board_id, payload)
        logger.info(f"🔔 [Admin] Notification {nid} queued for offline board {board_id}")
        return {
            "status": "queued",
            "notification_id": nid,
            "board_id": board_id,
            "board_online": False,
        }

app.include_router(admin_router)

# --- Resource Endpoints (stub — return empty lists until R2 integration) ---
@app.get("/api/v1/resources/my")
async def get_my_resources(
    session_id: str = "",
    section_id: str = "",
    course_name: str = "",
):
    return []

@app.get("/api/v1/resources/college")
async def get_college_resources(
    course_name: str = "",
):
    return []

# --- Faculty Control ---
@app.post("/v1/board/session/create", dependencies=[Depends(AuthService.require_role(["faculty", "admin"]))])
async def create_session_endpoint(
    request: SessionCreateRequest,
    pg_session: AsyncSession = Depends(get_pg_session),
):
    logger.info(f"🚀 [Faculty] Creating session for: {request.course_name}")
    session = await SessionService.create_session_pg(request.model_dump(), pg_session)
    return {"status": "success", "session_id": session["session_id"], "data": {"session_id": session["session_id"], "otp": session["otp"]}}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
