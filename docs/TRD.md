# Technical Requirements Document (TRD): QR Sync Engine

**System**: IntelliAttend Core Architecture
**Component**: High-Frequency TOTP QR Engine & Real-Time Pipeline
**Environment**: GCP (asia-south1), FastAPI, Redis, Firestore

## 1. System Architecture & Tech Stack (Aligned)
IntelliAttend is a **High-Performance Polyglot System** designed for zero-trust environments.

- **Backend (Brain)**: FastAPI (Python 3.11+) + Redis + Firestore.
- **SmartBoard (Hardware)**: **Flutter (Native Win/Android)**.
- **Mobile (Edge)**: Flutter (Dart).
- **Bridge (Live Feed)**: Node.js (High-Concurrency WebSocket).

### Why Native Flutter for SmartBoards?
1. **CPU-Bound Timers**: JavaScript `setInterval` is unreliable in background/kiosk modes. Flutter Native Isolates guarantee 3.5s precision.
2. **Kiosk Hardening**: Native Windows/Android APIs allow for true Fullscreen/WakeLock enforcement that browsers cannot guarantee.
3. **Hardware Pinning**: Allows direct access to MAC addresses and hardware IDs for node identity verification.

## 2. Cryptographic Specifications
The system utilizes a heavily modified Time-Based One-Time Password (TOTP) algorithm based on RFC 6238, optimized for optical transmission (QR).

- **Window Size ($W$)**: 3.5 seconds.
- **Time Step Formula**: $T = \lfloor \frac{\text{CurrentUnixTime} + \text{DriftOffset}}{3.5} \rfloor$
- **Hashing Algorithm**: HMAC-SHA256.
- **Seed Generation**: 32-byte cryptographically secure random number (`secrets.token_bytes(32)`), encoded in Base32.
- **Output Truncation**: The raw SHA-256 hash is dynamically truncated and encoded into a **6-character Base36 string** (0-9, A-Z) to ensure the QR code remains at Error Correction Level L/M.
- **Validation Tolerance**: The server must validate against both the current time step ($T$) and the previous time step ($T-1$) to allow a maximum latency window of **7.0 seconds**.

## 3. API Contracts (REST)

### 3.1 Initialize Class Session
Called by the Smart Board to generate the cryptographic seed and synchronize its internal clock.
- **Endpoint**: `POST /api/v1/session/start`
- **Auth**: Bearer Token (Faculty JWT)
- **Request Body**:
  ```json
  {
    "course_id": "CS302",
    "room_id": "LH-4"
  }
  ```
- **Response (200 OK)**:
  ```json
  {
    "session_id": "sess_8f92j29",
    "seed": "JBSWY3DPEHPK3PXP...", 
    "server_time": 1711345800.123
  }
  ```

### 3.2 Mark Attendance (The "Thundering Herd" Endpoint)
Called by 100+ student mobile apps simultaneously within a 5-minute window. Must execute in < 15ms.
- **Endpoint**: `POST /api/v1/attendance/mark`
- **Auth**: Bearer Token (Student JWT)
- **Request Body**:
  ```json
  {
    "session_id": "sess_8f92j29",
    "scanned_token": "8F4C9A",
    "device_id": "android_a8f93nf"
  }
  ```
- **Response (200 OK)**:
  ```json
  {
    "status": "success",
    "message": "Attendance recorded."
  }
  ```
- **Error Responses**:
  - `403 Forbidden`: "Invalid or expired QR code." (Token mismatch or $T-2$ expiration).
  - `401 Unauthorized`: "Device binding mismatch." (Student logged into a friend's phone).

## 4. Real-Time Pipeline (WebSocket)
The Smart Board maintains a persistent connection to display live scans.
- **URI**: `wss://api.intelliattend.com/ws/session/{session_id}`
- **Connection Lifecycle**: Opened immediately after `/session/start`. Closed by the client when the professor clicks "End Class".
- **Server-to-Client Payload** (Emitted on successful scan):
  ```json
  {
    "event": "STUDENT_SCANNED",
    "data": {
      "user_id": "21N31A6601",
      "first_name": "Rahul",
      "timestamp": 1711345892
    }
  }
  ```

## 5. Data & Cache Schemas

### 5.1 Redis (In-Memory State)
Active class data is strictly held in Redis for high-frequency reads.
- **The Cryptographic Seed**:
  - Key: `session:{session_id}:seed`
  - Value: `JBSWY3DPEHPK3PXP...` (String)
  - TTL: 7200 seconds (2 hours).
- **The Idempotency Set** (Preventing duplicate scans):
  - Key: `session:{session_id}:present`
  - Data Type: Redis Set (`SADD`)
  - Values: `["21N31A6601", "21N31A6602"]`

### 5.2 Firestore (Permanent Storage)
The backend uses a BackgroundTask to asynchronously flush Redis attendance data into Firestore.
- **Collection**: `attendance_logs`
- **Document ID**: `{session_id}_{student_id}` (Enforces uniqueness).
- **Document Structure**:
  ```json
  {
    "session_id": "sess_8f92j29",
    "student_id": "21N31A6601",
    "course_id": "CS302",
    "scanned_at": "2026-03-23T13:04:07Z",
    "device_used": "android_a8f93nf",
    "status": "PRESENT"
  }
  ```
