# Master Execution Plan: IntelliAttend QR Engine

This document serves as the architectural and procedural "North Star" for the IntelliAttend project. It specifies the roles of each technology and the roadmap for the Smart Board (Flutter) developmental phases.

## Phase 1: The "Who Does What" Cheat Sheet
Strict isolation is the golden rule. Each component has a specific jurisdiction.

| Component | Role | Jurisdiction |
| :--- | :--- | :--- |
| **Flutter** | Universal Frontend | Builds the Smart Board app (Windows/Android) and Student Mobile app. **Listens to Firestore for real-time updates.** |
| **Python (FastAPI)** | The Brain & Vault | Handles logins, device ID checks, cryptographic validation, and **Master of Firestore**. |
| **Firebase** | The Nervous System | Acts as the real-time data bridge between Python and Flutter. Stores attendance records in Firestore. |

---

## Phase 2: Smart Board (Flutter) Team Roadmap

### Sprint 1: The Offline QR Engine
*Goal: Get math and UI working locally.*
- **UI**: Build the screen with institutional branding, "breathing LED" border, and center QR.
- **Math**: Implement TOTP math in Dart/Flutter (RFC 6238). Use a `MOCK_SEED_123` for testing.
- **Loop**: Implement `Timer.periodic` (3500ms) to update the `intelliattend://` URI and redraw the QR.
- **Rule**: QR updates must **"snap"** instantly (no fade/cross-dissolve).

### Sprint 2: The Python & Firebase Handshake
*Goal: Secure session initiation and real-time link.*
- **Action**: Implement "Start Class" button triggering `POST /api/v1/session/start`.
- **Clock Sync**: Calculate the difference between local hardware time and `server_time` to apply a precise offset to the TOTP loop.
- **Firebase**: SmartBoard listens to `ActiveSessions/{sessionId}/Attendance` for live updates.

### Sprint 3: Production Hardening
*Goal: Resilience and Security.*
- **Crash Recovery**: Implement Isar database to persist `session_secret` locally for instant reboot recovery.
- **Offline Mode**: Queue scans locally if Wi-Fi drops and sync when back online.

---

## Phase 3: Coordination & Safety Rules

1. **API Contracts First**: Python team must provide OpenAPI/Swagger docs before Flutter development begins.
2. **The "Mock" Strategy**: Node.js team provides a "dummy" broadcast script so Flutter can build animations in parallel.
3. **No Business Logic in Frontend**: The Smart Board is a display; it does not decide "Late" or "Present" status.
4. **Rate Limiting**: Python backend must enforce limits to prevent scan spamming/DDoS.
5. **Quiet Zone**: No UI effects may bleed into the QR code's white margin to ensure optical scannability from distance.
