# 📋 IntelliAttend Product Specification

## 🎯 Vision
To provide a friction-less, tamper-proof, and automated attendance management system for educational institutions, reducing administrative overhead and eliminating proxy attendance.

---

## 👤 User Roles & Journeys

### 🎓 The Student
- **Login:** Authenticates with university-provided credentials.
- **Onboarding:** Binds their specific hardware device to their account.
- **Attendance:**
  1. Opens app in classroom.
  2. Scans rotating QR v7.0 token on SmartBoard.
  3. App performs background trust checks (GPS, Wi-Fi).
  4. Instant confirmation on device.

### 👩‍🏫 The Faculty
- **Session Management:** Initiates a class session via PIN/OTP.
- **Monitoring:** Views a real-time "Live Dashboard" on the SmartBoard or Mobile App.
- **Manual Override:** Can manually mark a student as present in case of technical failure.

### 🏛️ The Admin
- **Infrastructure:** Registers classroom GPS coordinates and Wi-Fi Access Point BSSIDs.
- **Users:** Manages faculty and student enrollments.
- **Reports:** Generates academic compliance and attendance history reports.

---

## ✅ Core Requirements

### 1. Security & Integrity
- **Dynamic QR:** 5-7s rotation cycle to prevent photo/video sharing.
- **Multi-Factor:** convergence of GPS (30m), Wi-Fi BSSID, and QR Token.
- **Device Binding:** One account per physical device.

### 2. Operational Reliability
- **Offline Mode:** Students must be able to scan and "queue" attendance if local Wi-Fi drops.
- **Kiosk Persistence:** SmartBoard app must auto-launch and stay in the foreground during classes.
- **Zero-Maintenance:** Automatic daily resets of timetable state.

### 3. User Experience
- **T-Minus Notifications:** Faculty notified 3 minutes before a session starts.
- **Adaptive Brightness:** Visual comfort for both bright and dark classroom environments.
- **Cinematic Transitions:** Clear visual feedback for scanning success.

---

## 📈 Future Enhancements
- **AI Anomaly Detection:** Identifying patterns of suspicious attendance behavior.
- **Chroma-Ghost:** Physics-based optical liveness detection.
- **Cross-Device Sync:** Seamlessly moving a session from a SmartBoard to a laptop.
