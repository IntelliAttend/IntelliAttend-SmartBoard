# HMAC Split-Knowledge Secret

**Status:** IMPLEMENTED (v5.8)  
**Scope:** Backend + SmartBoard Client  
**Objective:** Prevent session_secret exfiltration from any single leak vector (API logs, error reports, monitoring dashboards, MITM intercept).

---

## 1. The Problem

`POST /api/v1/board/session/initiate` previously returned the full `session_secret` in the JSON response:

```json
{
  "session_id": "SESS_ABC123",
  "session_secret": "the_full_44_char_secret_in_plaintext",
  "course_name": "CS301",
  ...
}
```

If an attacker gains access to **any one** of these:
- API response body
- API access logs (server-side)
- Monitoring dashboard (e.g., Datadog, New Relic)
- Error reports / crash dumps
- MITM / proxy intercept (e.g., Charles, Burp Suite)

They have the full `session_secret` and can forge attendance QR codes for that session.

---

## 2. The Solution: Split-Knowledge (Dual Control)

Instead of transmitting the full secret over the wire, split it into two halves that must be **independently** acquired and recombined:

```
session_secret = half1 ⊕ half2
                      │       │
                  from API    derived from hardware
                  response    fingerprint (never transmitted)
```

No single leak vector exposes both halves. Only a **physical device compromise** (attacker has both the API response AND the device's filesystem) allows reconstruction.

---

## 3. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                    PHASE 1: FACULTY CREATES SESSION                   │
│                                                                      │
│  Faculty App                    Backend                               │
│     │                              │                                 │
│     │  POST /session/create        │                                 │
│     │  { course, faculty, ... }    │                                 │
│     │─────────────────────────────►│                                 │
│     │                              ├── generate half1, OTP           │
│     │                              ├── Session doc: { half1,         │
│     │                              │    otp, status: otp_pending }   │
│     │                              ├── ActiveSession doc: { half1,   │
│     │                              │    status: pending }            │
│     │  { session_id, otp }         │                                 │
│     │◄─────────────────────────────│                                 │
└──────────────────────────────────────────────────────────────────────┘
                                    │ Faculty shows OTP on screen
                                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    PHASE 2: SMARTBOARD INITIATES                      │
│                                                                      │
│  SmartBoard Client              Backend                               │
│     │                              │                                 │
│     │  POST /session/initiate      │                                 │
│     │  X-Device-ID: sha256(hw)    │                                 │
│     │  { otp: "483291" }          │                                 │
│     │─────────────────────────────►│                                 │
│     │                              │                                 │
│     │                              ├── _verify_board_signature()     │
│     │                              │    → { device_id, status }      │
│     │                              │                                 │
│     │                              ├── find_session_by_otp(otp)      │
│     │                              │    → { half1, session_id, ... } │
│     │                              │                                 │
│     │                              ├── half2 = HMAC(device_id,       │
│     │                              │    half1)[:16]                   │
│     │                              ├── full_secret = half1 + half2   │
│     │                              │                                 │
│     │                              ├── activate_session()            │
│     │                              │    → ActiveSession:             │
│     │                              │      { session_secret, active } │
│     │                              │    → Initial QR token           │
│     │                              │    → Redis cache                │
│     │                              │                                 │
│     │  { session_id,               │                                 │
│     │    session_secret_half1 }    │   ← NO full secret              │
│     │◄─────────────────────────────│                                 │
│     │                              │                                 │
│     ├── getDeviceId()              │                                 │
│     ├── half2 = HMAC(deviceId,     │                                 │
│     │    half1)[:16]               │                                 │
│     ├── full = half1 + half2       │                                 │
│     └── Store in keychain         │                                 │
└──────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    QR TOKEN ROTATION & VERIFICATION                    │
│                                                                      │
│  Token Rotation (every 5s)     QR Verification (student scan)        │
│     │                              │                                 │
│     ├── Read ActiveSession         ├── Read ActiveSession            │
│     │   .session_secret            │   .session_secret               │
│     ├── Same field as before       ├── Same field as before          │
│     └── Unchanged                  └── Unchanged                     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 4. Detailed Protocol Flow

### 4.1 Session Creation (Faculty App — Pre-Initiation)

```
Faculty App                  Backend
     │                           │
     │  POST /session/create     │
     │  { course_name,           │
     │    faculty_name,          │
     │    section_id,            │
     │    roster_count }         │
     │──────────────────────────►│
     │                           │
     │                           ├── half1 = base64(token_bytes(16))
     │                           ├── OTP = random 6-digit code
     │                           ├── session_id = "SESS_" + hex(4)
     │                           │
     │                           ├── Session doc:
     │                           │    { session_secret_half1: half1,
     │                           │      otp: "483291",
     │                           │      status: "otp_pending",
     │                           │      course_name: "CS301", ... }
     │                           │
     │                           ├── ActiveSession doc:
     │                           │    { session_secret_half1: half1,
     │                           │      status: "pending" }
     │                           │    └── No initial QR token
     │                           │    └── Scheduler ignores status=pending
     │                           │
     │  { session_id, otp }      │
     │◄──────────────────────────│
```

Key detail: The ActiveSession is pre-created during faculty session creation with `session_secret_half1` and `status: "pending"`. It is populated with the full secret + initial token during activation.

### 4.2 Session Initiation (`/session/initiate` endpoint)

```
SmartBoard Client            Backend
     │                           │
     │  POST /session/initiate   │
     │  X-Device-ID: sha256(hw)  │
     │  Body: { otp: "483291" }  │
     │──────────────────────────►│
     │                           │
     │                           ├── _verify_board_signature()
     │                           │    → { device_id, status: "ACTIVE", ... }
     │                           │
     │                           ├── find_session_by_otp("483291")
     │                           │    → Queries Sessions where otp == "483291"
     │                           │      AND status == "otp_pending"
     │                           │    → Returns { session_id, half1, ... }
     │                           │
     │                           ├── verify_otp_and_mark_faculty(session_id)
     │                           │    → Marks OTP as verified
     │                           │    → Returns { session_secret_half1, ... }
     │                           │
     │                           ├── half2 = HMAC(device_id, half1)[:16]
     │                           ├── full_secret = half1 + half2
     │                           │
     │                           ├── activate_session(session_id, full_secret)
     │                           │    → Updates ActiveSession:
     │                           │      { session_secret, status: "active" }
     │                           │    → Generates initial QR token
     │                           │    → Writes Redis session_secret:<id>
     │                           │
     │  { session_id,            │
     │    session_secret_half1,  │   ← NO full secret in response
     │    course_name, ... }     │
     │◄──────────────────────────│
```

### 4.3 Client-side Reconstruction (`idle_screen.dart:378-386`)

```dart
// Step 1: Get half1 from API response
final half1 = data['session_secret_half1']?.toString();
if (half1 == null) throw Exception('Missing session_secret_half1');

// Step 2: Get device_id (same value as X-Device-ID header)
final deviceId = await HardwareFingerprintService.getDeviceId();
// deviceId = sha256(raw_hw_fingerprint) = "a3f8b2...c9d1"

// Step 3: Derive half2 using device_id as HMAC key
final half2 = Hmac(sha256, utf8.encode(deviceId))
    .convert(utf8.encode(half1))
    .toString()
    .substring(0, 16);

// Step 4: Reconstruct full secret
final sessionSecret = '$half1$half2';

// Step 5: Use identically to previous session_secret
await SecureStorageService.storeSessionSecret(sessionId, sessionSecret);
```

### 4.4 Downstream Operations (Unchanged)

All operations that read `session_secret` from `ActiveSession` are unchanged:

| Operation | Reads from | Change? |
|-----------|-----------|---------|
| Token rotation | `ActiveSession.session_secret` | None |
| QR code verification | `ActiveSession.session_secret` | None |
| End session | `ActiveSession.session_secret` | None |
| `get_all_active_sessions()` | Filters by `status == "active"` | None (pending sessions invisible) |

---

## 5. HMAC Key Alignment

**Critical:** Both sides must use the **same key** for HMAC derivation, or the reconstructed `half2` values won't match.

```
Raw HW Fingerprint:    "MB_SERIAL_CPU456_MAC789_DISK_GUID123"
                              │
                              ▼
getDeviceId() / X-Device-ID:  sha256(raw) = "a3f8b2c9d1..."
                              │
           ┌──────────────────┼──────────────────┐
           ▼                  ▼                  ▼
    Server HMAC key     Client HMAC key     Stored as device_id
    = device_id         = deviceId           in RegisteredDevices
    = "a3f8b2..."       = "a3f8b2..."        during OTP registration
           │                  │
           └──────┬───────────┘
                  ▼
          half2 = HMAC-SHA256(key, half1)[:16]
                  │
                  ▼
          Both sides compute the identical half2 ✅
```

**The function `getDeviceId()` returns `sha256(raw_hw_string)`** — the same value sent as `X-Device-ID` header and stored as `device_id` in the server's `RegisteredDevices` collection.

---

## 6. State Machine

```
Session (Sessions collection)
─────────────────────────────────────────────────
  [CREATED] ──create_session()──▶ [OTP_PENDING]
                                      │
                          verify_otp_and_mark_faculty()
                          + half2 derivation
                                      │
                                      ▼
                                  [ACTIVE]
                                      │
                              end_session()
                                      │
                                      ▼
                                  [ENDED]

ActiveSession (ActiveSessions collection)
─────────────────────────────────────────────────
  [PENDING] ──create_active_session()──▶ [PENDING]
                                              │
                                  activate_session()
                                  (half2 + full_secret)
                                              │
                                              ▼
                                          [ACTIVE]
                                              │
                                      end_session()
                                              │
                                              ▼
                                          [ENDED]

Token Rotation Scheduler:
  - Reads ActiveSession where status == "active"
  - PENDING sessions are invisible to the scheduler
  - No initial token generated until activation
```

---

## 7. Security Analysis

### 7.1 Leak Vectors

| Leak Vector | Before (full secret in response) | After (half1 only) | Severity |
|-------------|----------------------------------|-------------------|----------|
| API response body | Full secret leaked | Only half1 | ✅ Critical fix |
| API access logs (server) | Full secret visible in request/response logging | Only half1 | ✅ High |
| Monitoring dashboards | Full secret in captured traces | Only half1 | ✅ High |
| Error reports / crash dumps | Full secret captured in stack traces | Only half1 | ✅ High |
| MITM / proxy intercept | Full secret stolen from HTTP body | Only half1 | ✅ High |
| Firestore database breach | Full secret in `ActiveSession.session_secret` | Full secret still present (populated at activation) | ⚠️ Unchanged |

### 7.2 Attack Scenarios

| Scenario | Old System | New System | Improvement |
|----------|-----------|------------|-------------|
| Attacker reads API logs | Full secret → forge QR codes | Only half1 → cannot derive half2 without device_id | ✅ |
| Attacker hacks monitoring dashboard | Full secret captured | Only half1 visible | ✅ |
| Attacker intercepts HTTPS (MITM) | Full secret stolen | Only half1 stolen → needs device physical access for half2 | ✅ |
| Attacker dumps Firestore ActiveSessions | Full session_secret read directly | Full session_secret still readable (same field, populated at activation) | ⚠️ No change |
| Attacker steals device (physical) | Secret in OS keychain → encrypted | Secret in OS keychain → encrypted | Same |
| Attacker has both Firestore dump AND device physical access | Can reconstruct full secret | Can reconstruct full secret | Same |

### 7.3 What We Accept

The split protects against **API transit and log exposure** (the 5 most common leak vectors). It does not protect against a **Firestore database breach** because the full `session_secret` is still stored in `ActiveSession.session_secret` (populated during `activate_session()`). Protecting against DB breach would require external infrastructure (e.g., Redis with TTL-scoped device_id caching) which is not justified for this project's threat model.

---

## 8. Implementation Checklist

### 8.1 Backend — Two-Phase Architecture

**Phase 1: Faculty creates session** (`POST /session/create`)

| # | File | Change |
|---|------|--------|
| 1 | `services/session_service.py` — `create_session()` | Generate `token_bytes(16)` → base64 for half1. Generate 6-digit OTP. Store as `session_secret_half1` + `otp` in Session doc. |
| 2 | `services/active_sessions_service.py` — `create_active_session()` | Store `session_secret_half1`, `status: "pending"`. Skip token generation. No Redis write. |

**Phase 2: SmartBoard initiates** (`POST /session/initiate`)

| # | File | Change |
|---|------|--------|
| 3 | `services/session_service.py` — `find_session_by_otp()` (new) | Query Sessions collection where `otp == request.otp AND status == otp_pending`. Return `{ session_id, half1, ... }`. |
| 4 | `services/session_service.py` — `verify_otp_and_mark_faculty()` | Accept `session_id`. Mark OTP as verified. Return `{ session_secret_half1 }`. Backward compat: `half1 = (session_secret or "")[:22]` fallback. |
| 5 | `services/active_sessions_service.py` — `activate_session()` (new) | Accept `session_id, full_secret`. Generate initial token. Set `session_secret`, `status: "active"`. Update Firestore + Redis cache. |
| 6 | `main.py` — `/session/initiate` endpoint | Extract `device_id` from board_data. Call `find_session_by_otp()`. Derive `half2 = HMAC(device_id, half1)[:16]`. Call `activate_session()`. Return `session_secret_half1`. |

### 8.2 Client (1 file, ~5 lines changed)

| # | File | Change |
|---|------|--------|
| 1 | `services/hardware_fingerprint_service.dart` | Rename `getWindowsFingerprint()` → `getDeviceId()`. Keeps returning `sha256(raw_hw)`. |
| 2 | `presentation/screens/idle_screen.dart` | Replace `session_secret` read with `session_secret_half1` + HMAC derivation. |

### 8.3 Files Not Changed

| File | Reason |
|------|--------|
| Token rotation logic | Reads `ActiveSession.session_secret` (same field, populated at activation) |
| QR verification logic | Reads `ActiveSession.session_secret` (same field) |
| End session logic | Reads `ActiveSession.session_secret` (same field) |
| Backward-compat check | `doc.get("session_secret")` → if present, use full secret directly (old sessions) |

---

## 9. Key Code References

### 9.1 Backend Python

| File | Function | Purpose |
|------|----------|---------|
| `main.py:42-86` | `initiate_session()` | Orchestrates the entire split flow |
| `services/session_service.py:9-46` | `create_session()` | Generates half1, session_id, stores in Session doc |
| `services/session_service.py:48-79` | `verify_otp_and_mark_faculty()` | Validates OTP, returns half1 |
| `services/active_sessions_service.py:16-50` | `create_active_session()` | Stores half1 in ActiveSession (status=pending) |
| `services/active_sessions_service.py:52-83` | `activate_session()` | Derives full secret, generates token, updates Firestore + Redis |
| `services/active_sessions_service.py:85-106` | `get_session_secret()` | Reads with Redis fast-path + Firestore fallback |
| `services/board_service.py:7-33` | `get_board_data()` | Extracts device_id from X-Device-ID header |
| `services/cache_service.py` | `CacheService` | Redis cache with in-memory fallback |
| `services/token_validator.py` | `TokenGenerator` | Token generation, validation, rotation |

### 9.2 Client Dart

| File | Line | Purpose |
|------|------|---------|
| `hardware_fingerprint_service.dart:7` | `getDeviceId()` | Returns `sha256(raw_hw)` = X-Device-ID value |
| `idle_screen.dart:378` | `half1 = data['session_secret_half1']` | Reads half1 from API response |
| `idle_screen.dart:381` | `deviceId = getDeviceId()` | Gets HMAC key (same as X-Device-ID header) |
| `idle_screen.dart:382-385` | `half2 = Hmac(sha256, deviceId).convert(half1)[:16]` | Derives half2 locally |
| `idle_screen.dart:386` | `sessionSecret = '$half1$half2'` | Reconstructs full secret |
| `idle_screen.dart:387-389` | `else { sessionSecret = data['session_secret'] }` | Backward compat with old sessions |

---

## 10. Edge Cases

### 10.1 Backward Compatibility (In-Flight Sessions)

Sessions created before the HMAC split migration have `session_secret` (full secret) stored directly. The code handles this:

```dart
// Client-side backward compat
if (half1 != null) {
  // New flow: derive half2 from device_id
} else {
  // Old flow: use full session_secret directly
  sessionSecret = data['session_secret']?.toString() ?? '';
}
```

```python
# Server-side backward compat
full_secret = doc.get("session_secret")          # old format
if not full_secret:
    half1 = doc.get("session_secret_half1")       # new format
    redis_half2 = await cache.get(f"session_half2:{session_id}")
    full_secret = half1 + redis_half2
```

### 10.2 Unregistered Boards

`_verify_board_signature()` calls `verify_device_binding()` internally, which rejects any board with `status != "ACTIVE"`. The `device_id` is guaranteed present in the `RegisteredDevices` document before `half2` derivation runs.

### 10.3 OTP Verification

The `verify_otp_and_mark_faculty()` function does NOT receive the `device_id` — it only handles OTP validation and returns the `session_secret_half1`. The actual `half2` derivation happens in the endpoint, keeping the service layer clean.

### 10.4 Redis Unavailable

If Redis is down, `CacheService` falls back to in-memory dictionary. The `activate_session()` still writes `session_secret` to Firestore, so token rotation and QR verification fall through to Firestore reads. No session bricking.

---

## 11. HMAC Derivation: Why `device_id` and Not Raw Fingerprint

```
Raw HW Fingerprint:     "MB_SERIAL_CPU456_MAC789_DISK_GUID123"    (variable length, ~60 chars)
device_id = sha256(raw): "a3f8b2c9d1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9"  (64 hex chars, fixed)

Why device_id as HMAC key:
  ✓ Both client and server have it (client from getDeviceId(), server from X-Device-ID header)
  ✓ Fixed-length key (64 hex chars) — no padding/variable-length issues
  ✓ Already a high-entropy hash — cryptographically sound as HMAC key
  ✓ Stored during OTP registration — server has it for the lifetime of the device

Why NOT raw fingerprint:
  ✗ Variable length — different OS APIs return different lengths
  ✗ Server would need to store the raw string (extra PII/data exposure)
  ✗ No benefit — device_id is already derived from raw with maximal entropy
```

---

## 12. File Structure (Backend — Reference Implementation)

```
backend/python/
├── main.py                          # FastAPI routes (2 endpoints)
├── requirements.txt
├── serviceAccountKey.json
└── services/
    ├── __init__.py
    ├── board_service.py             # X-Device-ID → board_data + device_id
    ├── session_service.py           # create_session, find_by_otp, verify
    ├── active_sessions_service.py   # create_pending, activate, get, end
    ├── token_validator.py           # QR token gen/validate/rotate
    └── cache_service.py             # Redis (optional, in-memory fallback)
```

---

## 13. Pros & Cons Summary

| Aspect | Old System | New System |
|--------|-----------|------------|
| API response contains | Full `session_secret` | Only `session_secret_half1` |
| API logs reveal | Full secret | Only half1 |
| Error reports capture | Full secret | Only half1 |
| MITM intercept gets | Full secret | Only half1 |
| Firestore breach reveals | Full secret | Full secret (same — unchanged) |
| Client changes | None | ~5 lines in `idle_screen.dart` |
| Backend changes | None | ~40 lines across 4 files |
| New dependencies | None | `redis` (optional, graceful fallback) |
| Backward compatible | N/A | Yes — old sessions with full `session_secret` still work |

---

**Document Version:** 1.0  
**Last Updated:** May 8, 2026  
**Approver:** System Architect
