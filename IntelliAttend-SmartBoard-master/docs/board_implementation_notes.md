# SmartBoard Implementation Notes

**For:** Server Team  
**From:** Board Team  
**Date:** 2026-06-11  
**Context:** Response to `SMARTBOARD_INTEGRATION_CONTRACT_v3.md`

---

## 1. WebSocket Auth — Ticket vs JWT-Direct

### What the Contract Says

```
ws://<host>/api/v1/ws/board?session_id={sessionId}&token={jwt}
```

### What the Board Currently Implements

The board uses a **two-step ticket handshake**:

```
Step 1: POST /api/v1/websocket/ticket
        Authorization: Bearer <firebase_id_token>
        Response: { "ticket": "tkt_<32-hex>", "expires_in": 10 }

Step 2: ws://<host>/api/v1/websocket/session/{session_id}?ticket={ticket}
```

The backend implements this at `backend/python/main.py:258-325`.

### Question

Does the server team want to keep the ticket handshake, or should the board switch to the JWT-direct query-param approach? If switching, please confirm:

- The JWT used is the board's own backend JWT (not Firebase ID token)
- The endpoint path is `/api/v1/ws/board` (not `/api/v1/websocket/session/{session_id}`)

---

## 2. Room Name — `session_{session_id}` Rename

### What the Contract Says

> WebSocket broadcasts go to room `session_{session_id}`

### What the Current Backend Does

`ConnectionManager.broadcast()` at `main.py:165` uses the raw `session_id` as the room key — no `session_` prefix.

### Question

Has the `ConnectionManager` been updated to use `session_{session_id}` as the room key? If yes, the board must connect to `session_{session_id}`. If the room key remains `session_id` (bare), the contract line should be corrected.

---

## 3. Roster Endpoint

### What the Contract Says

```
GET /api/v1/student/section/{sectionId}
Authorization: Bearer <board_jwt>
```

### What the Board Currently Does

The board reads the `students` Firestore collection **directly** via `FirestoreRestClient.runQuery()`. There is no REST API call for roster loading.

### Question

- Is `GET /api/v1/student/section/{sectionId}` live now, or is it a planned endpoint?
- If planned, what is the ETA?
- Until it's live, should the board continue reading Firestore directly?

---

## 4. Offline Sync — Field Name

### What the Contract Says

The vault sync payload field is `records`:

```json
POST /api/v1/session/sync/vault
{
  "records": [ ... ]
}
```

### What the Board Currently Sends

The board sends `queued_scans` (`sync_manager.dart:67`):

```dart
final payload = scans.map((s) => {
  'student_id': s.studentId,
  'qr_payload': s.scannedTotpHash,
  'timestamp': s.scanTimestamp,
}).toList();
```

### What the Backend Currently Expects

`backend/python/models/board_auth_schema.py:40`:

```python
class VaultSyncRequest(BaseModel):
    session_id: str
    queued_scans: list[QueuedScan]
```

### Question

Which is final — `records` (contract) or `queued_scans` (current backend)? Need a single source of truth so we can align both sides.

---

## 5. `full_state_update` — Keepalive

### What the Contract Says

> Sent every 30 seconds as a keepalive + state refresh

```json
{
  "type": "full_state_update",
  "total_present": 12,
  "total_students": 60
}
```

### What the Board Currently Does

The board sends `{"type":"ping"}` every 30s (`WebsocketService._startPingTimer()`). The server responds with `{"type":"pong"}`.

### Question

- Is `full_state_update` replacing the ping/pong keepalive, or running alongside it?
- If the server pushes `full_state_update` on its own timer, the board should stop its client-side ping timer to avoid double keepalive.
- Should the board respond to `full_state_update` with an ack, or is it fire-and-forget?

---

## 6. Faculty Manual Marking — Confirmed

Understood: the faculty taps on **their own mobile app** (not the board's touchscreen). The board has no UI changes for this. It receives the identical `ATTENDANCE_MARKED` event and turns the seat green. No action needed from the board team.

---

## 7. Board-Side Updates Needed (For Awareness)

Once all questions above are resolved, the board team will ship these changes:

| Change | File |
|---|---|
| Add `studentEmail` and `markedBy` fields to `AttendanceMarkedEvent` | `websocket_service.dart` |
| Parse snake_case `student_email`, `student_name`, `marked_by` from WS events | `websocket_service.dart` |
| Add `studentEmail` to `PresentStudent` | `websocket_service.dart` |
| Read `student_email` (fall back to `student_id`) for seat lookup | `attendance_screen.dart` |
| Log seat-lookup misses instead of silent `null` | `attendance_screen.dart` |
| Switch roster fetch to `GET /api/v1/student/section/{sectionId}` | `student_service.dart` |
| Change `queued_scans` → `records` (if confirmed) | `sync_manager.dart` |
| Handle `full_state_update` message type | `attendance_screen.dart` |

---

## 8. Rollout Order

The `student_email` field is the critical dependency. The board must receive `student_email` in both `full_state_sync` and `ATTENDANCE_MARKED` for the seat grid to work.

**Recommended rollout:**

```
Phase 1: Server adds `student_email` to WS events
         (backward-compatible — old board ignores extra field)
         
Phase 2: Board ships update to read `student_email`
         (new board reads the field that's already present)
```

This way there is never a window where the seat grid is broken.
