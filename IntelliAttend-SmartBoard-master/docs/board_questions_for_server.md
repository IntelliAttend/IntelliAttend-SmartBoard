# Board Team — Open Questions for Server Team

**Date:** 2026-06-11  
**Document Status:** Waiting for server team response before implementation

---

## Q1: WebSocket Room Name

### Background

The contract specifies the board connects to room `session_{session_id}`. The current board connects to bare `session_id`. The current backend `ConnectionManager.broadcast()` also uses bare `session_id`.

### Question

Does the `ConnectionManager` now use `session_{session_id}` as the room key? If so, please confirm the board should connect to:

```
ws://<host>/api/v1/ws/board?session_id={sessionId}&token={jwt}
```

and the server broadcasts to `session_{sessionId}` (where `session_` is prepended server-side).

---

## Q2: `full_state_sync` — Does It Include `student_email`?

### Background

The `ATTENDANCE_MARKED` event now includes `student_email`. The board reads it. The `full_state_sync` payload in the architecture diagram shows `present_students` with only `{ student_id, student_name, status, recorded_at }` — no `student_email`.

### Question

Will `full_state_sync` also include `student_email` in each `present_students` entry? If not, the board falls back to `student_id` on reconnect, which requires `student_id` to equal the email. Please confirm one of:

- **Option A:** `full_state_sync` adds `student_email` field → board uses it directly
- **Option B:** `full_state_sync` keeps current format, but `student_id` is guaranteed to be the email → board uses `student_id` as fallback

---

## Q3: Roster Endpoint Availability

### Background

The contract specifies `GET /api/v1/student/section/{sectionId}`. The board currently reads Firestore directly.

### Question

Is this endpoint **live now**? If no, what is the expected delivery date, and should the board keep the Firestore direct-read as a fallback until then?

---

## Q4: `full_state_update` — Required or Optional?

### Background

The contract defines a `full_state_update` message sent every 30s as keepalive + state refresh. The board currently sends `{"type":"ping"}` every 30s and receives `{"type":"pong"}`.

### Question

Should the board:

- **A:** Remove its `ping` timer and rely solely on the server-pushed `full_state_update`?
- **B:** Keep `ping` alongside `full_state_update` (server sends both)?
- **C:** Ignore `full_state_update` entirely (it's optional/informational)?

---

## Q5: Offline Sync Field Name

### Background

The contract says the field is `records`. The current board sends `queued_scans`. The current backend expects `queued_scans`.

### Question

Which field name is final? We'll align both sides to match. Please pick one:

- `records` (as in contract)
- `queued_scans` (as in current backend code)
- Other (please specify)

---

## Summary: Board's Current Status

| Item | Status | Blocking On |
|---|---|---|
| `PresentStudent` — `studentEmail` field | ✅ Done | Nothing |
| `AttendanceMarkedEvent` — `studentEmail`, `markedBy`, snake_case | ✅ Done | Nothing |
| WS handler — reads `studentEmail ?? studentId` | ✅ Done | Nothing |
| WS room name | ❌ Needs confirmation | Q1 |
| `full_state_sync` `student_email` | ⚠️ Needs confirmation | Q2 |
| Roster endpoint | ⚠️ Needs confirmation | Q3 |
| `full_state_update` handling | ⚠️ Needs clarification | Q4 |
| Offline sync field name | ⚠️ Needs confirmation | Q5 |
