# Notification Integration — Server Team Guide

## Overview

The SmartBoard displays real-time notifications (alerts, attendance updates, system messages, admin messages) pushed from the backend. The board **never writes** to the notifications data — it only reads.

The architecture uses **Firestore native `.snapshots()`** for real-time push delivery at zero polling cost. If Firestore native is unavailable, a manual `forceSync()` trigger fetches via REST.

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

## 5. Testing Checklist

| Item | Expected | How to Verify |
|------|----------|---------------|
| Firestore rule deployed | `notifications` readable | Manually query from Firebase Console → should return docs |
| Write a test notification | Board displays it within seconds | Create a doc with a known `smart_board_id`, watch the board UI |
| `permission-denied` disappears | No 403 in app logs | Check `[NotificationListener]` logs for absence of error |
| `forceSync()` works | App loads notification on manual refresh | Trigger `forceSync()` (e.g. pull-to-refresh) → logs show count |
