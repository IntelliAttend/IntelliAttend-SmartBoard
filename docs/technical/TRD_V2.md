
# Technical Requirements Document (TRD)

**Project:** IntelliAttend Smart Board Client
**Platform:** Flutter (Targeting Android & Windows OS)
**Architecture Pattern:** Offline-First TOTP (Time-Based One-Time Password)
**Document Version:** 3.0

## 1. System Overview

The IntelliAttend Smart Board client is a highly resilient, isolated hybrid application. Its primary responsibilities are to authenticate the classroom, execute a strict 120-second cryptographic QR generation loop on a background thread, and maintain real-time UI state. By utilizing a TOTP architecture, the board operates completely independently of network stability during the attendance window. All manual exception handling (latecomers, missing phones) is strictly offloaded to the Faculty Mobile App and is out of scope for this client.

---

## 2. Technology Stack & Core Packages

| Component | Technology | Primary Flutter Packages Required |
| --- | --- | --- |
| **Framework** | Flutter (Dart) | `flutter`, `provider` or `riverpod` (State Management) |
| **Local Database** | Isar Database | `isar`, `isar_flutter_libs` (NoSQL, extreme read/write speed) |
| **Cryptography** | Dart Crypto | `crypto` (for HMAC-SHA256 generation) |
| **Time Sync** | NTP Client | `ntp` (for calculating hardware clock skew) |
| **Network State** | Connectivity | `connectivity_plus` (for offline vault triggers) |
| **Hardware Security** | Secure Storage | `flutter_secure_storage` (Hardware Keystore for the `session_secret`) |

---

## 3. Core System Modules & Logic Protocols

### 3.1. Boot Sequence & NTP Synchronization Module

Cheap smart board hardware often suffers from clock drift. Because TOTP relies on strict time windows, the board must correct its internal clock on boot.

1. **Execution:** On application launch, before rendering the OTP login screen, the app queries `time.google.com` via the `ntp` package.
2. **Calculation:** `clock_skew = true_ntp_time - local_device_time`.
3. **Storage:** The `clock_skew` variable is held in memory. Every time the app needs the "current time" for a cryptographic function, it must use `DateTime.now().add(clock_skew)`.

### 3.2. Session Ignition Module

1. **Trigger:** Faculty enters the 6-digit OTP on the UI.
2. **API Call:** App sends `POST /board/session/initiate` including the OTP and the composite hardware fingerprint.
3. **Payload Processing:** The server responds with the `session_id`, the classroom roster, and the crucial `session_secret` (the cryptographic seed).
4. **Security:** The `session_secret` is immediately written to the OS-level Hardware Keystore via `flutter_secure_storage`. It is *never* stored in plaintext or in the Isar database.

### 3.3. The TOTP QR Engine (The 2-Minute Sprint)

This is the most critical module. It must not block the main UI thread.

1. **Threading:** Upon clicking "Start Attendance", the app spawns a **Dart Isolate**.
2. **The Loop:** The Isolate runs a `Timer.periodic` every 3.5 seconds.
3. **The Math:**
* Fetch `adjusted_time` = `DateTime.now().add(clock_skew)`.
* Convert `adjusted_time` to a Unix epoch timestamp (rounded to the nearest 3.5s window).
* Generate Hash: `HMAC-SHA256(session_secret, adjusted_timestamp)`.
* Send the resulting hash string back to the Main Thread to be rendered as a QR Code widget.


4. **Termination:** A separate 120-second countdown runs on the Main Thread. At `00:00`, it calls `isolate.kill()` immediately, destroying the QR generator in memory and triggering the UI to transition to Presentation Mode.

### 3.4. Crash Recovery & Session Persistence Module

1. **State Saving:** Upon successful login, an `ActiveSession` record is written to the Isar database.
2. **Crash Intercept:** On app boot (Phase 3.1), the app queries Isar for an `ActiveSession`.
3. **Logic:** If a session exists AND the current NTP time is *before* the session's scheduled end time, the app bypasses the OTP screen, repaints the green tiles from the saved state, and resumes operation.

---

## 4. Local Database Schema (Isar Vault)

Your developers will use this exact schema to generate the Isar collections for the Smart Board.

```dart
// active_session.dart
@collection
class ActiveSession {
  Id id = Isar.autoIncrement; // Isar internal ID
  
  @Index(unique: true)
  late String sessionId; 
  
  late DateTime scheduledEndTime;
  late String facultyName;
  late String className;
  
  // Stores IDs of students who have successfully scanned
  // Used to instantly repaint the UI green upon a crash recovery
  List<String> verifiedStudentIds = []; 
}

// queued_scan.dart
// ONLY used if the campus Wi-Fi drops and the board captures scans via local LAN/Bluetooth
@collection
class QueuedScan {
  Id id = Isar.autoIncrement;
  
  @Index()
  late String sessionId;
  
  late String studentId;
  late String scannedTotpHash;
  late DateTime scanTimestamp;
}

```

---

## 5. API Contracts (Smart Board <-> Server)

**Base URL:** `https://api.intelliattend.edu/v1/board`
`Headers: X-Board-MAC: <hardware_fingerprint>` required on all requests.

### 5.1. `POST /session/initiate`

* **Trigger:** Faculty submits the OTP on the lock screen.
* **Request:**
```json
{
  "otp": "847291"
}

```


* **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "session_id": "SESS_554433",
    "session_secret": "z9#kL2!pQ8rX$mN5", 
    "scheduled_end_time": "2026-03-15T10:00:00Z",
    "faculty_details": {"name": "Dr. Smith", "course": "Physics 101"},
    "roster_count": 60
  }
}

```



### 5.2. `POST /sync/vault`

* **Trigger:** The `connectivity_plus` listener detects Wi-Fi restoration. App checks the Isar `QueuedScan` collection.
* **Request:**
```json
{
  "session_id": "SESS_554433",
  "queued_scans": [
    {
      "student_id": "STU_1122", 
      "hash": "a8f5c...9b2e1", 
      "timestamp": "2026-03-15T09:05:02Z"
    }
  ]
}

```


* **Response (200 OK):** Prompts the Smart Board to execute `isar.queuedScans.clear()`.

### 5.3. `POST /session/terminate`

* **Trigger:** Faculty taps "End Session".
* **Request:**
```json
{
  "session_id": "SESS_554433",
  "end_time": "2026-03-15T09:55:00Z"
}

```


* **Response:** Acknowledges punch-out. Prompts the board to wipe all local DB records, purge the hardware keystore, and return to the Kiosk UI.

---

## 6. WebSocket Event Definitions

The Smart Board maintains a persistent connection (`wss://api.intelliattend.edu/ws/board?session_id=...`) to listen for real-time updates.

* **`attendance_success`:** * Payload: `{"student_id": "STU_1122", "grid_index": 14}`
* UI Action: The state manager updates grid index 14 to `Colors.green`. Updates Isar `verifiedStudentIds` array.


* **`emergency_alert`:**
* Payload: `{"type": "fire", "message": "Evacuate"}`
* UI Action: Flutter `Navigator.push` to a full-screen, high-contrast warning overlay, overriding the presentation/QR view.



