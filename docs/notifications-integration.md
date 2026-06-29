# Notification Integration — Server Team Guide

> **⚠️ ARCHIVED — This document describes the legacy Firestore-based approach.**
> The production notification system now uses **WebSocket delivery**.
> See **[NOTIFICATION_SYSTEM_API.md](./NOTIFICATION_SYSTEM_API.md)** for the current contract.

## Overview

The SmartBoard displays real-time notifications (alerts, attendance updates, system messages, admin messages) pushed from the backend via **WebSocket**. The board **never writes** to the notifications data — it only reads and acknowledges.

> **Legacy note:** An earlier prototype used Firestore `.snapshots()` for delivery. The codebase has since moved to WebSocket. The `forceSync()` method now calls `GET /api/v1/board/notifications` (REST) as a fallback for history/pull-to-refresh.

---

## 1. Collections & Documents

### Collection: `notifications`

Each document in this collection represents a notification targeted at one or more smart boards.

**Document fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `smart_board_id` | `string` | **Yes** | Board identifier used for query filtering (e.g. `"IASB-4208"`) |
| `title` | `string` | No | Headline text. Defaults to `"Notification"` if missing. |
| `body` | `string` | No | Full notification message body. |
| `type` | `string` | No | Category (see table below). Defaults to `"info"`. |
| `timestamp` | `timestamp` | No | When the notification was created. Falls back to `created_at`. |
| `created_at` | `timestamp` | No | Fallback if `timestamp` is not set. |
| `read` | `boolean` | No | Read/unread status. Defaults to `false`. |
| `attachment_url` | `string` | No | URL to a downloadable document (PDF, image, etc.). Triggers the board's document viewer. |
| `attachment_name` | `string` | No | Human-readable file name to display (e.g. `"Lecture_Notes_Week10.pdf"`). |
| `attachment_type` | `string` | No | MIME type (e.g. `"application/pdf"`, `"image/png"`). Used for icon selection. |
| `attachment_size` | `number` | No | File size in bytes. Displayed as human-readable (KB/MB) in the UI. |

**Type values and their UI rendering:**

| `type` value | Icon | Colour | Use Case |
|---|---|---|---|
| `"alert"` / `"warning"` | ⚠️ warning | Orange | System alerts, warnings |
| `"attendance"` | ✅ fact_check | Lime green | Attendance events (matches app's accent colour) |
| `"system"` | 🔄 system_update | Teal | Software updates, config changes |
| `"message"` | 💬 message_outlined | Blue | Admin/faculty messages |
| (any other) | 🔔 notifications_none | Teal | Generic fallback |

---

## 2. How the SmartBoard Reads Notifications

### Primary Path: Native `.snapshots()` (real-time, ~0 reads idle)

```dart
FirebaseFirestore.instance
    .collection('notifications')
    .where('smart_board_id', isEqualTo: boardId)
    .orderBy('created_at', descending: true)
    .snapshots(includeMetadataChanges: false)
```

- **Cost:** Bills 1 read per document *change* only. Idle boards cost $0.
- **Latency:** Push-based — the server pushes changes to the board immediately.
- **Auth context:** No `firebase_auth` plugin → `request.auth` is **null** in security rules.

### Fallback Path: Manual `forceSync()` (REST, one-shot)

```dart
FirestoreRestClient.runQuery(
  collection: 'notifications',
  where: {'smart_board_id': boardId},
)
```

- **Called:** Pull-to-refresh, button press, or admin trigger.
- **Auth context:** Sends a **Bearer token** from Identity Toolkit (Firebase `signInWithCustomToken`) in the `Authorization` header. → `request.auth` is **non-null**.
- **Cost:** Bills 1 read per document fetched, per call.

---

## 3. Firestore Security Rules — The Issue

The board cannot read the `notifications` collection because no security rule grants access to it. The app handles this gracefully (logs warning, shows empty list), but notifications never arrive.

### Option A — Public read (recommended for real-time)

Because the query already filters by `smart_board_id`, a board can only fetch its own notifications. The data is not sensitive (just UI messages to the board).

```firestore
service cloud.firestore {
  match /databases/{database}/documents {

    // Allow unauthenticated read on notifications collection.
    // The board's query already restricts to its own smart_board_id.
    match /notifications/{doc} {
      allow read: if true;
    }

    // Keep other collections locked down.
    match /timetable_slots/{doc} {
      allow read: if true;
    }

    match /ActiveSessions/{session} {
      allow read: if request.auth != null;
    }
  }
}
```

**Effect:**
| Path | Native `.snapshots()` | REST `forceSync()` |
|---|---|---|
| `notifications` | ✅ Works (real-time) | ✅ Works (one-shot) |

### Option B — Authenticated REST-only

If public read is unacceptable, the rule can require auth:

```firestore
match /notifications/{doc} {
  allow read: if request.auth != null;
}
```

**Effect:**
| Path | Native `.snapshots()` | REST `forceSync()` |
|---|---|---|
| `notifications` | ❌ blocked (no firebase_auth) | ✅ Works (one-shot only) |

With Option B, the board can never receive real-time notifications. The user must manually trigger `forceSync()` to check for new messages. **This is not recommended** — it defeats the real-time purpose and still costs reads on each poll.

---

## 4. What the Backend Server Must Do

### Write notifications to Firestore

The backend (or a Cloud Function) writes documents to the `notifications` collection:

```json
{
  "smart_board_id": "IASB-4208",
  "title": "Class CSE-AIML-A starts in 5 min",
  "body": "Prepare for Period 3 with Dr. Smith",
  "type": "attendance",
  "created_at": "2026-05-20T11:00:00Z",
  "read": false
}
```

The board's Firestore listener picks this up within seconds (push-based) and displays it in the Notifications screen.

### What NOT to do

- **No custom API endpoint needed** — the board reads directly from Firestore.
- **No auth integration needed** — the board uses its Firebase API key for native access.
- **No delivery confirmation needed** — the `read` field is for the UI only; the backend does not need to track read status.

---

## 5. Document Sharing (Share-to-Board)

Users (faculty/students) can share documents to the SmartBoard by writing a notification with attachment fields to Firestore. This enables a **"Share to SmartBoard"** flow from phones.

### Example Document Notification

```json
{
  "smart_board_id": "IASB-4208",
  "title": "Lecture Notes — Week 10",
  "body": "Dr. Smith shared a PDF with the class.",
  "type": "message",
  "created_at": "2026-06-10T10:30:00Z",
  "read": false,
  "attachment_url": "https://storage.googleapis.com/.../lecture_week10.pdf",
  "attachment_name": "CSE-AIML_Week10_Notes.pdf",
  "attachment_type": "application/pdf",
  "attachment_size": 2457600
}
```

### How the Board Handles Documents (Prototyping Mode)

> **Status:** Prototyping / dev-only. Gated behind `ENABLE_DOCUMENTS=true` in `.env`.
> Document sharing is **not enabled** in production builds.

1. **Detection:** Notifications with a non-empty `attachment_url` are marked with a teal-bordered attachment chip in the UI.
2. **Tap to Download:** When the user taps the notification, the board downloads the file to a local cache (`{appDocDir}/documents/`).
3. **Viewing:**
   - **PDFs** are opened in `DocumentViewerScreen` (built on `pdfrx`/PDFium) with pinch-zoom, page navigation, and text selection.
   - **All other file types** (DOCX, PPTX, XLSX, TXT, MD, HTML, PNG, etc.) are opened with the **system default application** via `url_launcher`/`LaunchMode.externalApplication` — e.g. Word for `.docx`, Excel for `.xlsx`, the browser for `.html`.
4. **Caching:** Downloaded files are cached locally (configurable: max 200 MB, 7-day TTL). Re-opening the same document is instant.
5. **Offline:** Once downloaded, documents are viewable without connectivity (PDFs in the built-in viewer, other types via system app if available locally).

> **Prototyping note:** The system-default-app approach for non-PDFs was chosen for speed during prototyping. A future production version should either:
> - Integrate a universal inline document viewer (e.g. `universal_file_previewer` or `flutter_document_viewer`), or
> - Render documents inside a WebView using Microsoft Office Online / Google Docs viewer URLs.

### Document Service Configuration (`.env`)

```env
ENABLE_DOCUMENTS=true           # Enable document sharing feature (prototyping only)
DOCUMENT_CACHE_MAX_DAYS=7       # Auto-clear files older than N days
DOCUMENT_CACHE_MAX_MB=200       # Max local cache size before cleanup
```

### Backend Integration for Share-to-Board

To enable a "Share to SmartBoard" button on the faculty/student app:

1. The mobile app uploads the document to cloud storage (Firebase Storage / GCS / S3).
2. The backend writes a Firestore notification document with the `attachment_*` fields pointing to the uploaded file URL.
3. The SmartBoard receives it via the existing Firestore `.snapshots()` listener within seconds.
4. The board user taps the notification → document downloads and opens.

> **Note:** The board only supports **reading** documents. It cannot upload or send documents back.

---

## Migration to WebSocket

The current production system uses **WebSocket delivery** instead of Firestore snapshots. The Firestore-based approach in this document is preserved for reference but is no longer the active integration path.

### What changed:

| Aspect | Old (Firestore) | New (WebSocket + REST) |
|--------|-----------------|------------------------|
| Delivery | Firestore `.snapshots()` | WebSocket (real-time) |
| History | Firestore query | `GET /api/v1/board/notifications` |
| Ack tracking | Firestore `read` field | `PATCH /api/v1/user/notifications/{id}/acknowledge` |
| Auth | Firebase API key | Bearer token (Firebase ID token) |
| Admin push | Write to Firestore | `POST /api/v1/admin/board/{id}/notification` |

**The server team should refer to [`NOTIFICATION_SYSTEM_API.md`](./NOTIFICATION_SYSTEM_API.md) for all new development.**

---

## 5. Testing Checklist

| Item | Expected | How to Verify |
|------|----------|---------------|
| Firestore rule deployed | `notifications` readable | Manually query from Firebase Console → should return docs |
| Write a test notification | Board displays it within seconds | Create a doc with a known `smart_board_id`, watch the board UI |
| `permission-denied` disappears | No 403 in app logs | Check `[NotificationListener]` logs for absence of error |
| `forceSync()` works | App loads notification on manual refresh | Trigger `forceSync()` (e.g. pull-to-refresh) → logs show count |
