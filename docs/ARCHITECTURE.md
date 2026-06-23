# 🏗️ IntelliAttend Architecture

## 🎯 System Purpose
IntelliAttend is an enterprise-grade, offline-resilient attendance system for university classrooms. It eliminates proxy attendance by using a multi-factor "Trust Engine" that validates student presence through cryptographic, temporal, and spatial signals.

---

## 🛠️ Technology Stack

### Frontend (SmartBoard)
- **Framework:** Flutter (Windows Desktop)
- **Local State:** Provider (ChangeNotifier)
- **Local DB:** Isar 3.x (Offline vault for timetable and session state)
- **Platform Integration:** `window_manager` for kiosk mode, `win32_registry` for auto-launch.

### Backend (The Brain)
- **Language:** Python 3.11+
- **Framework:** FastAPI
- **Real-time:** WebSockets & Firebase Native Snapshots
- **Validation:** Pydantic models for request/response integrity.

### Data & Cloud
- **Primary Database:** Google Cloud Firestore (NoSQL)
- **Authentication:** Firebase Identity Toolkit (JWT) + API Key v5.4
- **Real-time Engine:** Native `.snapshots()` for cost-effective push updates.

---

## 🧩 Core Components

### 1. SmartBoard (Kiosk Hardware)
Runs in classrooms on Windows hardware.
- Displays rotating **QR v7.0** tokens.
- Manages class lifecycle (T-minus warm-up, active session, post-class cleanup).
- Enforces "Strictly Human" protocol (PIN entry to start session).

### 2. Backend Engine
Central orchestrator for the ecosystem.
- **Trust Engine:** Evaluates confidence scores from QR, GPS, Wi-Fi, and BLE signals.
- **Session Manager:** Coordinates QR rotation and session heartbeat.
- **API Gateway:** Handles JWT issuing, token refresh, and RBAC.

### 3. Mobile App (Student/Faculty)
- **Student:** Scans QR, collects sensor data (GPS/Wi-Fi), and submits attendance.
- **Faculty:** Initiates sessions, monitors live counts, and manages overrides.

---

## 📂 Project Structure

### Frontend (`/lib`)
```text
lib/
├── core/
│   ├── config/         # App constants & Firestore schema
│   ├── network/        # API client & interceptors
│   ├── platform/       # Kiosk service, Registry, Windows management
│   ├── security/       # Integrity verifier, Secure storage, JWT auth
│   └── theme/          # UI Styling
├── data/
│   └── repositories/   # Data access layer (Isar & Firestore)
├── models/             # Isar & JSON schemas
├── presentation/
│   ├── providers/      # State management (Stateful logic)
│   ├── screens/        # UI Screens (Boot, Idle, Attendance, etc.)
│   └── widgets/        # Reusable UI components
└── services/           # Business logic (API, Sync, Telemetry, Listeners)
```

### Backend (`/backend/python`)
```text
backend/python/
├── main.py             # FastAPI Entry point
├── middleware/         # Auth & Security middleware
├── models/             # Pydantic schemas
├── services/           # Trust Engine & Business logic
└── tests/              # Pytest suite
```

---

## 🔄 Communication Flow

The canonical product contract for attendance state is
[`docs/product/ATTENDANCE_SESSION_LIFECYCLE_PRD.md`](product/ATTENDANCE_SESSION_LIFECYCLE_PRD.md).

1.  **Hydration:** Every actor calls `GET /api/v1/session/current-state` on boot, open, foreground resume, reconnect, or WebSocket recovery.
2.  **Handshake:** SmartBoard performs pre-flight check and hardware binding.
3.  **Auth:** Device registers with OTP -> Server issues API Key + JWT (v5.4).
4.  **Sync:** Clients subscribe to WebSocket/Firebase updates only after hydration.
5.  **Active Session:**
    -   Faculty starts the session; server transitions `PREPARING -> IGNITING` and generates OTP/session credentials.
    -   SmartBoard verifies OTP; server transitions `IGNITING -> ACTIVE`.
    -   SmartBoard renders rotating QR and live roster when the server says `ACTIVE`.
    -   Student scans -> Mobile app submits to Backend.
    -   Backend validates signals -> persists attendance -> broadcasts update hints.
    -   Faculty, SmartBoard, Student, and Admin render the same server state. Missed WebSocket events are recovered through `current-state`.

---

## 📈 Service Level Objectives (SLOs)

IntelliAttend is designed for mission-critical university operations. The following targets are enforced:

| Metric | Target | Measurement Window |
|--------|--------|-------------------|
| **System Uptime** | 99.9% | Monthly |
| **API Latency (p95)** | < 200ms | Daily |
| **QR Scan-to-Mark** | < 3.0s | Per Session |
| **Offline Sync Delay** | < 10s | Post-Reconnection |
