# Backend Team — Action Items

The SmartBoard app is fully ready at v5.8+. The backend needs these changes before we can test end-to-end.

---

## Priority 1 (Blocking — Must Do First)

### 1. Implement Firebase Token Auth Middleware

Replace all `X-Device-ID` / `X-Board-ID` / hardware-fingerprint checks with Firebase Bearer token resolution:

```
Request:
  Authorization: Bearer <Firebase ID Token>

Server:
  1. Verify Firebase ID token
  2. Extract email from token payload (e.g. iasb-4208@smartboard.intelliattend.com)
  3. Query smart_boards collection WHERE email == extracted_email
  4. If found → proceed (board_data = doc)
  5. If not found → 403 BOARD_NOT_FOUND
```

**Remove all references to:**
- `X-Device-ID` header
- `X-Board-ID` header
- Device fingerprint / MAC address / hardware identity

### 2. Create `smart_boards` Document for IASB-4208

The board's Firebase Auth account exists (`iasb-4208@smartboard.intelliattend.com`) but the `smart_boards` Firestore doc is missing. All authenticated endpoints return 403.

**Required document fields:**
```json
{
  "boardId": "IASB-4208",
  "classroomId": "room_4208",
  "email": "iasb-4208@smartboard.intelliattend.com",
  "registeredAt": "<timestamp>"
}
```

Without this, all endpoints below will 403.

### 3. Add Auth Guard to Endpoints That Currently Have None

| Endpoint | Current State | Action |
|----------|--------------|--------|
| `GET /api/v1/board/time` | No auth guard | Add Firebase Bearer middleware (or remove if not needed) |
| `POST /api/v1/board/session/terminate` | Returns stub, no guard | Add middleware + real implementation |
| `POST /api/v1/board/session/attendance/record-live` | Returns stub, no guard | Add middleware + real implementation |

---

## Priority 2 (Required for Full Flow)

### 4. Verify Endpoint Compliance

Cross-check against `docs/BACKEND_INTEGRATION_SPEC.md` sections 6 and 8. Key endpoints:

| Endpoint | What Board Expects | Response |
|----------|-------------------|----------|
| `GET /api/v1/board/ready` | Lightweight canary — board calls on every boot | `200 OK` if registered, `403 BOARD_NOT_FOUND` if not |
| `GET /api/v1/board/preflight?slot_id=...` | Returns `pre_allocated_session_id` | `200 { pre_allocated_session_id }` |
| `POST /api/v1/device/heartbeat` | Board sends every 30s in Idle mode | `200 OK` |
| `POST /api/v1/board/session/initiate` | OTP → `session_id` + `session_secret_half1` | `200` with payload |
| `POST /api/v1/board/session/terminate` | End session cleanly | `200 { status: "terminated" }` |
| `POST /api/v1/board/session/attendance/record-live` | Record student scan | `200 { status: "recorded" }` |

### 5. Error Contract Compliance

All errors must follow this format:
```json
{
  "detail": "Human-readable message",
  "code": "MACHINE_READABLE_CODE"
}
```

**Standard error codes the board handles:**

| Code | HTTP | When |
|------|------|------|
| `BOARD_NOT_FOUND` | 403 | Token email not in `smart_boards` |
| `INVALID_TOKEN` | 401 | Firebase token expired or invalid |
| `OTP_INVALID_OR_EXPIRED` | 401 | OTP not in Redis cache |
| `SESSION_EXPIRED` | 401 | Session TTL exceeded |
| `OTP_MISMATCH` | 401 | OTP value doesn't match |
| `SESSION_NOT_FOUND` | 404 | Session ID doesn't exist |

### 6. Remove Outdated Error Codes

These should be removed (no longer possible without hardware headers):
- `UNAUTHORIZED_HARDWARE` (was for X-Device-ID mismatch)
- `MISSING_BOARD_ID` (board never sends board_id)

---

## Priority 3 (Questions — Need Answers)

### Q1: Is `GET /api/v1/board/ready` staying in the spec?

The board's boot canary (`boot_screen.dart:78`) calls this endpoint. If removed, we need an alternative — we can use `GET /api/v1/board/time` with the auth guard, or a dedicated endpoint.

### Q2: Is `GET /api/v1/board/timetable` meant to be unauthenticated?

The endpoints table in the auth spec lists it as "(no auth)" but also says "Every API call requires Authorization." Which is correct? The board currently fetches timetable directly from Firestore REST API (bypassing the backend entirely) — if the backend also exposes it, we can switch. **Recommendation:** keep it simple — board continues using Firestore REST for timetable, backend doesn't need this endpoint.

### Q3: Is telemetry / heartbeat being kept or removed?

`POST /api/v1/device/heartbeat` and `POST /api/v1/board/telemetry` exist in the current codebase — if the backend team plans to remove them, tell us so we can delete the board-side code. If keeping them, they need auth guards.

### Q4: Boot canary — which endpoint should the board hit?

Our current choice: `GET /api/v1/board/ready`. Confirm this exists in the final backend, or tell us which endpoint to use as the lightweight "is this board registered?" check.

---

## Summary of Dependencies

```
Backend creates smart_boards doc for IASB-4208
  ├── Auth middleware implemented (no X-Device-ID)
  │     ├── All endpoints start returning 200 instead of 403
  │     │     ├── Canary → IdleScreen transition works
  │     │     ├── Pre-flight handshake works
  │     │     ├── Heartbeat works
  │     │     └── OTP initiation works
  │     └── Answers to Q1-Q4 received
  │           └── Board-side adjustments (if any) are minimal
  │
  └── Board-side regression test plan:
        - Boot → BootScreen → Canary 200 → IdleScreen
        - Timetable syncs (36 slots)
        - T-10 pre-boot brings window to front
        - T-3 warm-up fires
        - OTP entry → session initiation
        - QR code generation
        - Attendance recording
        - Session termination
        - Heartbeat in Idle
