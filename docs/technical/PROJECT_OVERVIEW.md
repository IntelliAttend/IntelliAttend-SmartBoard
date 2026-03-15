# IntelliAttend Project Overview

**IntelliAttend** is a production-ready, smart attendance management system designed to eliminate proxy attendance and automate the classroom tracking process. It leverages multi-factor verification—combining Dynamic QR Codes, Geofencing, Wi-Fi BSSID checks, and Biometrics—to ensure that *only* the right student, in the right classroom, at the right time can mark their attendance.

---

## 🧐 The Core Problem
Traditional attendance systems (roll call, paper sheets, static QR codes) are flawed:
- **Proxy Attendance:** Students marking for absent friends.
- **Time Theft:** Students checking in from dorms or cafes.
- **Manual Errors:** Faculty spending valuable class time on administration.

## 💡 The Solution: Multi-Factor Trust Engine
IntelliAttend validates a student's presence using a weighted "Trust Score". Attendance is only marked if the aggregate score passes a strict threshold.

1.  **Dynamic QR Codes (Time-Based):**
    -   Displayed on the classroom SmartBoard.
    -   Rotates every 7 seconds to prevent photo-sharing.
    -   Encrypted with a time-based secret.

2.  **Geofencing (Location-Based):**
    -   Verifies the student's device GPS coordinates match the classroom's registered location.

3.  **Wi-Fi BSSID (Infrastructure-Based):**
    -   Checks if the student's phone is connected to (or can see) the specific University Wi-Fi Access Point for that room.

4.  **Biometric Binding (Identity-Based):**
    -   Requires fingerprint/FaceID to open the scanner, ensuring the actual device owner is present.

---

## 🏗️ System Architecture

The ecosystem consists of four main components functioning in real-time:

### 1. The Mobile App (Unified Student & Faculty)
*Built with Kotlin & Jetpack Compose*
-   **Student Mode:** Scans QR codes, performs background checks (GPS/Wi-Fi), and submits attendance requests.
-   **Faculty Mode:** View live class stats, manage courses, and manually override attendance if needed.
-   **Key Tech:** ML Kit (Fast scanning), CameraX, Biometric Auth, Play Integrity API (Root detection).

### 2. The Backend Engine
*Built with Python FastAPI*
-   Acts as the central brain.
-   **Trust Engine:** Receives data points (QR token, GPS, BSSID) and calculates the validity score.
-   **Security:** Implements Role-Based Access Control (RBAC) and JWT authentication.
-   Uses **Google Firestore** for scalable, real-time data storage.

### 3. SmartBoard Portal
*Built with Vanilla JavaScript*
-   A lightweight web page displayed on the classroom projector/screen.
-   Connects via WebSocket to display the rotating Dynamic QR Code for the active session.

### 4. Admin Portal
*Built with HTML/JS*
-   Web interface for University Administrators.
-   Manages infrastructure (registering Classroom Wi-Fi points, Geofences) and User hierarchies.

---

## 🚀 Key Features

-   **Tamper-Proof:** Replay attacks are prevented by short-lived tokens (7s validity).
-   **Offline-Resilient:** Caches attendance requests if internet drops (syncs on reconnection).
-   **Real-Time Dashboard:** Faculty see attendance counts update live as students scan.
-   **Device Binding:** A student accounts is locked to their specific phone hardware ID to prevent login sharing.

## 🛠️ Technology Stack Summary

| Component | Technology |
| :--- | :--- |
| **Backend** | Python, FastAPI, Pydantic, Uvicorn |
| **Database** | Google Cloud Firestore (NoSQL) |
| **Mobile** | Android (Kotlin), Jetpack Compose, Hilt (DI) |
| **Web Clients** | JavaScript (ES6+), HTML5, CSS3 |
| **Infra/Tools** | Docker, Firebase Auth & Cloud Messaging |

---

*This document provides a high-level "crystal clear" understanding of the project's purpose and mechanics.*
