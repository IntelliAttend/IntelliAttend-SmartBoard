# IntelliAttend SmartBoard v6.4 Manifest
## Security, UI/UX, and Windows Orchestration Hardening

This document outlines the architectural and security improvements implemented in the v6.4 hardening pass. The focus was on moving from a "Simple Kiosk" to an **"Intelligent Orchestrator"** that respects faculty multitasking while maintaining high-security attendance integrity.

---

### 🪟 1. Windows Lifecycle & Integration
We have integrated the SmartBoard more deeply with the Windows OS to ensure it behaves as a reliable appliance rather than just an application.

*   **Registry-Based Auto-Launch**: 
    *   Implemented `StartupService` using the `win32_registry` package.
    *   The app now automatically registers itself in `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` upon successful hardware binding.
    *   **Security Fix (SEC-2)**: All executable paths are now properly double-quoted (`"C:\Path\To\App.exe"`) to prevent registry hijack attacks and support installation directories with spaces.
*   **Window State Orchestration**:
    *   **Locked Mode (Active Class)**: Enforces `Always-on-Top`, `FullScreen`, and `Max Brightness`. Disables standard window controls to prevent students from tampering with the board during QR rotation.
    *   **Soft Mode (Idle/Between Classes)**: Automatically exits `Always-on-Top` and `Locked` states. This allows professors to minimize the app, use the board for YouTube/Presentations, while the app continues its background "Pre-Flight" checks.
    *   **Suspended Mode**: Provides an explicit "Minimize to Taskbar" button on the Idle Screen for administrative multitasking.

---

### 🛡️ 2. Security Hardening ("Strictly Human" Protocol)
The v6.4 update closes several critical security loopholes found in the previous audit.

*   **Human-First Ignition**: 
    *   Automated session starts are strictly forbidden. The Orchestrator prepares the UI (the "T-0 Takeover"), but an **OTP/PIN entry** is required to physically start QR generation.
*   **Atomic Hardware Binding**: 
    *   Refined the registration flow to ensure the device only binds after a successful server-side verification of the `verification_token`.
    *   **L-1 Recovery**: If the app crashes during registration, the `RegistrationProvider` now recovers the stored token and resumes at the OTP step, preventing redundant OTP generation.
*   **Secure Data Wipe (SEC-3)**:
    *   Expanded `SecureStorageService.clearAll()` to include:
        *   `clock_skew` (prevents time-manipulation replays)
        *   `registration_token` (prevents session hijacking)
        *   `idle_theme` (clean state reset)
*   **Anti-Race Condition Guards**:
    *   Resolved **BUG-2**: Removed redundant rotation timers that were causing simultaneous "End Session" triggers.
    *   Implemented **Window-Based Triggers**: T-minus logic now uses a `diffMin <= 3` window with per-slot debounce flags instead of brittle "exact equality" checks, ensuring triggers fire even if the Windows clock drifts or the app is momentarily suspended.

---

### 🎨 3. UI/UX Designing & Orchestration
The user experience has been redesigned to be proactive yet non-intrusive.

*   **T-Minus Lifecycle**:
    *   **T-10 Minutes**: Warm-up phase. The app starts background sync and pre-flights connections.
    *   **T-3 Minutes**: Proactive Notification. A Windows system toast alerts the faculty that the session starts in 3 minutes.
    *   **T-0 Minutes**: Takeover. The app automatically brings itself to the foreground and opens the "Enter OTP" card, signaling that the classroom is now under "Attendance Security."
*   **Daily State Resets**:
    *   The system now tracks the `_lastTickDate`. At midnight, it automatically wipes all "Fired" flags for the previous day's timetable. This ensures the board remains a "Zero-Maintenance" device for IT staff.
*   **Cinematic Transitions**:
    *   Integrated smooth animations in `IdleScreen` and `AttendanceScreen` using custom `AnimationControllers`, providing a premium "Software-as-an-Appliance" feel.
*   **Brightness Management**:
    *   **Adaptive Brightness**: The app saves the user's current system brightness before a class starts and restores it exactly when the session ends, ensuring we don't permanently alter the classroom's hardware settings.

---

### 📦 4. Production Readiness
*   **Logging Policy**: Removed all `print()` statements in favor of a structured `Log` service that prevents sensitive timing/token data from leaking into standard console output.
*   **Configuration Flexibility**: The OTP rotation window is now configurable via `AppConfig.otpRotationWindowSeconds` (defaulting to 300s/5mins), allowing IT admins to tune the system's strictness without code changes.

---
**Status**: 🟢 Production Ready | **Version**: 6.4 | **Platform**: Windows/macOS/Android
