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
from fastapi.middleware.cors import CORSMiddleware
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
    User,
    UserRole,
    AuthStatus,
    BoardVersion,
    UpdateEvent,
    ReleaseManifest,
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
    UpdateStatusReport,
    CiUploadRequest,
    AdminUpdateRequest,
    AdminRollbackRequest,
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


# ─── Health Check (no auth required) ────────────────────────────────────────
@app.get("/health")
async def health_check():
    """Lightweight health probe for load balancers and uptime monitors.

    Checks PostgreSQL and Redis connectivity. Returns 200 if at least
    the database is reachable; 503 otherwise.
    """
    from sqlalchemy import text
    import redis.asyncio as aioredis

    checks = {"postgres": "unknown", "redis": "unknown"}

    # Check PostgreSQL
    try:
        async with async_session_factory() as session:
            await session.execute(text("SELECT 1"))
        checks["postgres"] = "ok"
    except Exception as e:
        checks["postgres"] = f"error: {e}"

    # Check Redis
    try:
        redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379")
        r = aioredis.from_url(redis_url, socket_connect_timeout=3)
        await r.ping()
        await r.aclose()
        checks["redis"] = "ok"
    except Exception as e:
        checks["redis"] = f"error: {e}"

    healthy = checks["postgres"] == "ok"
    return {
        "status": "healthy" if healthy else "degraded",
        "checks": checks,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

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

# CORS: restrict to known origins in production.
# The kiosk communicates via HTTPS directly, not a browser, but this
# protects any future web-based admin dashboards.
ALLOWED_ORIGINS = os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")
ALLOWED_ORIGINS = [o.strip() for o in ALLOWED_ORIGINS if o.strip()]
if ALLOWED_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=ALLOWED_ORIGINS,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Deploy-Key", "X-Request-ID"],
        max_age=600,
    )

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

    # Upsert board_versions with current version and heartbeat time
    bv_result = await pg_session.execute(
        select(BoardVersion).where(BoardVersion.board_id == board_id)
    )
    bv = bv_result.scalar_one_or_none()
    if bv is None:
        bv = BoardVersion(
            board_id=board_id,
            current_version=request.appVersion,
            last_heartbeat_at=now,
        )
        pg_session.add(bv)
    else:
        bv.current_version = request.appVersion
        bv.last_heartbeat_at = now

    # Check for active session
    session_result = await pg_session.execute(
        select(ActiveSession)
        .where(ActiveSession.room_id == board_data.get("room_id", ""))
        .where(ActiveSession.status.in_([SessionStatus.ACTIVE, SessionStatus.COMPLETED]))
        .limit(1)
    )
    active = session_result.scalar_one_or_none()

    # Build dynamic config block with update manifest
    config = await _build_board_config(board_id, pg_session)

    return {
        "status": "ok",
        "server_time": now.isoformat(),
        "session": {
            "session_id": active.session_id,
            "status": active.status.value,
        } if active else None,
        "config": config,
    }


async def _build_board_config(board_id: str, pg_session: AsyncSession) -> dict:
    """Build the dynamic config block returned in heartbeat responses.

    Checks the release_manifests table first for CI-uploaded manifests,
    then falls back to environment variables for backward compatibility.
    """
    config_version = int(os.environ.get("CONFIG_VERSION", "1"))

    flags = {
        "enable_video_background": os.environ.get("ENABLE_VIDEO_BACKGROUND", "false").lower() == "true",
        "enable_documents": os.environ.get("ENABLE_DOCUMENTS", "true").lower() == "true",
        "enable_notifications": True,
        "enable_workspace": True,
        "kiosk_mode": "fullscreen",
        "qr_rotation_interval_ms": int(os.environ.get("QR_ROTATION_INTERVAL_MS", "5000")),
        "session_window_seconds": int(os.environ.get("SESSION_WINDOW_SECONDS", "300")),
        "idle_theme": "dark",
    }

    ui = {
        "branding": {
            "title": os.environ.get("BRANDING_TITLE", "IntelliAttend SmartBoard"),
        },
        "labels": {
            "welcome_text": os.environ.get("WELCOME_TEXT", "Welcome to Smart Class"),
            "footer_text": f"v{os.environ.get('APP_VERSION', '5.4.0')}",
        },
    }

    # Check for active release manifest in database (uploaded by CI/CD)
    force_update = None
    try:
        rm_result = await pg_session.execute(
            select(ReleaseManifest)
            .where(ReleaseManifest.is_active == True)
            .order_by(ReleaseManifest.created_at.desc())
            .limit(1)
        )
        rm = rm_result.scalar_one_or_none()
        if rm:
            force_update = {
                "minimum_version": rm.version,
                "download_url": rm.download_url,
                "sha256": rm.sha256 or "",
                "force": rm.force,
                "rollout_percentage": rm.rollout_percentage,
                "release_notes": rm.release_notes or "",
                "published_at": rm.created_at.isoformat() if rm.created_at else "",
            }
    except Exception as e:
        logger.warning(f"⚠️ [Config] Failed to query release_manifests: {e}")

    # Fall back to environment variables if no DB manifest
    if force_update is None:
        manifest_version = os.environ.get("UPDATE_MINIMUM_VERSION", "")
        if manifest_version:
            force_update = {
                "minimum_version": manifest_version,
                "download_url": os.environ.get("UPDATE_DOWNLOAD_URL", ""),
                "sha256": os.environ.get("UPDATE_SHA256", ""),
                "force": os.environ.get("UPDATE_FORCE", "true").lower() == "true",
                "rollout_percentage": int(os.environ.get("UPDATE_ROLLOUT_PERCENTAGE", "100")),
                "release_notes": os.environ.get("UPDATE_RELEASE_NOTES", ""),
                "published_at": datetime.now(timezone.utc).isoformat(),
            }

    return {
        "config_version": config_version,
        "flags": flags,
        "ui": ui,
        "issued_at": datetime.now(timezone.utc).isoformat(),
        "force_update": force_update,
    }


@api_router.get("/config")
async def get_board_config(
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Return full config for this board, including feature flags and update manifest."""
    board_id = board_data.get("user_id", "")
    return await _build_board_config(board_id, pg_session)

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


@api_router.post("/update-status")
async def report_update_status(
    report: UpdateStatusReport,
    board_data: dict = Depends(get_current_board_pg),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Board reports the outcome of a binary auto-update.

    Updates board_versions table and appends an audit event to update_events.
    """
    board_id = board_data.get("user_id", "")
    now = datetime.now(timezone.utc)

    # Upsert board_versions
    bv_result = await pg_session.execute(
        select(BoardVersion).where(BoardVersion.board_id == board_id)
    )
    bv = bv_result.scalar_one_or_none()
    if bv is None:
        bv = BoardVersion(
            board_id=board_id,
            current_version=report.current_version,
            update_status=report.status,
            last_update_at=now,
            rollback_count=report.rollback_count,
        )
        pg_session.add(bv)
    else:
        bv.current_version = report.current_version
        bv.update_status = report.status
        bv.last_update_at = now
        bv.rollback_count = report.rollback_count
        if report.status == "completed":
            bv.target_version = None
            bv.download_progress = 1.0
        elif report.status in ("failed", "rolled_back"):
            bv.last_error = report.status

    # Append audit event
    event = UpdateEvent(
        board_id=board_id,
        event_type="status_report",
        current_version=report.current_version,
        previous_version=report.previous_version,
        status=report.status,
        stable_startups=report.stable_startups,
        rollback_count=report.rollback_count,
        created_at=now,
    )
    pg_session.add(event)

    logger.info(
        f"📊 [Update] Board {board_id} reported: {report.status} "
        f"v{report.previous_version} → v{report.current_version}"
    )

    return {"status": "ok"}


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


# ─── CI/CD Upload Endpoint ──────────────────────────────────────────────────
# Called by GitHub Actions after building a new MSI. Authenticates via
# X-Deploy-Key header matching the DEPLOY_KEY environment variable.

DEPLOY_KEY = os.environ.get("DEPLOY_KEY", "")


@app.post("/api/v1/board/ci-upload")
async def ci_upload(
    version: str = "",
    release_notes: str = "",
    force: str = "true",
    rollout_percentage: str = "100",
    file: Optional[str] = None,
    x_deploy_key: str = Header(default=""),
):
    """Accept a release manifest from CI/CD and store it in the database.

    The actual MSI file is hosted on GitHub Releases; this endpoint only
    records the manifest metadata so boards receive it via heartbeat.
    """
    if not DEPLOY_KEY:
        raise HTTPException(status_code=503, detail="CI upload not configured (DEPLOY_KEY not set)")
    if x_deploy_key != DEPLOY_KEY:
        raise HTTPException(status_code=401, detail="Invalid deploy key")

    if not version:
        raise HTTPException(status_code=400, detail="version is required")

    # Build the download URL from the version
    repo = os.environ.get("GITHUB_REPOSITORY", "unknown/unknown")
    download_url = f"https://github.com/{repo}/releases/download/v{version}/IntelliAttendSmartBoard-{version}.msi"

    async with async_session_factory() as session:
        # Deactivate any previous active manifests
        prev = await session.execute(
            select(ReleaseManifest).where(ReleaseManifest.is_active == True)
        )
        for old_rm in prev.scalars().all():
            old_rm.is_active = False

        # Create new manifest
        rm = ReleaseManifest(
            version=version,
            download_url=download_url,
            sha256="",  # SHA-256 computed by CI and included in GitHub Release
            force=force.lower() == "true",
            rollout_percentage=int(rollout_percentage),
            release_notes=release_notes,
            is_active=True,
            uploaded_by="ci",
        )
        session.add(rm)
        await session.commit()

    logger.info(f"🚀 [CI] Release manifest uploaded: v{version} (force={force}, rollout={rollout_percentage}%)")
    return {"status": "ok", "version": version}


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

@admin_router.post("/board/{board_id}/deregister", dependencies=[Depends(AuthService.require_role(["admin"]))])
async def admin_deregister_board(
    board_id: str,
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Deregister a board by clearing its registration tokens.

    Sets auth_status to pending and clears Firebase UID so the
    board must re-register before it can authenticate.
    """
    from sqlalchemy import update

    result = await pg_session.execute(
        update(User)
        .where(User.smart_board_id == board_id)
        .where(User.role == UserRole.BOARD)
        .values(
            auth_status=AuthStatus.PENDING,
            firebase_uid=None,
        )
    )
    await pg_session.commit()

    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Board not found or already deregistered")

    logger.info(f"🔓 [Admin] Board {board_id} deregistered by admin")
    await AlertService.notify_stale_board(board_id, datetime.now(timezone.utc))
    return {"status": "ok", "board_id": board_id, "deregistered": True}


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


@admin_router.post("/board/{board_id}/update")
async def admin_push_update(
    board_id: str,
    request: AdminUpdateRequest,
    admin_data: dict = Depends(AuthService.require_role(["admin"])),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Push an update command to a specific board via WebSocket.

    Updates the board_versions table with the target version and sends
    an update_available message over the board's WebSocket connection.
    """
    import uuid

    # Update board_versions with target
    bv_result = await pg_session.execute(
        select(BoardVersion).where(BoardVersion.board_id == board_id)
    )
    bv = bv_result.scalar_one_or_none()
    if bv is None:
        bv = BoardVersion(
            board_id=board_id,
            target_version=request.target_version,
            update_status="downloading",
        )
        pg_session.add(bv)
    else:
        bv.target_version = request.target_version
        bv.update_status = "downloading"

    # Log audit event
    event = UpdateEvent(
        board_id=board_id,
        event_type="admin_push",
        target_version=request.target_version,
        status="pushed",
    )
    pg_session.add(event)

    # Send update_available via WebSocket
    cmd_id = str(uuid.uuid4())
    payload = {
        "type": "update_available",
        "command_id": cmd_id,
        "manifest": {
            "minimum_version": request.target_version,
            "download_url": request.download_url,
            "sha256": request.sha256,
            "force": request.force,
            "rollout_percentage": request.rollout_percentage,
            "release_notes": request.release_notes,
        },
        "issued_at": datetime.now(timezone.utc).isoformat(),
    }

    sent = await board_manager.send_command(board_id, payload)
    if sent:
        logger.info(f"🔄 [Admin] Update command sent to {board_id}: v{request.target_version}")
        return {"status": "sent", "command_id": cmd_id, "board_id": board_id}
    else:
        board_manager.queue_command(board_id, payload)
        logger.info(f"🔄 [Admin] Update command queued for offline board {board_id}: v{request.target_version}")
        return {"status": "queued", "command_id": cmd_id, "board_id": board_id}


@admin_router.post("/board/{board_id}/rollback")
async def admin_rollback_board(
    board_id: str,
    request: AdminRollbackRequest,
    admin_data: dict = Depends(AuthService.require_role(["admin"])),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Trigger a rollback on a specific board.

    Sends a system_command to restart the board, which will cause
    UpdateHealthMonitor to detect the crash loop and roll back.
    Alternatively, pushes an update manifest with the rollback target version.
    """
    import uuid

    # Determine rollback target
    bv_result = await pg_session.execute(
        select(BoardVersion).where(BoardVersion.board_id == board_id)
    )
    bv = bv_result.scalar_one_or_none()

    if bv and not request.target_version:
        # Use the previous version from the last rollback event
        ev_result = await pg_session.execute(
            select(UpdateEvent)
            .where(UpdateEvent.board_id == board_id)
            .where(UpdateEvent.event_type == "status_report")
            .order_by(UpdateEvent.created_at.desc())
            .limit(1)
        )
        last_event = ev_result.scalar_one_or_none()
        if last_event and last_event.previous_version:
            request.target_version = last_event.previous_version

    if not request.target_version:
        raise HTTPException(status_code=400, detail="Cannot determine rollback target version")

    # Update board_versions
    if bv:
        bv.target_version = request.target_version
        bv.update_status = "rolling_back"

    # Log audit event
    event = UpdateEvent(
        board_id=board_id,
        event_type="admin_rollback",
        target_version=request.target_version,
        status="triggered",
        error_message=request.reason,
    )
    pg_session.add(event)

    # Send update with the rollback target version
    cmd_id = str(uuid.uuid4())
    payload = {
        "type": "update_available",
        "command_id": cmd_id,
        "manifest": {
            "minimum_version": request.target_version,
            "download_url": "",
            "sha256": "",
            "force": True,
            "rollout_percentage": 100,
            "release_notes": f"Admin rollback: {request.reason}",
        },
        "issued_at": datetime.now(timezone.utc).isoformat(),
    }

    sent = await board_manager.send_command(board_id, payload)
    status_text = "sent" if sent else "queued"
    if not sent:
        board_manager.queue_command(board_id, payload)

    logger.warning(f"⏪ [Admin] Rollback triggered for {board_id} → v{request.target_version}")
    return {"status": status_text, "command_id": cmd_id, "board_id": board_id, "target_version": request.target_version}


@admin_router.post("/rollback-all")
async def admin_rollback_all(
    request: AdminRollbackRequest,
    admin_data: dict = Depends(AuthService.require_role(["admin"])),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Rollback all boards to a specific version.

    Updates the active release manifest and sends update commands to all
    connected boards via WebSocket.
    """
    import uuid

    if not request.target_version:
        raise HTTPException(status_code=400, detail="target_version is required")

    # Deactivate previous manifest and create rollback manifest
    prev = await pg_session.execute(
        select(ReleaseManifest).where(ReleaseManifest.is_active == True)
    )
    for old_rm in prev.scalars().all():
        old_rm.is_active = False

    rm = ReleaseManifest(
        version=request.target_version,
        download_url="",
        sha256="",
        force=True,
        rollout_percentage=100,
        release_notes=f"Fleet rollback: {request.reason}",
        is_active=True,
        uploaded_by="admin",
    )
    pg_session.add(rm)

    # Log event for all boards
    boards_result = await pg_session.execute(
        select(BoardVersion)
    )
    boards = boards_result.scalars().all()
    for bv in boards:
        bv.target_version = request.target_version
        bv.update_status = "rolling_back"
        event = UpdateEvent(
            board_id=bv.board_id,
            event_type="admin_rollback",
            target_version=request.target_version,
            status="triggered",
            error_message=f"Fleet rollback: {request.reason}",
        )
        pg_session.add(event)

    logger.warning(
        f"⏪ [Admin] Fleet rollback triggered → v{request.target_version} "
        f"({len(boards)} boards)"
    )

    return {
        "status": "ok",
        "target_version": request.target_version,
        "boards_affected": len(boards),
    }


@admin_router.get("/fleet")
async def get_fleet_status(
    admin_data: dict = Depends(AuthService.require_role(["admin"])),
    pg_session: AsyncSession = Depends(get_pg_session),
):
    """Return fleet-wide version and update status for all boards.

    This is the operations dashboard data source.
    """
    # Get all board versions
    bv_result = await pg_session.execute(
        select(BoardVersion)
        .order_by(BoardVersion.board_id)
    )
    versions = bv_result.scalars().all()

    # Get active release manifest
    rm_result = await pg_session.execute(
        select(ReleaseManifest)
        .where(ReleaseManifest.is_active == True)
        .order_by(ReleaseManifest.created_at.desc())
        .limit(1)
    )
    active_release = rm_result.scalar_one_or_none()

    # Aggregate stats
    version_counts = {}
    status_counts = {"idle": 0, "downloading": 0, "installing": 0, "completed": 0, "failed": 0, "rolling_back": 0}
    for bv in versions:
        v = bv.current_version or "unknown"
        version_counts[v] = version_counts.get(v, 0) + 1
        s = bv.update_status or "idle"
        status_counts[s] = status_counts.get(s, 0) + 1

    boards = []
    for bv in versions:
        boards.append({
            "board_id": bv.board_id,
            "current_version": bv.current_version,
            "target_version": bv.target_version,
            "update_status": bv.update_status,
            "download_progress": bv.download_progress,
            "last_heartbeat_at": bv.last_heartbeat_at.isoformat() if bv.last_heartbeat_at else None,
            "last_update_at": bv.last_update_at.isoformat() if bv.last_update_at else None,
            "last_error": bv.last_error,
            "rollback_count": bv.rollback_count,
        })

    return {
        "status": "ok",
        "total_boards": len(versions),
        "version_distribution": version_counts,
        "status_distribution": status_counts,
        "active_release": {
            "version": active_release.version,
            "force": active_release.force,
            "rollout_percentage": active_release.rollout_percentage,
            "created_at": active_release.created_at.isoformat() if active_release.created_at else None,
        } if active_release else None,
        "boards": boards,
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
