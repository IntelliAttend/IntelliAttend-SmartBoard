# SmartBoard Notification System — Server API Contract

> **Version:** 2.0  
> **Last Updated:** 2026-06-29  
> **Applies To:** IntelliAttend SmartBoard v5.4.0+  
> **Delivery:** WebSocket (real-time) + REST (history/fallback)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Priority Model — P0 through P3](#2-priority-model--p0-through-p3)
3. [Architecture & Data Flow](#3-architecture--data-flow)
4. [WebSocket Delivery (Primary)](#4-websocket-delivery-primary)
   - 4.1 Connection Flow
   - 4.2 Notification Event Contract (v1)
   - 4.3 All-Clear Events
   - 4.4 Acknowledgement on Reconnect
5. [REST API Endpoints](#5-rest-api-endpoints)
   - 5.1 `GET /api/v1/board/notifications` — Fetch History
   - 5.2 `PATCH /api/v1/user/notifications/{id}/acknowledge` — Acknowledge
   - 5.3 `PATCH /api/v1/user/notifications/{id}/read` — Mark Read
   - 5.4 `POST /api/v1/websocket/ticket` — WS Auth Ticket
   - 5.5 `POST /api/v1/admin/board/{board_id}/notification` — Admin Push
6. [Display Mode Routing](#6-display-mode-routing)
7. [Notification Lifecycle](#7-notification-lifecycle)
8. [Attachment & Document Support](#8-attachment--document-support)
9. [Authentication & Headers](#9-authentication--headers)
10. [Error Handling & Retry](#10-error-handling--retry)
11. [Testing Guide](#11-testing-guide)

---

## 1. Overview

The SmartBoard displays real-time notifications pushed from the server. The board **never writes** to notification data — it only **reads** and **acknowledges**.

**Two delivery channels:**

| Channel | Purpose | Latency | Reliability |
|---------|---------|---------|-------------|
| **WebSocket** (primary) | Real-time push of new events | Sub-second | Persistent connection with auto-reconnect |
| **REST** (fallback/history) | Load notification history on boot, pull-to-refresh | One-shot | Circuit breaker + 3 retries |

**Key principles:**
- Server pushes → board receives (never polls)
- Each notification has a unique `event_id` for deduplication
- Dismissed notifications are re-acknowledged on WebSocket reconnect
- Notifications can carry document attachments (PDF, DOCX, images, etc.)

---

## 2. Priority Model — P0 through P3

| Priority | Enum Value | `display_mode` | UI Treatment | Dismissable | Timer |
|----------|-----------|----------------|--------------|-------------|-------|
| **P0 — Emergency** | `emergency` | `full_screen` | Full-screen blur overlay with amber border arc, countdown, emergency details (location, safe exit, assembly point, steps) | Only after countdown expires | 60s (configurable via `duration_seconds`, min 10s) |
| **P1 — High** | `high` | `overlay` | Same blur overlay as P0 but no emergency details | Only after countdown expires | 60s (configurable via `duration_seconds`, min 10s) |
| **P2 — Normal** | `normal` | `reminder` | Same overlay widget, teal accent, no countdown | Immediately | None |
| **P3 — Low** | `low` | `default` | Notification inbox + animated top-right popdown banner (5s auto-dismiss) | Immediately or auto-dismiss after 5s | 5s popdown |

### Visual Differentiation

| Priority | Icon | Colour | Border Arc | Behaviour |
|----------|------|--------|------------|-----------|
| P0 | ⚠️ warning triangle | Amber `#F59E0B` | Solid amber progress arc | Full-screen takeover with emergency info |
| P1 | ⚠️ warning triangle | Amber `#F59E0B` | Solid amber progress arc | Blur overlay, no emergency details |
| P2 | ℹ️ info circle | Teal `#14B8A6` | None | Blur overlay, instant dismiss |
| P3 | 🔔 bell | Teal `#14B8A6` | None | Popdown banner + inbox |

---

## 3. Architecture & Data Flow

```
┌─────────────┐        WebSocket (real-time)        ┌──────────────┐
│   Server    │ ──────────────────────────────────▶  │  SmartBoard  │
│  (Backend)  │                                      │  (Flutter)   │
│             │                                      │              │
│  Admin UI   │◀──── PATCH /acknowledge ────────────│  UI Display  │
│  sends P0-  │                                      │  P0/P1/P2    │
│  P3 events  │◀──── PATCH /read ──────────────────│  overlay /   │
│             │                                      │  P3 popdown  │
│  REST API   │────── GET /notifications ──────────▶│              │
│  (history)  │       (on boot / refresh)            │              │
└─────────────┘                                      └──────────────┘
```

**Event flow for a new notification:**

1. Admin/faculty creates notification via backend admin panel or API
2. Server delivers it via the board's persistent WebSocket connection
3. Flutter `WebsocketService` receives the message, parses into `NotificationEvent`
4. `NotificationListenerService.handleNotificationEvent()` applies:
   - Dedup by `event_id` (reconnect safety)
   - Dismissed-ID check (skip previously dismissed)
   - All-clear detection (restore normal UI)
   - Display-mode routing (P0→full-screen overlay, P1→overlay, P2→reminder overlay, P3→inbox+popdown)
5. The appropriate UI widget renders the notification
6. When user taps DISMISS, board sends `PATCH /acknowledge` to server

---

## 4. WebSocket Delivery (Primary)

### 4.1 Connection Flow

```
┌──────────┐          ┌──────────┐          ┌──────────┐
│  Board   │          │  API     │          │  WS      │
│  Flutter │          │  Server  │          │  Server  │
└────┬─────┘          └────┬─────┘          └────┬─────┘
     │                     │                     │
     │  POST /websocket    │                     │
     │  /ticket            │                     │
     │────────────────────▶│                     │
     │                     │                     │
     │  { ticket: "tkt_.." }                     │
     │◀────────────────────│                     │
     │                     │                     │
     │  WS connect         │                     │
     │  /board/{boardId}   │                     │
     │  ?ticket=tkt_...    │────────────────────▶│
     │                     │                     │
     │  { type: "board_connected",              │
     │    board_id: "IASB-4208" }               │
     │◀──────────────────────────────────────────│
     │                     │                     │
     │  GET /active-session│                     │
     │────────────────────▶│                     │
     │                     │                     │
     │  (notification events stream...)          │
     │◀──────────────────────────────────────────│
     │                     │                     │
```

**Steps:**

1. Board requests a short-lived ticket: `POST /api/v1/websocket/ticket`
   - Response: `{ "ticket": "tkt_<uuid>", "expires_in": 10 }`
   - Ticket is valid for 10 seconds (one-time use)
2. Board connects via WebSocket to:
   ```
   ws[s]://<host>/api/v1/websocket/board/<boardId>?ticket=<ticket>
   ```
3. On success, server sends `board_connected` confirmation
4. Board checks for active session via `GET /api/v1/board/active-session`
5. Board enters listening mode — all notification events arrive over this connection

**Reconnection:**
- On disconnect, board retries with exponential backoff (1s, 2s, 4s, 8s, max 30s)
- On reconnect: `reAcknowledgeDismissed()` re-sends acks for all dismissed `notification_id`s
- Already-processed `event_id`s are skipped via local dedup set

### 4.2 Notification Event Contract (v1)

Sent from **server → board** over the board WebSocket connection.

**JSON Schema:**

```json
{
  "event_type": "notification",
  "event_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "version": 1,
  "institution_id": "inst-123",
  "timestamp": "2026-06-29T12:00:00.000Z",
  "payload": {
    "notification_id": "n-87654321-1234-5678-abcd-ef0987654321",
    "version": 1,
    "priority": "P0",
    "notification_type": "emergency",
    "display_mode": "full_screen",
    "severity": null,
    "title": "FIRE EMERGENCY",
    "body": "Fire reported in Block B, 2nd Floor. Evacuate immediately.",
    "requires_acknowledgement": true,
    "duration_seconds": 60,
    "data": {
      "attachment_url": "https://storage.example.com/map.pdf",
      "attachment_name": "Evacuation_Map.pdf",
      "attachment_type": "application/pdf",
      "attachment_size": 245760
    }
  }
}
```

**Field reference:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `event_type` | `string` | Yes | Always `"notification"` |
| `event_id` | `string` (UUID) | Yes | Unique event ID for deduplication |
| `version` | `int` | Yes | Schema version (`1`) |
| `institution_id` | `string` | Yes | Institution/organization identifier |
| `timestamp` | `string` (ISO 8601) | Yes | When the event was created |
| `payload.notification_id` | `string` (UUID) | Yes | Server-assigned notification ID (used for ack) |
| `payload.version` | `int` | Yes | Payload schema version (`1`) |
| `payload.priority` | `string` | Yes | One of: `"P0"`, `"P1"`, `"P2"`, `"P3"`, or `"emergency"`, `"high"`, `"normal"`, `"low"` |
| `payload.notification_type` | `string` | Yes | See notification types table below |
| `payload.display_mode` | `string` | Yes | One of: `"full_screen"`, `"overlay"`, `"reminder"`, `"default"` |
| `payload.severity` | `int?` | No | Numeric severity level (reserved for future use) |
| `payload.title` | `string?` | No | Headline text |
| `payload.body` | `string?` | No | Message body |
| `payload.requires_acknowledgement` | `boolean` | No | Whether server expects a `PATCH /acknowledge` call (default: `false`) |
| `payload.duration_seconds` | `int?` | No | Auto-dismiss timer (P0/P1 minimum 10s; P3 default 5s) |
| `payload.data` | `object?` | No | Extended data map (see attachments below) |

**`notification_type` values:**

| Value | UI Icon | Colour | Use Case |
|-------|---------|--------|----------|
| `all_clear` | ✅ green check | Green | Emergency resolved — restores normal UI |
| `emergency` | ⚠️ warning | Amber | Fire, evacuation, lockdown |
| `alert` | ⚠️ warning | Amber | System alerts, warnings |
| `warning` | ⚠️ warning | Amber | General warnings |
| `system` | 🔄 system_update | Teal | Software updates, config changes |
| `attendance` | ✅ fact_check | Lime green | Attendance events |
| `message` | 💬 message | Blue | Admin/faculty messages |
| `info` | 🔔 notifications | Teal | Generic informational |

**`data` map fields (optional):**

| Field | Type | Description |
|-------|------|-------------|
| `attachment_url` | `string` | URL to downloadable document |
| `attachment_name` | `string` | Human-readable file name |
| `attachment_type` | `string` | MIME type (e.g. `"application/pdf"`) |
| `attachment_size` | `int` | File size in bytes |

### 4.3 All-Clear Events

An **all-clear** notification is a special event that cancels an active emergency.

**Detection logic (Flutter):**
```dart
bool get isAllClear =>
    notification_type == "all_clear" &&
    display_mode == "full_screen";
```

**Behaviour:**
- Dismisses any active P0 emergency overlay
- Removes all emergency notifications from cache (archives in history)
- Shows a green toast banner: *"All Clear — Emergency resolved"*
- Auto-dismisses the toast after 3 seconds
- Emits on the `onAllClear` stream for any custom listeners

### 4.4 Acknowledgement on Reconnect (Contract §4.3)

When the WebSocket reconnects after a transient disconnect:

1. `reAcknowledgeDismissed()` iterates `_dismissedNotificationIds` set
2. For each ID, re-sends `PATCH /api/v1/user/notifications/{id}/acknowledge`
3. Incoming notification events with already-processed `event_id` values are silently skipped
4. Incoming events with previously dismissed `notification_id` values are skipped and re-acknowledged

This ensures the server always knows which notifications the board has handled, even across disconnections.

---

## 5. REST API Endpoints

### 5.1 GET /api/v1/board/notifications

Fetch notification history for this board (used on boot and pull-to-refresh).

**Request:**
```
GET /api/v1/board/notifications
Authorization: Bearer <firebase-id-token>
X-Device-ID: <hardware-fingerprint>
X-Request-ID: <correlation-uuid>
```

**Success Response (200):**
```json
{
  "data": [
    {
      "notification_id": "n-87654321-1234-5678-abcd-ef0987654321",
      "title": "FIRE EMERGENCY",
      "body": "Fire reported in Block B, 2nd Floor.",
      "type": "emergency",
      "priority": "emergency",
      "display_mode": "full_screen",
      "timestamp": "2026-06-29T12:00:00.000Z",
      "read": false,
      "requires_acknowledgement": true,
      "duration_seconds": 60,
      "attachment_url": "https://...",
      "attachment_name": "map.pdf",
      "attachment_type": "application/pdf",
      "attachment_size": 245760,
      "location": "Block B, Room 204",
      "safe_exit": "NORTH-EAST",
      "assembly_point": "Main Ground Assembly Point",
      "precautionary_steps": [
        "Remain Calm — Do not panic or run",
        "Alert Others — Inform nearby students and staff",
        "Exit Immediately — Use nearest fire exit",
        "Do Not Use Elevators — Use stairwell only",
        "Report to Assembly Point — Main ground area"
      ]
    }
  ]
}
```

**Error Responses:**

| Code | Meaning |
|------|---------|
| 401 | Unauthorized (token expired/invalid) |
| 404 | Board not found / no notifications |
| 500 | Server error (retryable) |

### 5.2 PATCH /api/v1/user/notifications/{notification_id}/acknowledge

Sent when the user taps DISMISS on a P0/P1/P2 overlay notification. Creates an audit trail.

**Request:**
```
PATCH /api/v1/user/notifications/n-87654321/acknowledge
Authorization: Bearer <firebase-id-token>
```

**Success Response (200):**
```json
{ "status": "acknowledged" }
```

**Notes:**
- Called for P0, P1, and P2 notifications on dismiss
- Also called on WebSocket reconnect for previously dismissed notifications
- Failure is non-critical (logged but does not block the UI)

### 5.3 PATCH /api/v1/user/notifications/{notification_id}/read

Sent when the user taps a P3 notification in the inbox (marks as read).

**Request:**
```
PATCH /api/v1/user/notifications/n-87654321/read
Authorization: Bearer <firebase-id-token>
```

**Success Response (200):**
```json
{ "status": "read" }
```

### 5.4 POST /api/v1/websocket/ticket

Request a one-time WebSocket authentication ticket.

**Request:**
```
POST /api/v1/websocket/ticket
Authorization: Bearer <firebase-id-token>
```

**Success Response (200):**
```json
{
  "ticket": "tkt_a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "expires_in": 10
}
```

**Notes:**
- Ticket is valid for 10 seconds
- Single-use only
- Must be passed as `?ticket=` query parameter on WebSocket connect

### 5.5 POST /api/v1/admin/board/{board_id}/notification

Admin endpoint to push a notification to a specific board via its WebSocket connection.

**Request:**
```
POST /api/v1/admin/board/IASB-4208/notification
Authorization: Bearer <admin-token>
Content-Type: application/json
```

**Body:**
```json
{
  "priority": "P1",
  "notification_type": "alert",
  "display_mode": "overlay",
  "title": "Faculty Meeting Reminder",
  "body": "All faculty members are requested to attend the urgent meeting in Conference Room A at 12:00 PM.",
  "duration_seconds": 60,
  "requires_acknowledgement": true
}
```

**Success Response (200):**
```json
{
  "status": "delivered",
  "notification_id": "n-87654321-1234-5678-abcd-ef0987654321"
}
```

---

## 6. Display Mode Routing

The `display_mode` field in the payload determines the UI treatment:

```
payload.display_mode
│
├─ "full_screen" ──▶ P0 Emergency overlay
│   - Blur backdrop
│   - Warning triangle icon (amber)
│   - Amber progress arc border (60s countdown)
│   - Emergency details (location, safe exit, assembly point, steps)
│   - DISMISS button enabled only after timer expires
│   - No "0s" shown when expired
│
├─ "overlay" ──▶ P1 High overlay
│   - Blur backdrop
│   - Warning triangle icon (amber)
│   - Amber progress arc border (60s countdown)
│   - No emergency details
│   - DISMISS button enabled only after timer expires
│   - No "0s" shown when expired
│
├─ "reminder" ──▶ P2 Normal overlay
│   - Blur backdrop
│   - Info circle icon (teal)
│   - No progress arc border
│   - DISMISS button enabled immediately
│   - No countdown
│
└─ "default" (or missing) ──▶ P3 Low
    - Adds to notification inbox list
    - Shows animated top-right popdown banner
    - Auto-dismisses after 5 seconds
    - Tappable → opens NotificationsScreen
```

---

## 7. Notification Lifecycle

```
                     ┌──────────────────┐
                     │  Server creates  │
                     │  notification    │
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  WS delivers to  │  ◀── Primary path
                     │  board           │
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  Dedup check     │
                     │  (by event_id)   │
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  Dismissed-ID    │
                     │  check           │─── If dismissed → re-ack and skip
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  All-clear?      │─── Yes → restore UI, archive
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  Route by        │
                     │  display_mode    │─── P0/P1/P2 → overlay; P3 → inbox
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  Display on      │
                     │  SmartBoard      │
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  User taps       │
                     │  DISMISS / tap   │
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  PATCH /acknowl- │
                     │  edge            │
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  Removed from    │
                     │  active display  │
                     └──────────────────┘
```

### Key Timings

| Event | Duration | Configurable |
|-------|----------|--------------|
| P0/P1 countdown | 60s | Via `duration_seconds` (min 10s) |
| P3 popdown auto-dismiss | 5s | Via `displayDuration` in code |
| All-clear toast | 3s | Hardcoded |
| Notification cache TTL | Until dismissed or new day | Resets on new day |

### Queue Behaviour (P3 during non-idle screens)

When the board is on a non-idle screen (e.g. attendance in progress):
- P0/P1/P2 notifications fire immediately (bypass queue)
- P3 notifications are queued in `_notificationQueue`
- When returning to the idle screen, `drainQueue()` emits all queued P3s sequentially
- Each P3 popdown auto-dismisses before the next one appears

---

## 8. Attachment & Document Support

Notifications can carry file attachments via the `data` map in the payload.

### Server Requirements

1. Upload the file to cloud storage (Firebase Storage / GCS / S3 / R2)
2. Generate a presigned/download URL
3. Include in the notification payload:
   ```json
   "data": {
     "attachment_url": "https://storage.example.com/file.pdf",
     "attachment_name": "Lecture_Notes_Week10.pdf",
     "attachment_type": "application/pdf",
     "attachment_size": 2457600
   }
   ```

### Supported File Types

| Type | MIME Pattern | Board Handling |
|------|-------------|----------------|
| PDF | `application/pdf` | Built-in PDF viewer (pinch-zoom, page nav, text selection) |
| Word | `application/vnd.openxmlformats-officedocument.wordprocessingml.*` | System default app (Word) |
| Excel | `application/vnd.openxmlformats-officedocument.spreadsheetml.*` | System default app (Excel) |
| PowerPoint | `application/vnd.openxmlformats-officedocument.presentationml.*` | System default app (PowerPoint) |
| Images | `image/*` | System default app |
| Text | `text/*` | System default app |
| Other | Any | System default app |

### Attachment UI

- Notifications with attachments show a teal-bordered **attachment chip**
- Tapping the notification downloads the file to local cache (`{appDocDir}/documents/`)
- Downloaded once; re-opening is instant (cached locally)
- Offline: PDFs open in built-in viewer; other files if available locally

---

## 9. Authentication & Headers

### Base URL

```
https://api-dev.balaseetharamanjaneyulu.com
```

Configurable via `API_BASE_URL` in `.env`.

### Every Request

| Header | Value | Required | Description |
|--------|-------|----------|-------------|
| `Authorization` | `Bearer <firebase-id-token>` | Yes | Firebase ID token (auto-refreshed) |
| `Content-Type` | `application/json` | Yes | For requests with body |
| `X-Device-ID` | `<hardware-fingerprint>` | No | Board hardware fingerprint |
| `X-Request-ID` | `<uuid>` | Yes | Correlation ID for tracing |

### Authentication Flow

```
Board                                     Firebase                     Backend
  │                                         │                           │
  │  1. Sign in with email/password          │                           │
  │  (board ID → email mapping)             │                           │
  │────────────────────────────────────────▶│                           │
  │                                         │                           │
  │  2. Firebase ID token (JWT) ◀───────────│                           │
  │◀────────────────────────────────────────│                           │
  │                                         │                           │
  │  3. API call with Bearer token ────────▶│                           │
  │                                         │  firebase_admin.auth      │
  │                                         │  .verify_id_token(token)  │
  │                                         │──────────────────────────▶│
  │                                         │  user info ◀─────────────│
  │  4. Response ◀──────────────────────────│                           │
  │◀────────────────────────────────────────│                           │
```

The backend uses `firebase_admin.auth().verify_id_token()` to validate tokens. No secondary JWT or API key is needed.

### Admin Authentication

Admin endpoints (like pushing notifications) require admin-level Firebase claims or a separate admin API key.

---

## 10. Error Handling & Retry

### Circuit Breaker (Per Endpoint)

| Parameter | Value |
|-----------|-------|
| Failure threshold | 5 consecutive failures |
| Cooldown | 60 seconds |
| State | Closed → Open (after 5 failures) → Half-Open (after cooldown) |

### Retry Policy

| Parameter | Value |
|-----------|-------|
| Max retries | 3 |
| Backoff | Exponential: 1s, 2s, 4s |
| Retryable errors | 5xx, `SocketException`, `TimeoutException`, `ClientException` |
| Non-retryable | 4xx (especially 401, 404) |

### Error Response Format

Server errors should follow this structure:

```json
{
  "detail": "Human-readable error description",
  "error_code": "ERROR_CODE",
  "status": 400
}
```

Fields parsed for user display: `detail` > `message` > `error`

---

## 11. Testing Guide

### Prerequisites

- Board registered and connected (WebSocket active)
- `.env` configured with `API_BASE_URL` and Firebase credentials

### Test Scenarios

| # | Test | How to Trigger | Expected Result |
|---|------|----------------|-----------------|
| 1 | P0 full-screen emergency | Push via `POST /api/v1/admin/board/{id}/notification` with `display_mode: "full_screen"`, `priority: "P0"` | Full-screen blur overlay with amber border, 60s countdown, DISMISS disabled |
| 2 | P1 overlay notification | Push with `display_mode: "overlay"`, `priority: "P1"` | Blur overlay with amber border, countdown, no emergency details |
| 3 | P2 reminder | Push with `display_mode: "reminder"`, `priority: "P2"` | Blur overlay with teal icon, immediate dismiss, no countdown |
| 4 | P3 default notification | Push with `display_mode: "default"`, `priority: "P3"` | Animated popdown banner + inbox entry, auto-dismiss after 5s |
| 5 | All-clear | Push with `notification_type: "all_clear"`, `display_mode: "full_screen"` | Emergency clears, green toast appears, normal UI restores |
| 6 | Acknowledgement | Dismiss P1 notification | Board sends `PATCH /acknowledge`; check server logs |
| 7 | Reconnect ack | Disconnect network, dismiss notification, reconnect | On reconnect, board re-sends ack for dismissed notification |
| 8 | Dedup | Push same event twice with same `event_id` | Second event silently ignored |
| 9 | Attachment | Push notification with `data.attachment_url` | Attachment chip visible; tap to download and open |
| 10 | History | Call `GET /api/v1/board/notifications` | Returns list of past notifications for this board |

### Debug Endpoints (Development Only)

The Flutter app has built-in debug buttons for testing all priority levels (visible in `kDebugMode` only):
- **Emergency (P0)** — injects a full emergency notification with all fields
- **P1 Blur** — injects a high-priority overlay
- **P-2** — injects a normal-priority reminder
- **P3 Inbox** — injects a low-priority notification to inbox+popdown

---

## Appendix A: Field Name Constants

The Flutter client references JSON field names through `ApiSchema` constants. These must match the server's JSON keys.

| Constant | JSON Key |
|----------|----------|
| `fieldNotificationId` | `notification_id` |
| `fieldTitle` | `title` |
| `fieldBody` | `body` |
| `fieldType` | `type` |
| `fieldTimestamp` | `timestamp` |
| `fieldPriority` | `priority` |
| `fieldRead` | `read` |
| `fieldDisplayMode` | `display_mode` |
| `fieldRequiresAcknowledgement` | `requires_acknowledgement` |
| `fieldDurationSeconds` | `duration_seconds` |
| `fieldAttachmentUrl` | `attachment_url` |
| `fieldAttachmentName` | `attachment_name` |
| `fieldAttachmentType` | `attachment_type` |
| `fieldAttachmentSize` | `attachment_size` |
| `fieldLocation` | `location` |
| `fieldSafeExit` | `safe_exit` |
| `fieldAssemblyPoint` | `assembly_point` |
| `fieldPrecautionarySteps` | `precautionary_steps` |

## Appendix B: Full Notification JSON Example (Emergency)

```json
{
  "event_type": "notification",
  "event_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "version": 1,
  "institution_id": "inst-university-123",
  "timestamp": "2026-06-29T14:30:00.000Z",
  "payload": {
    "notification_id": "n-87654321-1234-5678-abcd-ef0987654321",
    "version": 1,
    "priority": "P0",
    "notification_type": "emergency",
    "display_mode": "full_screen",
    "severity": 5,
    "title": "FIRE EMERGENCY — Block B",
    "body": "Fire reported in Block B, 2nd Floor (Room 204). All occupants must evacuate immediately.",
    "requires_acknowledgement": true,
    "duration_seconds": 60,
    "data": {
      "attachment_url": "https://storage.example.com/evacuation_map_building_b.pdf",
      "attachment_name": "Block_B_Evacuation_Map.pdf",
      "attachment_type": "application/pdf",
      "attachment_size": 5242880
    }
  }
}
```
