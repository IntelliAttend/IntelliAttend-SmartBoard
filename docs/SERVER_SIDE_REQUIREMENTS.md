# IntelliAttend SmartBoard — Server-Side Requirements

This document outlines the changes and contracts the **backend team** must implement for the SmartBoard Flutter app to function correctly. The app is a Flutter Windows kiosk that communicates with a Python FastAPI backend.

---

## 1. Required Backend Changes

### 1.1 Mount the Device Registration Router

**Status:** ❌ Missing

The `app/api/v1/device.py` router (which contains `POST /api/v1/device/register/login`, `/verify`, and `/complete`) is **not imported/mounted** in `main.py`.

**Action:**

```python
# In main.py
from app.api.v1 import device
app.include_router(device.router, prefix="/api/v1/device")
```

**Why:** Without this, all registration API calls return **404 Not Found**.

---

### 1.2 Reset Board Registration Flag

**Status:** ❌ Wrong value

The Firestore document `smart_boards/IASB-4208` has `is_registered: true`. This causes the server to skip the OTP registration flow, but the app has no local Isar data yet — creating a deadlock.

**Action:** Set `is_registered: false` on the board document so the OTP flow triggers on first boot.

---

## 2. API Endpoint Contracts

### 2.1 Initiate Registration

**Endpoint:** `POST /api/v1/device/register/login`

**Request:**
```json
{
  "smart_board_id": "IASB-4208",
  "password": "1234567890"
}
```
Headers: `Authorization: Bearer <Firebase ID Token>`

**Expected Response (200):**
```json
{
  "is_registered": false,
  "otp_required": true,
  "message": "OTP sent to admin email"
}
```

The app checks for either `is_registered` or `status` field.

---

### 2.2 Verify OTP

**Endpoint:** `POST /api/v1/device/register/verify`

**Request:**
```json
{
  "smart_board_id": "IASB-4208",
  "otp": "123456"
}
```
No auth header required (OTP is self-validating).

**Expected Response (200):**
```json
{
  "verification_token": "<15-minute-expiry JWT>",
  "message": "OTP verified"
}
```

---

### 2.3 Complete Registration

**Endpoint:** `POST /api/v1/device/register/complete`

**Request:**
```json
{
  "smart_board_id": "IASB-4208",
  "hardware_id": "<sha256-hash-of-hardware-fingerprint>",
  "verification_token": "<token-from-verify-step>",
  "metadata": {
    "brand": "Dell",
    "model": "OptiPlex 7080",
    "os_name": "Windows",
    "os_version": "10.0.26200",
    "processor": "Intel64 Family 6 Model 165",
    "total_physical_memory_mb": 16384,
    "system_firmware": "UEFI",
    "motherboard_serial": "CN1234567890",
    "cpu_id": "BFEBFBFF000906ED",
    "mac_address": "AA:BB:CC:DD:EE:FF"
  }
}
```
Headers: `Authorization: Bearer <Firebase ID Token>`

**Expected Response (200):**
```json
{
  "board_id": "IASB-4208",
  "hardware_id": "<sha256-hash>",
  "classroom_id": "<uuid>",
  "room_name": "Room 204",
  "building": "Block B",
  "department": "Computer Science",
  "capacity": 60,
  "custom_token": "<Firebase Custom Token for hardware-bound session>",
  "is_registered": true
}
```

**Critical:** The `custom_token` field is **required**. The app exchanges it via Firebase Identity Toolkit `signInWithCustomToken` to bind the session to the registered hardware. Without it, the board cannot authenticate after registration.

---

### 2.4 Board Hydrate

**Endpoint:** `GET /api/v1/board/hydrate`

**Headers:** `Authorization: Bearer <Firebase ID Token>`, `X-Device-ID: <hardware-id>`

**Expected Response (200):**
```json
{
  "manifest_hash": "sha256-of-entire-payload",
  "profile": {
    "board_id": "IASB-4208",
    "board_name": "Room 204 Board",
    "room_id": "room-uuid",
    "room_number": "204",
    "building": "Block B",
    "floor": "2nd",
    "institution_id": "inst-uuid",
    "institution_name": "University College",
    "is_registered": true
  },
  "schedule_list": [
    {
      "slot_id": "uuid",
      "day_of_week": 1,
      "start_time": "09:00",
      "end_time": "10:00",
      "subject_name": "Machine Learning",
      "faculty_name": "Dr. Sharma",
      "faculty_emails": ["sharma@college.edu"],
      "section_id": "sec-uuid",
      "section_name": "CSE-AIML-A",
      "course_code": "CS305",
      "room_number": "204",
      "slot_type": "regular",
      "class_type": "Lecture"
    }
  ],
  "rosters": {
    "sectionId_courseCode": [
      {
        "student_id": "user-uuid",
        "name": "John Doe",
        "roll_number": "2021CS001"
      }
    ]
  }
}
```

**Notes:**
- `manifest_hash` enables the app to skip re-downloading unchanged data (hash comparison with local cache)
- Schedule is the weekly timetable; rosters are per section+course combination

---

### 2.5 Heartbeat V2

**Endpoint:** `POST /api/v1/board/heartbeat`

**Headers:** `Authorization: Bearer <Firebase ID Token>`, `X-Device-ID: <hardware-id>`

**Request:**
```json
{
  "boardId": "IASB-4208",
  "screenState": "idle",
  "uptimeSeconds": 12345,
  "appVersion": "5.4.0+1",
  "timestamp": "2026-06-28T17:06:39.000Z"
}
```

**Expected Response (200):**
```json
{
  "status": "ok",
  "server_time": "2026-06-28T17:06:39.500Z",
  "session": {
    "session_id": "uuid-or-null",
    "status": "active"
  }
}
```

**Notes:**
- `session` can be `null` when no active session exists (the app handles this)
- Heartbeat is sent every 15 seconds when WebSocket is disconnected; skipped when WS is connected
- The app also uses this route for time sync data

---

### 2.6 Time Sync

**Endpoint:** `POST /api/v1/board/time`

**Request:**
```json
{
  "client_timestamp_ms": 1715112345678
}
```

**Expected Response (200):**
```json
{
  "server_timestamp_ms": 1715112346123,
  "server_received_at_ms": 1715112346122,
  "client_timestamp_ms": 1715112345678,
  "processing_duration_ms": 1,
  "realm": "UTC"
}
```

---

### 2.7 Session State

**Endpoint:** `GET /api/v1/session/current-state`

**Headers:** `Authorization: Bearer <Firebase ID Token>`

**Expected Response (200):**
```json
{
  "session_id": "uuid",
  "state": "IDLE",
  "version": 5,
  "present": 23,
  "absent": 5,
  "total_students": 60,
  "course_name": "Machine Learning",
  "faculty_name": "Dr. Sharma",
  "section_id": "sec-123",
  "session_secret_half1": "base64-encoded-16-bytes",
  "websocket_token": "..."
}
```

**States:** `IDLE` | `PREPARING` | `IGNITING` | `ACTIVE` | `CLOSED`

---

### 2.8 WebSocket Ticket

**Endpoint:** `POST /api/v1/websocket/ticket`

**Headers:** `Authorization: Bearer <Firebase ID Token>`

**Expected Response (200):**
```json
{
  "ticket": "<10-second-expiry-token>"
}
```

---

### 2.9 WebSocket Endpoints

**Board Connection:** `WS /api/v1/websocket/board/{board_id}?ticket=<ticket>`

**Session Connection:** `WS /api/v1/websocket/session/{session_id}?ticket=<ticket>`

**Server → Client Messages:**
| Type | Description |
|------|-------------|
| `board_connected` | Board connected; triggers session discovery |
| `session_preparing` | Faculty initiated session |
| `session_igniting` | Session about to open |
| `attendance_open` | Attendance window open (contains `session_secret_half1`) |
| `full_state_sync` | Full roster + present list |
| `ATTENDANCE_MARKED` | Student marked present |
| `attendance_updated` | Updated counts |
| `student_verified` | Seat verification complete |
| `attendance_closed` | Window closed |
| `session_ended` | Session finished |
| `notification` | Alert/notification with `priority`, `display_mode`, `title`, `body` |
| `system_command` | Shutdown/restart command |
| `pong` | Heartbeat response |

**Client → Server Messages:**
| Type | Description |
|------|-------------|
| `ping` | Keep-alive (every 30s) |
| `join_session` | Request to join active session |
| `system_command_ack` | Acknowledge system command |

---

### 2.10 Preflight Warm-Up

**Endpoint:** `GET /api/v1/board/preflight`

**Query params:** `?slot_id=<slot-uuid>`

**Headers:** `Authorization: Bearer <Firebase ID Token>`

**Expected Response (200):**
```json
{
  "status": "armed",
  "session_id": "pre-allocated-session-id",
  "server_timestamp_ms": 1715112345678
}
```

---

## 3. Authentication Flow

The app uses **Firebase Auth via REST API** only (no Firebase plugin due to Windows threading bugs):

1. **Initial Registration:**
   - `signInWithPassword(email, password)` → Firebase ID Token
   - `POST /api/v1/device/register/login` → OTP sent to admin
   - User enters OTP
   - `POST /api/v1/device/register/verify` → `verification_token`
   - Hardware fingerprint collected (motherboard serial + CPU ID + MAC)
   - `POST /api/v1/device/register/complete` → `custom_token`
   - `signInWithCustomToken(custom_token)` → Firebase session bound to hardware

2. **Subsequent Boots:**
   - Isar local DB has `DeviceRegistration`
   - `signInWithPassword(email, password)` → Firebase ID Token
   - All API calls carry `Authorization: Bearer <idToken>` + `X-Device-ID`

3. **Token Refresh:**
   - Memory cache checked first (5-min buffer)
   - `POST securetoken.googleapis.com/v1/token?key=<API_KEY>` with `grant_type=refresh_token`
   - Fallback: email/password re-auth

---

## 4. WebSocket Connection Flow

```
1. POST /api/v1/websocket/ticket → get 10s ticket
2. WS /api/v1/websocket/board/{board_id}?ticket=<ticket>
3. Server sends "board_connected"
4. Client sends "join_session" if session exists
5. Real-time attendance events flow over WS
```

- Keep-alive: `ping` every 30s, server responds with `pong`
- Reconnect: exponential backoff (1s, 2s, 4s, 8s, 15s cap)
- When WS is connected, HTTP heartbeat is skipped

---

## 5. Notification Contract

```json
{
  "event_id": "uuid",
  "event_type": "notification",
  "version": 1,
  "institution_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "notification_id": "uuid",
    "version": 1,
    "priority": "P3",
    "notification_type": "info",
    "display_mode": "overlay",
    "title": "Emergency Alert",
    "body": "Building evacuation in progress",
    "duration_seconds": null,
    "requires_acknowledgement": true,
    "data": { "attachment_url": "https://..." }
  }
}
```

**Priorities:** `P1` (emergency, full-screen lock), `P2` (high priority, persistent overlay), `P3` (normal, banner)

**Display modes:** `full_screen` | `overlay` | `reminder` | `default`

---

## 6. Pre-Flight / Session Lifecycle

```
PRE_ALLOCATED [pre-flight warm-up]
       ↓
   ACTIVE [OTP verified by faculty via mobile app]
       ↓
COMPLETED / ENDED
```

- Pre-flight is triggered when a scheduled class slot's start time approaches
- The server pre-allocates a session ID and returns it
- Faculty starts the session from their mobile app
- Server pushes `session_preparing` → `session_igniting` → `attendance_open` over WebSocket

---

## 7. Error Response Format

All errors should follow this structure:
```json
{
  "detail": {
    "code": "BOARD_NOT_FOUND",
    "message": "No board registered with ID: IASB-4208"
  }
}
```

Common error codes:
- `BOARD_NOT_FOUND` — Board ID not recognized
- `ALREADY_REGISTERED` — Board already completed registration
- `INVALID_OTP` — Wrong verification code
- `VERIFICATION_TOKEN_EXPIRED` — 15-min token expired
- `HARDWARE_MISMATCH` — Hardware ID doesn't match registered device
- `SESSION_NOT_FOUND` — No active session for the given slot
- `UNAUTHORIZED` — Missing or invalid Firebase token

---

## 8. Auto-Update: Config Block + Health Reporting

The board polls the heartbeat endpoint every 15 seconds. The server **must** return a `config` block in the heartbeat response to enable remote feature flags and binary auto-updates.

### 8.1 Heartbeat `config` block

The existing `POST /api/v1/board/heartbeat` response should include a `config` object:

```json
{
  "status": "ok",
  "server_time": "2026-06-28T12:00:00Z",
  "session": { ... },
  "config": {
    "config_version": 1,
    "issued_at": "2026-06-28T12:00:00Z",
    "flags": {
      "enable_analytics": false,
      "enable_documents": true,
      "enable_workspace": true,
      "enable_video_background": true,
      "kiosk_mode": "fullscreen",
      "qr_rotation_interval_ms": 5000,
      "debug_buttons_hidden": true
    },
    "ui": {
      "branding": {
        "title": "IntelliAttend SmartBoard"
      },
      "labels": {
        "welcome_text": "Welcome to Smart Class"
      }
    },
    "force_update": {
      "minimum_version": "5.5.0",
      "download_url": "https://github.com/org/repo/releases/download/v5.5.0/IntelliAttendSmartBoard-5.5.0.msi",
      "sha256": "abc123def456...",
      "force": false,
      "rollout_percentage": 100,
      "release_notes": "Fixed QR crash on rapid scan",
      "published_at": "2026-06-28T12:00:00Z"
    }
  }
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `config_version` | int | ✅ | Monotonically increasing. Board ignores configs with version ≤ last applied |
| `flags` | object | ❌ | Arbitrary key/value feature flags. Absent key = enabled by default |
| `ui` | object | ❌ | UI branding and label overrides |
| `force_update` | object | ❌ | Present only when a binary update is available. Null/absent = no update |

**`force_update` fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `minimum_version` | string | ✅ | Semver (e.g. "5.5.0"). Board compares against installed version |
| `download_url` | string | ✅ | Full HTTPS URL to the MSI |
| `sha256` | string | ❌ | SHA-256 hex digest. Board verifies file integrity before installing |
| `force` | bool | ❌ | Default `false`. If `true`, board shows blocking overlay during install |
| `rollout_percentage` | int | ❌ | 0–100. Board uses hash of its ID for canary/staged rollouts |
| `release_notes` | string | ❌ | Markdown-ish plain text |
| `published_at` | string | ❌ | ISO-8601 timestamp |

### 8.2 Update Status Reporting

Boards report update outcomes to `POST /api/v1/board/update-status`:

**Request:**
```json
{
  "current_version": "5.5.0",
  "previous_version": "5.4.0",
  "status": "completed",
  "stable_startups": 3,
  "rollback_count": 0,
  "timestamp": "2026-06-28T12:00:00Z"
}
```

**Status values:**
| Status | Meaning |
|--------|---------|
| `completed` | Board updated successfully and version is stable |
| `failed` | Update download or installation failed |
| `rolled_back` | New version crashed; board auto-reverted to previous version |

**Response:** `200 OK` (board does not retry on failure — fire-and-forget)

### 8.3 Board Health / Version Dashboard

The server should store per-board version history:
- Current version per board
- Update attempt timestamps and outcomes
- Rollback count
- Last stable version

This enables the admin dashboard to show:
- Which boards are on which version
- Which boards failed to update
- Which boards have rolled back
- Overall rollout progress

### 8.4 Admin API (for future dashboard)

The backend should expose an API for the admin dashboard to:
- Set feature flags per institution / per board group
- Trigger a forced update for specific boards
- View rollout progress and version distribution
- View boards that crashed after update and rolled back

**Example:**
```
POST /api/v1/admin/config/flags
  Body: { "institution_id": "...", "flags": { ... } }

POST /api/v1/admin/config/force-update
  Body: { "institution_id": "...", "board_ids": ["..."], "update": { ... } }

GET /api/v1/admin/boards/versions
  Returns: { "boards": [ { "board_id": "...", "version": "...", "status": "..." } ] }
```
