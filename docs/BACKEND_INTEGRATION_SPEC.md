# Backend Integration Specification — SmartBoard ↔ Server

**Status:** FINAL  
**Scope:** Backend team — align all endpoints with this spec  
**Board Version:** 5.8+  
**Auth Model:** Firebase Bearer Token only (no X-Device-ID, no hardware binding)

---

## Table of Contents
1. [Authorization Model](#1-authorization-model)
2. [Firestore Collections](#2-firestore-collections)
3. [Registration Flow](#3-registration-flow)
4. [Board Boot Flow](#4-board-boot-flow)
5. [Session Lifecycle](#5-session-lifecycle)
6. [API Endpoints (Complete Reference)](#6-api-endpoints-complete-reference)
7. [Heartbeat / Telemetry](#7-heartbeat--telemetry)
8. [Error Contract](#8-error-contract)
9. [Implementation Checklist](#9-implementation-checklist)

---

## 1. Authorization Model

**Every** API call from the SmartBoard carries:

```
Authorization: Bearer <Firebase ID Token>
```

There are **no** exceptions. No `X-Device-ID`, no `X-Board-ID`, no hardware fingerprint headers, no custom tokens.

### 1.1 Board Firebase Auth Account

Each SmartBoard has a Firebase Auth account created during registration:

| Field | Example |
|-------|---------|
| Email | `iasb-4208@smartboard.intelliattend.com` |
| Password | Random, stored in OS keychain on the board |
| UID | Firebase auto-generated |

### 1.2 Token Acquisition (Board Side)

```
POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=AIzaSy...
Content-Type: application/json

{
  "email": "iasb-4208@smartboard.intelliattend.com",
  "password": "<stored-password>",
  "returnSecureToken": true
}
```

Response:
```json
{
  "idToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresIn": "3600",
  "refreshToken": "..."
}
```

### 1.3 Token Refresh

```
POST https://securetoken.googleapis.com/v1/token?key=AIzaSy...
Content-Type: application/json

{
  "grant_type": "refresh_token",
  "refreshToken": "<refreshToken from sign-in>"
}
```

Response:
```json
{
  "access_token": "<new-id-token>",
  "expires_in": "3600"
}
```

### 1.4 How Server Resolves Board Identity

The server **must not** rely on any header or body field for board identity. Instead:

1. Extract Firebase UID from the verified Bearer token
2. Look up the board's Firebase Auth account by UID → get the email
3. Query `smart_boards` collection where `email == firebase_email`
4. If found → board is authenticated and registered
5. If not found → return `403 BOARD_NOT_FOUND`

This is the **only** way the board identity is resolved. No device_id, no fingerprint.

---

## 2. Firestore Collections

### 2.1 `smart_boards`

One document per physical board. Created during registration.

```
Document ID: auto-generated (or boardId)

{
  "boardId": "IASB-4208",
  "email": "iasb-4208@smartboard.intelliattend.com",
  "classroomId": "room_4208",
  "registeredAt": <Timestamp>,
  "status": "active"
}
```

### 2.2 `timetable_slots`

One document per class slot. Queried by `classroomId`.

```
Document ID: auto-generated

{
  "classroomId": "room_4208",
  "slotId": "SLOT_CSE-AIML-A_2025_Tuesday_P1",
  "startTime": "18:00",
  "endTime": "19:00",
  "courseName": "IoT and Its Applications",
  "facultyName": "Dr. S. Bala",
  "sectionId": "CSE-AIML-A_2025"
}
```

### 2.3 `active_sessions`

Pre-allocated during pre-flight, activated during OTP initiation.

```
Document ID: sessionId (from pre-flight)

--- Pre-allocated state ---
{
  "sessionId": "33dca24bda7fc8202202",
  "slotId": "SLOT_CSE-AIML-A_2025_Tuesday_P1",
  "smartBoardId": "IASB-4208",
  "status": "pre-allocated",
  "createdAt": <Timestamp>
}

--- After OTP activation ---
{
  "sessionId": "33dca24bda7fc8202202",
  "slotId": "SLOT_CSE-AIML-A_2025_Tuesday_P1",
  "smartBoardId": "IASB-4208",
  "status": "active",
  "sessionSecretHalf1": "a1b2c3d4...",
  "facultyId": "fac03@mrcet.ac.in",
  "courseName": "IoT and Its Applications",
  "sectionId": "CSE-AIML-A_2025",
  "subjectId": "R22A6951",
  "expiresAt": <Timestamp>,
  "ttlSeconds": 7200,
  "createdAt": <Timestamp>
}
```

### 2.4 `attendees`

One document per student scan.

```
Document ID: auto-generated

{
  "sessionId": "33dca24bda7fc8202202",
  "studentId": "STU-001",
  "studentName": "John Doe",
  "entryType": "in",
  "timestamp": <Timestamp>
}
```

---

## 3. Registration Flow

```
FACULTY APP               BACKEND                    FIREBASE AUTH
    │                         │                           │
    │ 1. POST /register       │                           │
    │    { boardId,           │                           │
    │      classroomId }      │                           │
    │────────────────────────►│                           │
    │                         │                           │
    │                         │ 2. Create Firebase Auth   │
    │                         │    account                │
    │                         │    email: iasb-4208@...   │
    │                         │    password: <random>     │
    │                         │──────────────────────────►│
    │                         │    UID returned ◄─────────│
    │                         │                           │
    │                         │ 3. Create smart_boards doc│
    │                         │    { boardId, email,      │
    │                         │      classroomId, status }│
    │                         │                           │
    │    { boardId,           │                           │
    │      email, password,   │                           │
    │      apiKey }           │                           │
    │◄────────────────────────│                           │
```

### Registration Endpoint

```
POST /api/v1/board/register

Headers:
  Authorization: Bearer <faculty-admin-token>
  Content-Type: application/json

Body:
{
  "boardId": "IASB-4208",
  "classroomId": "room_4208"
}

Response 200:
{
  "boardId": "IASB-4208",
  "email": "iasb-4208@smartboard.intelliattend.com",
  "password": "<generated-password>",
  "classroomId": "room_4208"
}
```

### Server-Side Requirements

On registration, the server MUST:
1. Create a Firebase Auth account (email + password)
2. Create a document in `smart_boards` with the board's email
3. Return the generated email + password to the faculty app
4. NOT store any hardware fingerprint or device ID

---

## 4. Board Boot Flow

```
BOOT
  │
  ├── 1. Load .env, check SSL pinning
  │
  ├── 2. Check Isar for local Registration object
  │       └── If missing → RegistrationScreen
  │
  ├── 3. Sign in with Firebase Auth (email + password from SecureStorage)
  │       └── Store idToken, refreshToken
  │
  ├── 4. Validate server-side registration (NEW - CRITICAL)
  │       └── Call GET /api/v1/board/time with Bearer token
  │       └── If 403 BOARD_NOT_FOUND → RegistrationScreen with error
  │       └── If success → proceed
  │
  ├── 5. Enter IdleScreen
  │       ├── Sync timetable from Firestore REST
  │       ├── Start heartbeat timer (5 min interval)
  │       ├── Start pre-flight countdown watcher
  │       └── Start window orchestrator
```

### Step 4 Detail: Server-Side Registration Validation

The board calls `GET /api/v1/board/time` not just to sync clock, but as a lightweight canary:

```
GET /api/v1/board/time
Authorization: Bearer <idToken>

Success 200:
{
  "serverTime": <unix-epoch-ms>
}

Failure 403:
{
  "error": "BOARD_NOT_FOUND",
  "message": "Board not registered in smart_boards collection"
}
```

If the server returns 403, the board **must not** proceed to IdleScreen. It should show a clear error: "Board not registered on server. Contact IT."

---

## 5. Session Lifecycle

```
TIMELINE:     T-10            T-3            T-0           T+end
               │               │              │              │
EVENTS:        │               │              │              │
               ├── Status      ├── Pre-flight  ├── Lock      ├── End-of-class
               │    check      │    warm-up   │    screen    │    reminder
               │    (sync      │    (pre-     │              │
               │    timetable, │    allocate  │              │
               │    telemetry) │    session)  │              │
               │               │              │              │
               ▼               ▼              ▼              ▼
          ┌─────────┐    ┌──────────┐    ┌──────┐      ┌────────┐
          │ IDLE    │    │ARMED     │    │PIN   │      │ACTIVE  │
          │ (wait)  │───►│(pre-     │───►│ENTRY │─────►│SESSION │
          │         │    │ flight   │    │      │      │(attend)│
          └─────────┘    │ done)    │    └──────┘      └────────┘
                         └──────────┘
```

### 5.1 T-10 Status Check (Board Only)

At 10 min before class start, the board:
- Syncs timetable from Firestore REST
- Pushes hardware telemetry
- No API call to the backend server

### 5.2 T-3 Pre-Flight Warm-Up

```
Board                               Backend
  │                                    │
  │ GET /api/v1/board/preflight        │
  │ ?slot_id=SLOT_...                  │
  │ Authorization: Bearer <token>      │
  │───────────────────────────────────►│
  │                                    │
  │                                    ├── Validate Bearer token
  │                                    ├── Look up smart_boards by email
  │                                    ├── Pre-allocate session ID
  │                                    ├── Create active_sessions doc
  │                                    │   { status: "pre-allocated",
  │                                    │     slotId, smartBoardId }
  │                                    │
  │ 200 {                              │
  │   "pre_allocated_session_id": "...",│
  │   "server_timestamp": <ms>,        │
  │   "status": "ready"                │
  │ }                                  │
  │◄───────────────────────────────────│
  │                                    │
  │ Board stores session_id in RAM     │
  │ Shows "System Ready" on UI         │
```

### 5.3 OTP Initiation

When faculty enters 6-digit PIN:

```
Board                               Backend
  │                                    │
  │ POST /api/v1/board/session/initiate│
  │ Authorization: Bearer <token>      │
  │ Content-Type: application/json     │
  │                                    │
  │ { "otp": "371571" }                │
  │───────────────────────────────────►│
  │                                    │
  │                                    ├── Validate Bearer token
  │                                    ├── Look up smart_boards by email
  │                                    ├── Verify OTP exists in Redis
  │                                    ├── Find session by OTP
  │                                    ├── Mark session as active
  │                                    ├── Update active_sessions doc
  │                                    │   { status: "active",
  │                                    │     sessionSecretHalf1, ... }
  │                                    │
  │ 200 {                              │
  │   "session_id": "33dca24bda7fc...",│
  │   "session_secret_half1": "a1b2..."│
  │   "classroom_id": "room_4208",     │
  │   "section_id": "CSE-AIML-A_2025", │
  │   "subject_id": "R22A6951",        │
  │   "slot_id": "SLOT_...",           │
  │   "faculty_id": "fac03@...",       │
  │   "expires_at": "2026-05-12T...",  │
  │   "ttl_seconds": 7200              │
  │ }                                  │
  │◄───────────────────────────────────│
  │                                    │
  │ Board derives session_secret:      │
  │   half2 = HMAC(boardId, half1)[:16]│
  │   full = half1 + half2             │
  │ Store in SecureStorage             │
  │ Navigate to AttendanceScreen       │
```

**Important:** The server returns `session_secret_half1`, NOT the full `session_secret`. The full secret is derived on the board using HMAC.

### 5.4 QR Token Generation (Server Side)

After activation, generate QR tokens using the full session secret:

```
Token = "IATT::<base64(session_id|timestamp_ms|nonce)>::<hmac_hex[:16]>"

Where:
  payload = base64("session_id|timestamp_ms|random_nonce")
  hmac = HMAC-SHA256(session_secret, payload).toString()[:16]
  token = "IATT::" + payload + "::" + hmac
```

The server's `active_sessions` doc contains the full `session_secret` (populated during activation by the server deriving half2).

### 5.5 Session Termination

```
POST /api/v1/board/session/terminate

Headers:
  Authorization: Bearer <idToken>
  Content-Type: application/json

Body:
{
  "session_id": "33dca24bda7fc8202202"
}

Response 200:
{
  "status": "ended",
  "session_id": "33dca24bda7fc8202202"
}
```

Server MUST:
1. Update `active_sessions` doc → `status: "ended"`
2. Clear Redis cache for this session
3. Return 200

---

## 6. API Endpoints (Complete Reference)

### 6.1 `GET /api/v1/board/time`

Lightweight clock sync + server-side registration canary.

| | |
|---|---|
| Auth | Required |
| Purpose | Clock sync + registration validation |
| Response 200 | `{ "serverTime": <unix-epoch-ms> }` |
| Response 403 | `{ "error": "BOARD_NOT_FOUND", "message": "..." }` |

### 6.2 `GET /api/v1/board/timetable`

No auth required. Returns today's slots for the board's classroom.

| | |
|---|---|
| Auth | None |
| Query | `?classroomId=room_4208` |
| Response 200 | `{ "slots": [ { "slotId", "startTime", "endTime", "courseName", "facultyName", "sectionId" } ] }` |

### 6.3 `GET /api/v1/board/preflight`

Pre-allocates a session ID for the upcoming class.

| | |
|---|---|
| Auth | Required (Bearer) |
| Query | `?slot_id=SLOT_...` |
| Response 200 | `{ "pre_allocated_session_id": "...", "server_timestamp": <ms>, "status": "ready" }` |
| Side effect | Create `active_sessions` doc with `status: "pre-allocated"` |
| Response 403 | `{ "error": "BOARD_NOT_FOUND", "message": "..." }` |

### 6.4 `POST /api/v1/board/session/initiate`

Activates a session with faculty OTP.

| | |
|---|---|
| Auth | Required (Bearer) |
| Body | `{ "otp": "371571" }` |
| Response 200 | `{ "session_id", "session_secret_half1", "classroom_id", "section_id", "subject_id", "slot_id", "faculty_id", "expires_at", "ttl_seconds" }` |
| Response 401 | `OTP_INVALID_OR_EXPIRED`, `SESSION_EXPIRED`, `OTP_MISMATCH`, `MISSING_BOARD_ID` |
| Response 403 | `BOARD_NOT_FOUND`, `UNAUTHORIZED_HARDWARE` |
| Response 503 | `CACHE_UNAVAILABLE` |

### 6.5 `POST /api/v1/board/session/attendance/record-live`

Records a student attendance scan.

| | |
|---|---|
| Auth | Required (Bearer) |
| Body | `{ "student_id", "session_id", "room_id", "entry_type", "timestamp_ms" }` |
| Response 200 | `{ "status": "recorded" }` |

### 6.6 `POST /api/v1/board/session/terminate`

Ends an active session.

| | |
|---|---|
| Auth | Required (Bearer) |
| Body | `{ "session_id": "..." }` |
| Response 200 | `{ "status": "ended", "session_id": "..." }` |

---

## 7. Heartbeat / Telemetry

### 7.1 Heartbeat (`POST /api/v1/board/heartbeat`)

Sent every 5 minutes from IdleScreen and AttendanceScreen.

```
POST /api/v1/board/heartbeat
Authorization: Bearer <idToken>
Content-Type: application/json

{
  "boardId": "IASB-4208",
  "screenState": "idle",
  "uptimeSeconds": <int>,
  "appVersion": "5.8.0+1",
  "timestamp": <ISO8601>
}
```

| | |
|---|---|
| Auth | Required (Bearer) |
| Response 200 | `{ "status": "ok" }` |
| Response 403 | `{ "error": "BOARD_NOT_FOUND" }` — server MUST return 403, not 401 |

### 7.2 Telemetry (`POST /api/v1/board/telemetry`)

Sent on boot and periodically.

```
POST /api/v1/board/telemetry
Authorization: Bearer <idToken>
Content-Type: application/json

{
  "boardId": "IASB-4208",
  "wifiSignalDbm": -45,
  "availableStorageGb": 12.5,
  "appVersion": "5.8.0+1",
  "timestampMs": <unix-epoch-ms>
}
```

| | |
|---|---|
| Auth | Required (Bearer) |
| Response 200 | `{ "status": "ok" }` |
| Response 404 | Acceptable if endpoint not deployed — board logs and ignores |

---

## 8. Error Contract

### 8.1 HTTP Status Codes

| Code | Meaning | When |
|------|---------|------|
| 200 | Success | All successful operations |
| 401 | Authentication failure | Firebase token missing, expired, or invalid |
| 403 | Authorization failure | Board not in `smart_boards`, or wrong classroom |
| 404 | Not found | Endpoint or resource doesn't exist |
| 503 | Service unavailable | Redis down, temporary failure |

### 8.2 Error Response Format

All errors MUST return JSON:

```json
{
  "error": "<ERROR_CODE>",
  "message": "<Human-readable description>"
}
```

### 8.3 Error Codes

| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `MISSING_BOARD_ID` | 401 | Firebase token missing from Authorization header |
| `TOKEN_EXPIRED` | 401 | Firebase token expired |
| `OTP_INVALID_OR_EXPIRED` | 401 | OTP not found in Redis |
| `OTP_MISMATCH` | 401 | OTP doesn't match stored value |
| `SESSION_EXPIRED` | 401 | Pre-allocated session expired |
| `BOARD_NOT_FOUND` | 403 | Board email not found in `smart_boards` collection |
| `UNAUTHORIZED_HARDWARE` | 403 | Board's classroom doesn't match the slot's classroom |
| `CACHE_UNAVAILABLE` | 503 | Redis is down, retry with backoff |

### 8.4 Board-Side Error Handling

| Error | Board Behavior |
|-------|---------------|
| `BOARD_NOT_FOUND` (any endpoint) | Redirect to RegistrationScreen, clear local registration |
| `TOKEN_EXPIRED` | Refresh token silently, retry request |
| `OTP_INVALID_OR_EXPIRED` | Show "PIN expired — faculty must restart" |
| `OTP_MISMATCH` | Show "Invalid PIN — try again" |
| `SESSION_EXPIRED` | Show "Session expired — restart attendance flow" |
| Network error | Retry up to 3 times with exponential backoff |

---

## 9. Implementation Checklist

### Phase 1: Firestore Data (⏳ Backend Team)

- [ ] Create `smart_boards` collection
- [ ] Add document for IASB-4208: `{ boardId, email, classroomId, status }`
- [ ] Verify `timetable_slots` collection has all 36 slots for room_4208
- [ ] Verify `timetable_slots` documents use field `classroomId` (not `smart_board_id`)

### Phase 2: Auth Alignment (⏳ Backend Team)

- [ ] Remove all `X-Device-ID` / `X-Board-ID` / hardware fingerprint checks
- [ ] Board identity resolved **only** from Firebase Bearer token → email → `smart_boards` lookup
- [ ] All endpoints return `403 BOARD_NOT_FOUND` for unrecognized boards
- [ ] All endpoints return `401 MISSING_BOARD_ID` for missing/expired tokens
- [ ] Heartbeat endpoint returns 403 (not 401) for unrecognized boards
- [ ] Pre-flight endpoint returns 403 for unrecognized boards

### Phase 3: Session Initiation (⏳ Backend Team)

- [ ] `POST /api/v1/board/session/initiate` returns `session_secret_half1` (not full secret)
- [ ] OTP verification uses Redis lookup
- [ ] Active session doc updated with full `session_secret` + `status: "active"`
- [ ] QR token generator reads `active_sessions.session_secret` for HMAC

### Phase 4: Board-Side Guards (Implemented ✅)

- [x] `_handleIncomingSession` — crash recovery only, ignores stale Firestore docs
- [x] BootScreen validates local registration + Firebase token
- [x] OTP flow uses pre-allocated session ID from pre-flight API
- [x] Session secret derived via HMAC split-knowledge
- [x] Three-tier kiosk fullscreen (soft / locked / absoluteLocked)
- [x] Fallback warm-up for current slot when board boots after class start

