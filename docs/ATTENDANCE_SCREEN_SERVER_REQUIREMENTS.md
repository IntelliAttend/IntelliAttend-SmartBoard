# Attendance Screen — Server Requirements

## Overview

The SmartBoard attendance screen displays a live seating grid. Each seat turns **lime green** when the server verifies a student scan. The board never writes attendance data — it only reads from Firestore `.snapshots()` and REST endpoints. The server owns all writes.

## Data Flow Diagram

```
Student QR Scan ──► Server ──► Firestore (attendees subcollection)
                                    │
                          .snapshots() listener
                                    │
                              SmartBoard UI
                           (seat turns green)
```

## 1. Firestore Collections Required

### 1.1 `students` Collection

One document per student. Read by SmartBoard via REST on session start.

| Field | Type | Example | Required |
|---|---|---|---|
| `roll_number` | string | `"22CS001"` | Yes (also stored as doc ID or in `__id`) |
| `name` | string | `"John Doe"` | Yes |
| `email` | string | `"john@example.com"` | **Critical** — used as the join key with attendee records |
| `section_id` | string | `"CS-A-2024"` | Yes |
| `class_id` | string | `"CS2024"` | No |
| `status` | string | `"active"` | Yes (SmartBoard filters by `status == 'active'`) |

**SmartBoard reads:**
```
FirestoreRestClient.runQuery(
  collection: 'students',
  where: { 'section_id': sectionId, 'status': 'active' },
)
```

**SmartBoard expects:** Returns list of maps with keys matching field names above. Document ID is injected as `__id`. The `email` field **must exactly match** the `student_id` field written by the server into the attendees subcollection — the join is case-insensitive (lowercased on both sides).

### 1.2 `ActiveSessions/{sessionId}` Document

Created by the server when a new session begins.

| Field | Type | Example | Required |
|---|---|---|---|
| `classroom_id` | string | `"CR102"` | Yes |
| `smart_board_id` | string | `"SB-003"` | Yes |
| `faculty_id` | string | `"FAC-042"` | Yes |
| `section_id` | string | `"CS-A-2024"` | Yes — used by board to load student roster |
| `status` | string | `"active"` or `"ended"` | Yes |
| `started_at` | timestamp | — | Yes |
| `ended_at` | timestamp | — | Only when status → `"ended"` |

**SmartBoard listens:** `.snapshots()` on `ActiveSessions/{sessionId}`
- When `status == "ended"` → board navigates back to idle screen

### 1.3 `ActiveSessions/{sessionId}/attendees` Subcollection

Written by the server when a student scan is verified. Read by SmartBoard via `.snapshots()`.

| Field | Type | Example | Required |
|---|---|---|---|
| `student_id` | string | `"john@example.com"` | **Critical** — must match `email` in `students` collection |
| `student_name` | string | `"John Doe"` | No |
| `roll_number` | string | `"22CS001"` | No |
| `timestamp` | timestamp | — | Yes (used for ordering) |
| `verified` | boolean | `true` | No |

**SmartBoard listener:**
```dart
FirebaseFirestore.instance
    .collection('ActiveSessions')
    .doc(widget.sessionId)
    .collection('attendees')
    .orderBy('timestamp', descending: true)
    .snapshots()
```

**Critical join logic** (`_updateAttendanceFromDatabase`):
```dart
final email = data['student_id'].toString().trim().toLowerCase();
// 1. Look up email in _emailToSeatIndex map
// 2. Map email → seat index → turn that seat lime green
```

The `student_id` field is the **sole join key** between the attendee record and the student's seat in the grid. It must match the `email` field in the `students` collection.

## 2. Server REST Endpoints Required

### 2.1 Scan Verification Endpoint

```
POST /api/v1/scan/verify
```

**Purpose:** Accept student scan payload, verify TOTP, write attendee doc.

**Request body:**
```json
{
  "session_id": "abc123",
  "qr_token": "IATT::<base64_payload>::<hmac_hex_signature>",
  "student_id": "john@example.com",
  "device_id": "optional_device_fingerprint"
}
```

**Verification logic (server-side):**
1. Parse `qr_token` → extract `session_id|timestamp_ms|nonce`
2. Look up `session_secret` for the session
3. Recompute HMAC-SHA256 — must match signature in token
4. Check timestamp is within the rotation window (typically 300s)
5. Check nonce has not been used (anti-replay)

**On success:**
- Write document to `ActiveSessions/{sessionId}/attendees/{autoId}`
  ```json
  {
    "student_id": "john@example.com",
    "student_name": "John Doe",
    "roll_number": "22CS001",
    "timestamp": "<server_time>",
    "verified": true
  }
  ```
- Return `200 { "status": "verified", "seat_index": 4 }`

**On failure:**
- `400` — invalid token
- `409` — already verified
- `429` — rate limited

### 2.2 Session Termination Endpoint

```
POST /api/v1/board/session/terminate
```

Already implemented. Called by SmartBoard when faculty taps "End Session" or auto-exit fires.

```json
{
  "session_id": "abc123"
}
```

Response: `200`

### 2.3 Session Start Endpoint (implied — verify with server team)

```
POST /api/v1/session/start
```

**Purpose:** Called by faculty mobile app or admin portal to create a session.

**On success:**
- Create `ActiveSessions/{sessionId}` document with `status: "active"`
- Return `session_id`, `session_secret` (for TOTP generation)

## 3. TOTP Token Format (SmartBoard QR)

The QR code displayed contains:

```
IATT::<base64_payload>::<hmac_signature>
```

Where `<base64_payload>` decodes to:
```
{session_id}|{timestamp_ms}|{4-byte-random-nonce}
```

- **session_id:** The active session ID
- **timestamp_ms:** Server-corrected Unix epoch ms
- **nonce:** 4 random bytes, base64 encoded (anti-replay)
- **signature:** HMAC-SHA256 of the base64 payload, hex-encoded

The server must:
1. Store `session_secret` when creating a session
2. Recompute HMAC on every scan to verify authenticity
3. Reject tokens older than the rotation window (configurable, default 300s)
4. Track used nonces to prevent replay within the same window

## 4. Seat Index Mapping Logic

The SmartBoard uses a simple array-index mapping:

```dart
// During roster load:
for (int i = 0; i < students.length; i++) {
  _emailToSeatIndex[students[i].email.trim().toLowerCase()] = i;
}

// On attendee update:
final email = data['student_id'].trim().toLowerCase();
if (_emailToSeatIndex.containsKey(email)) {
  int seatIndex = _emailToSeatIndex[email]!;
  // Turn seat[seatIndex] lime green
}
```

**Implication:** Seat indices are determined by the array order returned by the `students` collection query. If the server team wants a specific seat layout, they should control the order of student documents (e.g., by `roll_number` ascending).

## 5. Error Handling & Resilience

| Scenario | SmartBoard Behavior |
|---|---|
| Server writes wrong `student_id` | Attendee won't match any seat — no green highlight, logged as warning |
| Server never writes attendee doc | Seat stays grey — student appears absent |
| Server sets `status: "ended"` prematurely | Board immediately navigates back to idle |
| Server drops Firestore connection | Board's `.snapshots()` reconnects automatically (health monitor: 3min stale → reconnect) |
| Student roster fetch fails | Board falls back to generic seat codes ("S01", "S02", ...) — no email mapping, no green highlights |

## 6. Testing Checklist for Server Team

- [ ] Create `students` collection with sample documents
- [ ] Create `ActiveSessions/{id}` with `status: "active"`, correct `section_id`
- [ ] Write an attendee doc — SmartBoard seat should turn green within 1s
- [ ] Change `status` to `"ended"` — SmartBoard should navigate to idle
- [ ] Verify with wrong `student_id` (no email match) — no green, warning logged
- [ ] Verify TOTP token signature validation end-to-end
- [ ] Verify replay protection (same nonce rejected)
- [ ] Verify expired token (older than rotation window) rejected
