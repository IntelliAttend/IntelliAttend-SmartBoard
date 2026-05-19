# Backend API Issues — SmartBoard Integration

**Status:** UNRESOLVED (server-side)  
**Scope:** Backend team  
**Objective:** Document all known backend API issues blocking SmartBoard functionality.

---

## 1. Heartbeat 401 — Hardware Security Binding Violation

### SmartBoard Request
```
POST /api/v1/device/heartbeat
Headers:
  X-Device-ID: IASB-4208
  Authorization: Bearer <firebase-id-token>
  Content-Type: application/json

Body:
{
  "smart_board_id": "IASB-4208",
  "hardware_id": "<sha256-fingerprint>",
  "screen_state": "idle",
  "uptime_seconds": 120,
  "app_version": "5.4.0+1",
  "system_metrics": {
    "memory_usage_mb": 0,
    "cpu_load_percent": 0.0,
    "network_latency_ms": 0
  },
  "timestamp": "2026-05-12T14:09:03.431Z"
}
```

### Server Response
```
HTTP 401
{
  "detail": "Hardware security binding violation."
}
```

### Root Cause (Hypothesized)
Device `IASB-4208` is **not registered** in the running server's Firestore (`RegisteredDevices` or `smart_boards` collection). The server performs a lookup of the device's `smart_board_id` against its registration table during heartbeat and rejects unregistered devices.

Alternatively, the `hardware_id` (SHA-256 fingerprint of the Windows machine) does not match the fingerprint stored during registration. This could happen if:
- The board was registered on a different physical machine
- The hardware fingerprint changed (OS reinstall, hardware change)
- The registration document was deleted from Firestore

### Impact
| Item | Impact |
|---|---|
| Heartbeat | Logged and ignored — fire-and-forget. No functional impact. |
| Pre-flight | Works independently — uses same auth token, doesn't depend on heartbeat. |
| Session initiation | Unknown — may also 401 if server checks hardware binding on every call. |
| Attendance recording | Unknown — may fail mid-class if server enforces binding per-request. |

### To Reproduce
1. Register board `IASB-4208` on any Windows machine
2. Start the SmartBoard
3. Observe `POST /api/v1/device/heartbeat` → `401`

### Fix Required (Backend Team)
**Option A:** Register device `IASB-4208` in the running server's Firestore:
```json
// Collection: RegisteredDevices
// Document ID: IASB-4208 or auto-generated
{
  "smart_board_id": "IASB-4208",
  "classroom_id": "room_4208",
  "hardware_fingerprint": "<sha256-of-board-machine>",
  "registered_at": <timestamp>,
  "status": "active"
}
```

**Option B:** If the endpoint exists but the hardware fingerprint changed, clear the binding and re-register.

**Option C:** Make heartbeat tolerant of unknown devices (return 200 for any authenticated device, log the anomaly server-side).

---

## 2. Pre-Flight Endpoint — Was Working After URL Fix

### Status: RESOLVED (SmartBoard side)

The `GET /api/v1/board/preflight?slot_id=SLOT_CSE-AIML-A_2025_Tuesday_P6` endpoint **exists** on the server and returns 200. The SmartBoard was sending a malformed URL (see `docs/PREFLIGHT_HANDSHAKE.md` for details). After fixing the URL encoding in `_buildUri()`, the endpoint responds correctly:
```json
{
  "pre_allocated_session_id": "38008fafa1199767a148",
  "server_timestamp": 1715500000000,
  "status": "ready"
}
```

**No action needed from backend team.**

---

## 3. Pre-Flight Endpoint Contract

For reference, the SmartBoard expects this response from `GET /api/v1/board/preflight?slot_id=<slotId>`:

### Success (200)
```json
{
  "pre_allocated_session_id": "<session-id>",
  "server_timestamp": <unix-epoch-ms>,
  "status": "ready"
}
```

### Server-Side Side-Effect
The server **must** create a Firestore document in `ActiveSessions` **before** returning the response. The SmartBoard's Firestore stream (`watchActiveSession`) picks up this document as a secondary confirmation:

```json
// Collection: ActiveSessions
// Document ID: same as pre_allocated_session_id
{
  "smart_board_id": "IASB-4208",
  "slot_id": "SLOT_CSE-AIML-A_2025_Tuesday_P6",
  "status": "active",
  "created_at": 1715500000000
}
```

---

## 4. Observed Stale ActiveSessions Document

A Firestore document `ActiveSessions/52752cf39c8d9848297e` exists from a previous session but was never cleaned up. The SmartBoard's stream picks it up on boot. This is harmless if the SmartBoard gets a fresh pre-allocation (the new session ID takes precedence), but can confuse debugging.

**Fix:** Add a TTL or cleanup job for `ActiveSessions` documents older than ~6 hours, or implement a `status: "ended"` transition that is set when the session terminates.

---

## 5. Network / Environment

| Item | Value |
|---|---|
| API Base URL | `https://api-dev.balaseetharamanjaneyulu.com` |
| Board ID | `IASB-4208` |
| Classroom ID | `room_4208` |
| Firebase Project | `intelliattend-a2564` |
| Firestore Collection (timetable) | `timetable_slots` (36 docs for room_4208) |
| Firestore Collection (sessions) | `ActiveSessions` |
| Pre-flight Endpoint | ✅ Working |
| Heartbeat Endpoint | ❌ 401 |
| Session Initiate Endpoint | `POST /api/v1/board/session/initiate` — not yet tested |
