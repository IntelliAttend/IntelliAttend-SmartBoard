"""
IntelliAttend Mock Backend Server for Integration Testing
=========================================================
A lightweight FastAPI server that mimics the real backend.
No Firebase dependency — uses in-memory storage.
Run: python scripts/mock_server.py
"""

import asyncio
import base64
import hashlib
import hmac
import json
import os
import secrets
import sys
import time
import uuid
from datetime import datetime, timezone
from typing import Optional

import uvicorn
from fastapi import FastAPI, HTTPException, Request, Response, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ──────────────────────────────────────────────
# Data Models (mirrors backend/models/board_auth_schema.py)
# ──────────────────────────────────────────────

class TelemetryPayload(BaseModel):
    wifi_signal_dbm: int
    storage_gb: float
    app_version: str
    timestamp_ms: Optional[int] = None

class SessionInitiateRequest(BaseModel):
    otp: str = Field(..., min_length=6, max_length=6)

class SessionCreateRequest(BaseModel):
    course_name: str
    faculty_name: str
    section_id: str = ""
    roster_count: int = 0
    slot_id: Optional[str] = None

class HeartbeatRequest(BaseModel):
    screen_state: str = "unknown"
    uptime_seconds: int = 0
    app_version: str = "unknown"
    timestamp_ms: int = 0

class DeviceRegisterInitiateRequest(BaseModel):
    smart_board_id: str
    password: str

class DeviceRegisterVerifyRequest(BaseModel):
    smart_board_id: str
    otp: str

class DeviceRegisterCompleteRequest(BaseModel):
    smart_board_id: str
    verification_token: str
    hardware_id: str

# ──────────────────────────────────────────────
# In-Memory Store
# ──────────────────────────────────────────────

class MockStore:
    def __init__(self):
        self.boards: dict = {}          # board_id -> board info
        self.sessions: dict = {}        # session_id -> session info
        self.active_sessions: dict = {} # session_id -> active session
        self.tokens: dict = {}          # board_id -> token info
        self.otps: dict = {}            # board_id -> otp
        self.heartbeats: dict = {}      # board_id -> last heartbeat
        self.registration_tokens: dict = {}  # board_id -> verification token
        self.clock_skew: int = 0

    def generate_jwt(self, board_id: str, expiry_s: int = 900) -> str:
        header = base64.urlsafe_b64encode(json.dumps({"alg": "HS256", "typ": "JWT"}).encode()).rstrip(b"=").decode()
        payload = base64.urlsafe_b64encode(json.dumps({
            "sub": board_id,
            "iat": int(time.time()),
            "exp": int(time.time()) + expiry_s,
            "jti": str(uuid.uuid4())
        }).encode()).rstrip(b"=").decode()
        sig = hmac.new(b"mock-secret", f"{header}.{payload}".encode(), hashlib.sha256).hexdigest()
        return f"{header}.{payload}.{sig}"

    def seed_defaults(self):
        """Pre-populate with test data on startup."""
        board_id = "IASB-4208"
        self.boards[board_id] = {
            "device_id": board_id,
            "classroom_id": "room_4208",
            "room_name": "Room 4208",
            "building": "Main Building",
            "department": "Computer Science",
            "capacity": 60,
            "is_registered": True,
            "firmware_version": "v5.4"
        }
        self.tokens[board_id] = {
            "api_key": "bk_live_mock_test_key_12345",
            "access_token": self.generate_jwt(board_id),
            "refresh_token": f"rt_{secrets.token_hex(16)}"
        }
        self.otps[board_id] = {"otp": "123456", "expires_at": time.time() + 300}


store = MockStore()

# ──────────────────────────────────────────────
# App Factory
# ──────────────────────────────────────────────

app = FastAPI(title="IntelliAttend Mock Backend (Testing Only)")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    store.seed_defaults()
    print("✓ Mock store seeded with defaults")

# ──────────────────────────────────────────────
# Middleware: Correlation ID
# ──────────────────────────────────────────────

@app.middleware("http")
async def add_correlation_id(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    response: Response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Mock-Server"] = "true"
    return response

# ──────────────────────────────────────────────
# Dependency: Board Authentication
# ──────────────────────────────────────────────

async def get_board_data(request: Request):
    """Extract board identity from headers (like real backend)."""
    device_id = request.headers.get("X-Device-ID", "IASB-4208")
    auth = request.headers.get("Authorization", "")
    api_key = request.headers.get("X-API-Key", "")

    board = store.boards.get(device_id)
    if not board:
        board = store.boards.get("IASB-4208")

    return {
        "device_id": device_id,
        "room_id": board.get("classroom_id", "room_4208") if board else "room_4208",
        "is_authenticated": bool(auth or api_key)
    }

# ──────────────────────────────────────────────
# API Routes
# ──────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "mode": "mock", "uptime_s": int(time.time())}

@app.get("/api/v1/board/time")
async def get_server_time():
    return {
        "status": "success",
        "server_timestamp_ms": int(time.time() * 1000)
    }

@app.get("/api/v1/board/ready")
async def board_ready():
    return {
        "status": "ready",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/board/preflight")
async def get_preflight(
    slot_id: str,
    x_retry_attempt: Optional[int] = Header(None, alias="X-Retry-Attempt"),
    board_data: dict = None
):
    board_data = await get_board_data(None)
    return {
        "status": "ready",
        "server_timestamp": int(time.time() * 1000),
        "pre_allocated_session_id": f"sess_{slot_id}",
        "session_secret_half1": base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip("="),
        "slot_verification": {
            "subject_name": "Mock Subject",
            "faculty_name": "Mock Professor"
        }
    }

@app.post("/api/v1/board/session/initiate")
async def initiate_session(request: SessionInitiateRequest, board_data: dict = None):
    board_data = await get_board_data(None)
    session_id = f"sess_{secrets.token_hex(8)}"
    session_secret = secrets.token_hex(16)

    store.sessions[session_id] = {
        "session_id": session_id,
        "session_secret": session_secret,
        "status": "active"
    }

    return {
        "status": "success",
        "data": {
            "session_id": session_id,
            "session_secret": session_secret,
            "faculty_name": "Mock Professor",
            "course_name": "Mock Course",
            "roster_count": 60
        }
    }

@app.post("/api/v1/board/session/attendance/record-live")
async def record_attendance():
    return {"status": "success"}

@app.post("/api/v1/board/session/terminate")
async def terminate_session():
    return {"status": "success"}

@app.post("/api/v1/device/heartbeat")
async def board_heartbeat(request: HeartbeatRequest, board_data: dict = None):
    board_data = await get_board_data(None)
    device_id = board_data.get("device_id", "IASB-4208")
    store.heartbeats[device_id] = {
        "last_seen": time.time(),
        "screen_state": request.screen_state,
        "uptime_seconds": request.uptime_seconds
    }
    return {"status": "ok", "device_id": device_id}

@app.post("/api/v1/board/telemetry")
async def receive_telemetry(payload: TelemetryPayload, board_data: dict = None):
    return {"status": "success"}

@app.get("/api/v1/board/sync-context")
async def sync_context(board_data: dict = None):
    board_data = await get_board_data(None)
    return {"status": "success", "data": board_data}

# ──────────────────────────────────────────────
# Registration Routes
# ──────────────────────────────────────────────

@app.post("/api/v1/device/register/login")
async def initiate_device_registration(request: DeviceRegisterInitiateRequest):
    board_id = request.smart_board_id
    store.otps[board_id] = {"otp": "123456", "expires_at": time.time() + 300}
    return {
        "status": "success",
        "message": "OTP sent",
        "data": {"otp": "123456"}
    }

@app.post("/api/v1/device/register/verify")
async def verify_device_registration(request: DeviceRegisterVerifyRequest):
    board_id = request.smart_board_id
    otp_data = store.otps.get(board_id)

    if not otp_data or otp_data["otp"] != request.otp:
        raise HTTPException(status_code=400, detail="Invalid OTP")

    verification_token = secrets.token_hex(16)
    store.registration_tokens[board_id] = verification_token

    return {
        "status": "success",
        "data": {
            "verification_token": verification_token
        }
    }

@app.post("/api/v1/device/register/complete")
async def complete_device_registration(request: DeviceRegisterCompleteRequest):
    board_id = request.smart_board_id
    stored_token = store.registration_tokens.get(board_id)

    if not stored_token or stored_token != request.verification_token:
        raise HTTPException(status_code=400, detail="Invalid verification token")

    tokens = {
        "api_key": f"bk_live_mock_{secrets.token_hex(16)}",
        "access_token": store.generate_jwt(board_id),
        "refresh_token": f"rt_{secrets.token_hex(16)}",
        "expires_in_ms": 900000,
        "token_type": "Bearer"
    }
    store.tokens[board_id] = tokens

    store.boards[board_id] = {
        "device_id": board_id,
        "classroom_id": "room_4208",
        "room_name": f"Room {board_id.split('-')[1]}",
        "building": "Main Building",
        "department": "Computer Science",
        "capacity": 60,
        "is_registered": True,
        "hardware_id": request.hardware_id,
        "firmware_version": "v5.4"
    }

    return {"status": "success", "data": tokens}

@app.post("/api/v1/board/auth/refresh")
async def refresh_token(request: Request):
    body = await request.json()
    refresh_token = body.get("refresh_token", "")

    if not refresh_token.startswith("rt_"):
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    return {
        "access_token": store.generate_jwt("IASB-4208"),
        "expires_in_ms": 900000
    }

@app.post("/v1/board/session/create")
async def create_session_endpoint(request: SessionCreateRequest):
    session_id = f"sess_{secrets.token_hex(8)}"
    otp = "123456"
    return {
        "status": "success",
        "session_id": session_id,
        "data": {
            "session_id": session_id,
            "otp": otp
        }
    }

# ──────────────────────────────────────────────
# Store Inspection Endpoints (for test teardown)
# ──────────────────────────────────────────────

@app.get("/__mock/state")
async def mock_state():
    return {
        "boards": list(store.boards.keys()),
        "sessions": list(store.sessions.keys()),
        "heartbeats": list(store.heartbeats.keys())
    }

@app.post("/__mock/reset")
async def mock_reset():
    store.__init__()
    store.seed_defaults()
    return {"status": "reset"}

# ──────────────────────────────────────────────
# Entrypoint
# ──────────────────────────────────────────────

if __name__ == "__main__":
    port = int(os.environ.get("MOCK_PORT", "8080"))
    print(f"╔══════════════════════════════════════════════════╗")
    print(f"║  IntelliAttend Mock Backend                      ║")
    print(f"║                                                  ║")
    print(f"║  URL:   http://127.0.0.1:{port}                       ║")
    print(f"║  Board: IASB-4208 / OTP: 123456                  ║")
    print(f"║                                                  ║")
    print(f"║  Endpoints:                                      ║")
    print(f"║    GET  /health                                  ║")
    print(f"║    POST /api/v1/device/register/login            ║")
    print(f"║    POST /api/v1/device/register/verify           ║")
    print(f"║    POST /api/v1/device/register/complete         ║")
    print(f"║    POST /api/v1/device/heartbeat                 ║")
    print(f"║    GET  /api/v1/board/time                       ║")
    print(f"║    GET  /api/v1/board/ready                      ║")
    print(f"║    GET  /api/v1/board/preflight                  ║")
    print(f"║    POST /api/v1/board/session/initiate           ║")
    print(f"║    POST /api/v1/board/auth/refresh               ║")
    print(f"║    POST /__mock/reset                            ║")
    print(f"║    GET  /__mock/state                            ║")
    print(f"╚══════════════════════════════════════════════════╝")
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info")
