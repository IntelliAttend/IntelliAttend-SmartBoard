# 🔥 Firebase & Firestore Configuration

## 🗄️ Firestore Collections

All collection and field names are centralized in `lib/core/config/firestore_schema.dart`. 

### 1. `timetable_slots`
**Purpose:** Stores the class schedule for each SmartBoard.
- `smart_board_id`: (string) Filter key for the device.
- `day_of_week`: (string) Monday-Sunday.
- `start_time` / `end_time`: (timestamp/string).
- `subject_name` / `course_code`: Display data.

### 2. `ActiveSessions`
**Purpose:** Real-time state of currently running classes.
- `current_token`: (string) The binary-packed QR v7.0 token.
- `sequence`: (number) Rotation counter.
- `faculty_id`: (string) Reference to the host.
- `status`: `active` | `expired`.

### 3. `student_attendance`
**Purpose:** Records of successful scans.
- `student_id`: Reference.
- `session_id`: Reference.
- `trust_score`: (number 0-100).
- `marked_at`: (timestamp).

### 4. `notifications`
**Purpose:** Real-time push messages to specific boards.
- `smart_board_id`: Target board.
- `message`: Payload.
- `type`: `alert` | `info` | `command`.

---

## 🔐 Security Rules
The SmartBoard app uses the **Firebase Identity Toolkit (REST)** and does not use the standard `firebase_auth` SDK (to avoid C++ crashes on Windows). 

Rules must allow reads based on `smart_board_id`:

```javascript
match /timetable_slots/{doc} {
  allow read: if resource.data.smart_board_id == request.auth.token.board_id;
}
match /notifications/{doc} {
  allow read: if resource.data.smart_board_id == request.auth.token.board_id;
}
```

---

## 🛰️ Real-time Listeners (`.snapshots()`)
The app uses native Firestore snapshots for cost-efficiency.
- **Budget:** ~333 reads/board/day.
- **snapshots():** Only bills on actual data changes.
- **forceSync():** Manual REST-based one-shot fetch for one-off refreshes (e.g., Pull-to-refresh).

---

## 🚀 Setup Guide
1.  Create Firebase Project.
2.  Enable Firestore in **Native Mode**.
3.  Add macOS/Windows app (using package ID from `pubspec.yaml`).
4.  Download `google-services.json` / `GoogleService-Info.plist`.
5.  Set `FIREBASE_API_KEY` and `FIREBASE_PROJECT_ID` in `.env`.
