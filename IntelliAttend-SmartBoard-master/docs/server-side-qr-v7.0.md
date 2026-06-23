# QR Binary Packing v7.0 — Server Implementation Guide

## Overview

The SmartBoard QR tokens have been redesigned from a text-based format (~86 chars,
QR V3–V4) to a compact binary-packed format (33 chars, QR Version 2 — 25×25 grid).
The student phone app passes the raw string through unchanged; **only the server's
QR parser needs updating**.

## 1. QR Token Format

### Wire Format

```
IATT::<Base64URL(20 bytes)>
```

| Component | Length | Notes |
|-----------|--------|-------|
| `IATT::` prefix | 6 chars | Fixed literal |
| Base64URL payload | 27 chars | 20 raw bytes, URL-safe Base64, **no padding** |
| **Total** | **33 chars** | Fits QR Version 2 (vs V3–V4 previously) |

### Raw Byte Layout (20 bytes)

```
Offset  Size  Field            Description
──────  ────  ───────────────  ─────────────────────────────────────────
 0       6    sessionIdHash    SHA256(sessionId) truncated to first 6 bytes (48 bits)
                                → used to identify the active session on the server
 6       4    timestampSec     Unix epoch timestamp in seconds as uint32 big-endian
                                → NOT milliseconds (saves 2 bytes vs v6.x)
10       2    nonce            Random 16-bit value (0–65535)
                                → prevents same-second replay attacks
12       8    hmac             HMAC-SHA256(secret, header)[0..7] — 64-bit truncated
                                → birthday bound ~2^32, ~634 years at 1 scan/sec
```

**Header** (bytes 0–11): `sessionIdHash[6] | timestampBE[4] | nonce[2]`

### Encoding/Decoding

**Board encoding** (Dart):
```dart
final payloadBytes = <int>[...header, ...hmacBytes];         // 20 bytes
final b64url = base64Url.encode(payloadBytes).replaceAll('=', '');
final token = 'IATT::$b64url';                                // 33 chars
```

**Server decoding**:
```python
import base64, hashlib, hmac, struct

prefix = "IATT::"
assert token.startswith(prefix)
b64 = token[len(prefix):]

# Restore padding (Base64 decoder requires multiple of 4)
while len(b64) % 4 != 0:
    b64 += '='

raw = base64.urlsafe_b64decode(b64)   # 20 bytes
sid_hash = raw[0:6]                   # bytes
ts = struct.unpack('>I', raw[6:10])[0]  # uint32 BE
nonce = raw[10:12]                    # bytes
provided_hmac = raw[12:20]            # bytes
```

### Verification Algorithm

1. Extract `sessionIdHash` (bytes 0–5)
2. Look up the session by matching `SHA256(sessionId)[:6]` against active sessions
   - Store the first 6 bytes of SHA256(sessionId) when creating sessions
3. Check timestamp is within the acceptance window (e.g., ±300s of server time)
4. Reconstruct header: `sessionIdHash | timestampBE | nonce` (12 bytes)
5. Compute: `HMAC-SHA256(fullSecret, header)[:8]`
6. Compare with `provided_hmac` — reject if mismatch

```python
expected_hmac = hmac.new(
    full_secret.encode('utf-8'),
    header,
    hashlib.sha256
).digest()[:8]

if provided_hmac != expected_hmac:
    raise ValueError("HMAC mismatch — token invalid")
```

## 2. Key Differences from v6.x (Old Format)

| Aspect | Old Format (v6.x) | New Format (v7.0) |
|--------|-------------------|--------------------|
| Token length | ~86 chars | 33 chars |
| QR Version | V3–V4 (29–33 grid) | V2 (25×25 grid) |
| QR scan speed | Slower (larger) | Faster (smaller) |
| Timestamp precision | Milliseconds (8 bytes) | Seconds (4 bytes) |
| Timestamp encoding | Base64 string | uint32 big-endian |
| Session ID | Full string in payload | First 6 bytes of SHA256(sessionId) |
| HMAC length | Full hex (64 chars) | 8 bytes (16 hex chars) |
| HMAC position | Appended as `::hex64` suffix | Embedded in 20-byte binary |
| Payload format | `IATT::base64(sid\|ms\|nonce)::hex64` | `IATT::Base64URL(20 raw bytes)` |
| Nonce | Variable-length string | Exactly 2 bytes (16-bit) |
| Padding | N/A | Base64URL padding **explicitly stripped** |

### Padding Note

Base64URL output of 20 bytes is 27 characters (ceil(20×4/3) = 27, remainder 2).
The board strips the `=` padding to save 1 character. The server must **restore
padding** before decoding:

```python
while len(b64_payload) % 4 != 0:
    b64_payload += '='
```

## 3. Security Properties

### HMAC Truncation to 64 Bits

- Full HMAC-SHA256 produces 256 bits
- We truncate to the first 64 bits (8 bytes)
- Birthday bound: after ~2^32 ≈ 4 billion tokens, a collision becomes likely
- At 1 scan/second: ~634 years before reaching the birthday bound
- **Acceptable risk** for classroom attendance — dismissed students cannot reuse
  a QR across sessions because the session ID hash and timestamp change

### Nonce (16-bit)

- 65,536 possible values per second
- Prevents same-second replay: two scans with identical timestamp + nonce → reject
- With 500 students scanning in the same second, collision probability is ~0.4%
  (birthday bound: 1 − exp(−500² / 2 × 65536) ≈ 0.85)

### Session ID Hash (48-bit)

- SHA256(sessionId) truncated to 6 bytes (48 bits)
- Birthday bound: ~2^24 ≈ 16 million sessions before collision possible
- For a university timetable (thousands of sessions per year), collisions are
  **effectively impossible**
- If a collision does occur, the server should fall back to matching by
  `smart_board_id` + timestamp proximity

## 4. Server Changes Required

### 4.1 Session Creation

When creating an ActiveSession, store the first 6 bytes of SHA256(sessionId):

```python
import hashlib

def create_session(session_id, full_secret, ...):
    sid_hash = hashlib.sha256(session_id.encode()).digest()[:6]
    # Store sid_hash alongside session_id for fast QR lookup
    ...
```

### 4.2 QR Parser

Replace the existing parser (which splits on `::` and extracts hex signature)
with the binary decoder above. The parser must:

1. Strip `IATT::` prefix
2. Restore Base64 padding
3. Decode 20 bytes
4. Extract 4 fields per the byte layout
5. Verify HMAC

**Critical**: The old format used `::` as a delimiter within the payload. The
new format does NOT contain `::` in the payload — only the fixed prefix. A naive
`split('::')` will return only 2 parts instead of 3. The server must use the
new parser **exclusively** (or detect format via length).

### 4.3 Format Detection

The old token format is `IATT::<base64>::<hex64>` (~86 chars).
The new format is `IATT::<base64url>` (33 chars).

Server can detect by length:
```python
if len(token) == 33:
    # v7.0 binary format
elif len(token) > 40:
    # v6.x text format (deprecated)
```

### 4.4 Timestamp Validation

- Old format: milliseconds since epoch (13–14 digits)
- New format: **seconds** since epoch (10 digits in uint32 BE)
- The validation window (e.g., ±300s) remains the same
- **Adjust any server-side clock comparison logic** that expected milliseconds

### 4.5 API Endpoints (Unchanged)

The following endpoints are NOT affected by the QR format change:

| Endpoint | Purpose | Status |
|----------|---------|--------|
| `POST /api/v1/board/session/initiate` | Creates session, returns half1 + sessionId | Unchanged |
| `POST /api/v1/board/session/attendance/record-live` | Student QR scan submission | Unchanged — receives parsed token fields |
| `POST /api/v1/board/session/terminate` | Ends a session | Unchanged |
| `POST /api/v1/board/sync/vault` | Offline scan upload | Unchanged |

## 5. Attendance Completion Flow

The board-side flow after "End Session" is tapped:

```
┌─────────────────────┐
│  Attendance Screen  │
│  (End Session tap)  │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  _handleEndAttendance│
│  ─────────────────  │
│  1. setMode(full)   │
│  2. recordCompleted │  ← Isar local — no server call
│     Session(slotId) │
│  3. pushReplacement │  ← New IdleScreen(completedSession: true)
│     to IdleScreen   │
│  4. terminateSession│  ← POST /api/v1/board/session/terminate
│  5. clearSession()  │
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│  Idle Screen        │
│  ────────────────   │
│  Shows "COMPLETED"  │  ← on lock icon (was "SESSION COMPLETED")
│  Waits 3 seconds    │
│  Auto-minimizes     │  ← setMode(KioskMode.suspended)
│  to OS desktop      │
└─────────────────────┘
```

### Behavioural Changes for Server

1. **No new API needed** — the flow uses existing `terminateSession` endpoint
2. The board now **immediately terminates** the session when End Session is tapped
   (previously the termination was best-effort, fire-and-forget)
3. The `terminateSession` response should return promptly — the board waits for
   the HTTP response before clearing local session state

## 6. Migration Plan

### Prerequisites

1. Server team deploys updated QR parser **before** board-side deploy
2. Server must support both v6.x and v7.0 formats during transition

### Cutover Steps

| Step | What | Who |
|------|------|-----|
| 1 | Update server QR parser to handle v7.0 binary format | Server team |
| 2 | Add format detection (length check) for backwards compat | Server team |
| 3 | Deploy parser changes to production | Server team |
| 4 | Deploy v7.0 board build (this release) | Board team |
| 5 | Monitor for parsing errors in logs | Both |
| 6 | After stabilisation, remove v6.x parser code | Server team |

### Rollback

- If v7.0 tokens cause issues, the board can revert to the v6.x build
- Old boards continue to produce v6.x tokens — server must accept both
- No data loss: both formats carry the same semantic data (session, timestamp,
  nonce, HMAC)

## 7. Reference: Example Token

```
Input:        sessionId = "sess_abc123", secret = "dGhpcyBpcyBhIHRlc3QgaGFsZg...",
              timestampSec = 1711881234, nonce = [0xAB, 0xCD]

SHA256(sid):          3a6b... → first 6 bytes = [0x3a, 0x6b, ...]
Timestamp BE:         [0x66, 0x0b, 0x1c, 0x32]
Nonce:                [0xAB, 0xCD]
Header (12 bytes):    [0x3a, 0x6b, ..., 0x66, 0x0b, 0x1c, 0x32, 0xAB, 0xCD]
HMAC header[:8]:      [0x...]
Payload (20 bytes):   header + hmac
Base64URL (27 chars): yAyHFujnZgk8EqvN3_tq-3a8p4g
Token (33 chars):     IATT::yAyHFujnZgk8EqvN3_tq-3a8p4g
```

## 8. Reference: Test Vectors

Contact the board team for a full set of deterministic test vectors
(test vectors with known sessionId + secret + timestamp + nonce and their
expected token + valid HMAC).
