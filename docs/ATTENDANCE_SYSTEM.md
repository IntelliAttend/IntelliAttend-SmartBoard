# SmartBoard Attendance System — Server Contract

## Overview

The SmartBoard attendance flow has three distinct stages: **Save**, **Submit**, and **End Session**.  
Faculty marks attendance via a seat-grid UI; the board guarantees zero data loss and only allows
session termination after attendance has been persisted server-side.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ATTENDANCE LIFECYCLE                             │
├──────────┬──────────────┬──────────────────┬────────────────────────┤
│  STAGE   │  ACTION      │  PERSISTENCE     │  RELIABILITY           │
├──────────┼──────────────┼──────────────────┼────────────────────────┤
│  Save    │  Tap cells + │  Local Isar DB   │  Survives power loss,  │
│          │  SAVE button │  (on-device)     │  crash, reboot         │
├──────────┼──────────────┼──────────────────┼────────────────────────┤
│  Submit  │  SUBMIT btn  │  Server DB       │  WebSocket (primary)   │
│          │              │  (PostgreSQL)    │  REST API (fallback)   │
├──────────┼──────────────┼──────────────────┼────────────────────────┤
│  End     │  END SESSION │  Server status   │  Blocked until Submit  │
│  Session │  button      │  → ENDED         │  completes             │
└──────────┴──────────────┴──────────────────┴────────────────────────┘
```

---

## 1. WebSocket Protocol (Primary Path)

### 1.1 Board → Server: `attendance_submit`

Sent by the board when faculty taps **SUBMIT ATTENDANCE** after reviewing the split-view.

**Message format:**

```json
{
  "type": "attendance_submit",
  "session_id": "uuid-of-session",
  "present_emails": ["student1@college.edu", "student2@college.edu"],
  "absent_emails":  ["student3@college.edu", "student4@college.edu"]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | `string` | Must be exactly `"attendance_submit"` |
| `session_id` | `string` | UUID of the active session |
| `present_emails` | `string[]` | Student emails the faculty marked present |
| `absent_emails` | `string[]` | Student emails the faculty marked absent |

**Server must:**

1. Accept the message on the session WebSocket (`/api/v1/websocket/session/{session_id}`)
2. Upsert `SessionAttendee` rows in PostgreSQL:
   - If a `SessionAttendee` row already exists for `(session_id, student_id)`, update its `status` and `recorded_at`
   - If not, insert a new row with `status = PRESENT` or `status = ABSENT`
3. Broadcast confirmation to **all clients** connected to that session:

**Broadcast confirmation:**

```json
{
  "type": "attendance_submitted",
  "session_id": "uuid-of-session",
  "present_count": 28,
  "absent_count": 4,
  "timestamp": "2026-06-29T10:30:00.000Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | `string` | `"attendance_submitted"` |
| `session_id` | `string` | UUID of the session |
| `present_count` | `int` | Number of present students |
| `absent_count` | `int` | Number of absent students |
| `timestamp` | `string` | ISO 8601 UTC timestamp |

### 1.2 Server → Board: `attendance_submitted` (broadcast)

The board does **not** wait for this confirmation before navigating forward — it assumes
success after the send. This broadcast is primarily for observability and any secondary
clients (monitors, dashboards).

---

## 2. REST API (Fallback Path)

Used only when the WebSocket connection is unavailable.

### `POST /api/v1/board/session/attendance/submit`

**Auth:** Bearer token (Firebase ID token, same as other endpoints)  
**Content-Type:** `application/json`

**Request body:**

```json
{
  "session_id": "uuid-of-session",
  "present_emails": ["student1@college.edu"],
  "absent_emails":  ["student2@college.edu"]
}
```

**Response `200 OK`:**

```json
{
  "status": "success",
  "present": 28,
  "absent": 4
}
```

**Response `4xx/5xx`:** The board will show an error toast and allow retry.

**Server must:**
- Same upsert logic as the WebSocket path (idempotent)
- Also broadcast `attendance_submitted` via WebSocket so connected clients stay in sync

---

## 3. Session Termination

### `POST /api/v1/board/session/terminate`

Called only after attendance has been submitted. The board enforces this client-side —
if the faculty taps "End Session" before submitting, a dialog blocks them.

**Request body:**

```json
{
  "session_id": "uuid-of-session"
}
```

**Server must:**

1. Set `ActiveSession.status = ENDED` and `ended_at = now`
2. Broadcast `session_ended` via WebSocket
3. **Not** modify attendance records — those were already finalized by the `attendance_submit` call

---

## 4. Full State Sync

On WebSocket connect, the server sends `full_state_sync` which includes currently
present students. The board merges these with faculty manual marks.

```json
{
  "type": "full_state_sync",
  "session_id": "uuid-of-session",
  "total_present": 14,
  "present_students": [
    {
      "student_id": "student@college.edu",
      "student_name": "Aarav Sharma",
      "status": "PRESENT",
      "recorded_at": "2026-06-29T10:15:00.000Z"
    }
  ]
}
```

**Important:** The `full_state_sync` contains students who scanned QR but does **not**
contain faculty-submitted attendance. After `attendance_submit`, the server's
`SessionAttendee` table holds the complete picture (QR scans + faculty marks).

---

## 5. Database Model

### Table: `session_attendees`

```sql
CREATE TABLE session_attendees (
    id          VARCHAR(32) PRIMARY KEY,
    session_id  VARCHAR(64) NOT NULL REFERENCES active_sessions(session_id),
    student_id  VARCHAR(64) NOT NULL REFERENCES users(id),
    student_name VARCHAR(255),
    status      attendee_status NOT NULL DEFAULT 'PRESENT',  -- 'PRESENT' | 'ABSENT'
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_attendees_session ON session_attendees(session_id);
CREATE INDEX ix_attendees_student ON session_attendees(student_id);
```

### Enum: `attendee_status`

| Value | Meaning |
|-------|---------|
| `PRESENT` | Student was marked present (QR scan or faculty mark) |
| `ABSENT` | Student was marked absent by faculty |

### Upsert logic

Board submissions are **idempotent**. The same `(session_id, student_id)` can be
submitted multiple times; the server should update the existing row rather than
insert a duplicate:

```sql
INSERT INTO session_attendees (id, session_id, student_id, student_name, status, recorded_at)
VALUES (gen_random_uuid(), :session_id, :student_id, '', :status, NOW())
ON CONFLICT ON CONSTRAINT uq_attendee_session_student
DO UPDATE SET status = :status, recorded_at = NOW();
```

---

## 6. Data Flow — Complete Trace

```
FACULTY TAPS CELLS
  │  Local state only (_presentSeatIndices / _absentSeatIndices)
  ▼
SAVE ATTENDANCE (button)
  │  SessionManager.saveAttendanceSnapshot() → Isar (local)
  │  Survives power loss, crash, app restart
  ▼
SUBMIT ATTENDANCE (button)
  │
  ├── WebSocket connected? ──YES──→ send "attendance_submit" message
  │                                      Server upserts SessionAttendee rows
  │                                      Server broadcasts "attendance_submitted"
  │
  └── WebSocket down? ──────NO───→ POST /api/v1/board/session/attendance/submit
                                         Server upserts SessionAttendee rows
                                         Server broadcasts "attendance_submitted"
  │
  ▼
END SESSION (button)
  │
  ├── attendance submitted? ──NO──→ "Please submit first" dialog blocks
  │
  └── attendance submitted? ──YES──→ POST /api/v1/board/session/terminate
                                           Server sets status = ENDED
                                           Server broadcasts "session_ended"
  │
  ▼
SUMMARY SCREEN
    30s countdown → return to idle
```

---

## 7. Error Handling & Retry

| Scenario | Board behaviour |
|----------|-----------------|
| WebSocket send fails | Falls back to REST `POST /api/v1/board/session/attendance/submit` |
| REST call fails | Shows error snackbar, stays on submission screen, allows retry |
| Session terminate fails | Enqueues pending termination in `HeartbeatService` for retry |
| Power loss before Submit | `_restoreLocalSnapshot()` recovers attendance from Isar on reboot |
| Power loss after Submit | Attendance already persisted server-side. Session can be terminated via heartbeat timeout. |

---

## 8. Implementation Checklist for Server Team

- [ ] Handle `attendance_submit` message type in session WebSocket handler
- [ ] Add `POST /api/v1/board/session/attendance/submit` REST endpoint
- [ ] Implement idempotent upsert on `session_attendees` (not blind insert)
- [ ] Broadcast `attendance_submitted` to all session clients after processing
- [ ] Ensure `terminateSession` does **not** wipe attendance records
- [ ] Index `session_attendees` on `(session_id, student_id)` for upsert performance
- [ ] Validate `session_id` exists and session is in ACTIVE state before accepting submission
- [ ] Log all attendance submissions for audit (correlation ID from header `X-Request-ID`)
- [ ] Include `attendance_submitted` in `full_state_sync` response (future enhancement)
