# SmartBoard ↔ Server API Alignment

## Issue: 404 Not Found on V2 Endpoints

Both `GET /api/v1/board/ready` and `POST /api/v1/board/heartbeat` return **404 Not Found** from the remote server (`api-dev.balaseetharamanjaneyulu.com`). The board proceeds in degraded mode (no server sync), and the heartbeat silently fails.

## Root Cause

The SmartBoard Flutter client (V2 API contract) calls these endpoints:

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/v1/board/ready` | Boot canary — confirms board is registered |
| `POST` | `/api/v1/board/heartbeat` | Alive signal + session context (every 5 min) |
| `POST` | `/api/v1/board/session/initiate` | OTP-based session ignition |
| `POST` | `/api/v1/board/telemetry` | Hardware health push |
| `POST` | `/api/v1/board/sync/vault` | Offline attendance vault flush |
| `POST` | `/api/v1/board/session/terminate` | End active session |
| `POST` | `/api/v1/board/deregister` | Unlink hardware + revoke tokens |
| `GET` | `/api/v1/board/preflight` | Slot pre-allocation |
| `GET` | `/api/v1/board/time` | NTP-style time sync |
| `POST` | `/api/v1/websocket/ticket` | WebSocket auth ticket |
| `POST` | `/api/v1/device/register/login` | Registration phase 1 (OTP send) |
| `POST` | `/api/v1/device/register/verify` | Registration phase 2 (OTP verify) |
| `POST` | `/api/v1/device/register/complete` | Registration phase 3 (hardware bind) |
| `POST` | `/api/v1/device/register/token/refresh` | JWT rotation |
| `POST` | `/api/v1/device/register/deregister` | Deregistration |

The server must have **all** V2 endpoints deployed. Missing endpoints produce `404 {"detail":"Not Found"}` which the Flutter client handles gracefully but results in a degraded board.

## Deployment: Python Backend

The V2 endpoints live in `backend/python/main.py`:

```
D:\Dev\IntelliAttend-SmartBoard\backend\python\main.py
```

To deploy, copy `backend/python/` to the server and run:

```bash
cd backend/python
pip install -r requirements.txt
python main.py
```

The server listens on `127.0.0.1:8000` by default. Use a process manager (systemd, Supervisor, PM2) for production.

### Key routes in `main.py`

| Line | Route | Module |
|------|-------|--------|
| 209 | `POST /api/v1/board/heartbeat` | `board_heartbeat_v2` |
| 246 | `POST /api/v1/board/verify-otp` | `verify_otp_v2` |
| 322 | `POST /v1/board/session/initiate` | `initiate_session_legacy` |
| 332 | `GET /api/v1/board/time` | `api_router` |
| 339 | `GET /api/v1/board/ready` | `api_router` |
| 345 | `GET /api/v1/board/preflight` | `api_router` |
| 414 | `POST /api/v1/board/telemetry` | `api_router` |
| 422 | `GET /api/v1/board/sync-context` | `api_router` |
| 426 | `POST /api/v1/board/session/initiate` | `api_router` |
| 430 | `POST /api/v1/board/session/terminate` | `api_router` |
| 454 | `POST /api/v1/board/session/attendance/record-live` | `api_router` |
| 481 | `POST /api/v1/board/sync/vault` | `api_router` |

## Verification

After deployment, verify from the board:

```bash
# Ready check
curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Device-ID: test-device" \
  -H "Authorization: Bearer <token>" \
  https://api-dev.balaseetharamanjaneyulu.com/api/v1/board/ready

# Should return 200
```

Or check the Flutter debug logs for:
```
💡 [Boot] Server-side registration confirmed for <BOARD_ID>.
```

## Local Testing (No Server)

Run both backend and Flutter app locally:

1. Start Python backend:
```bash
cd backend/python
python main.py
# Listening on http://127.0.0.1:8000
```

2. Update `.env`:
```env
API_BASE_URL=http://127.0.0.1:8000
```

3. Run Flutter app in debug mode:
```bash
flutter run -d windows
```

## Error Handling Behavior

| Status | Endpoint | Flutter Handling |
|--------|----------|-----------------|
| `404` | `/api/v1/board/ready` | Logs warning, **proceeds to IdleScreen** (degraded) |
| `404` | `/api/v1/board/heartbeat` | Logs warning, returns `{status: error}` — caller handles gracefully |
| `401` | `/api/v1/board/heartbeat` | Clears registration, redirects to RegistrationScreen |
| `403` | `/api/v1/board/ready` | Blocks transition, shows "BOARD NOT REGISTERED" |
