# 🧩 IntelliAttend — Complete Tech Stack File

---

## 1️⃣ OVERALL ARCHITECTURE STYLE

**Architecture Type:**
👉 **Cloud-native, multi-tenant SaaS, event-driven**

**Core Principles:**

* Zero-trust security
* Tenant isolation
* Real-time systems
* Mobile-first
* Fail-safe design

---

## 2️⃣ FRONTEND STACK

### 📱 Student Mobile App

**Platform**

* Android (Primary)
* iOS (Phase 2)

**Tech**

* Flutter (recommended) **OR** React Native
* Camera API
* Bluetooth LE API
* Wi-Fi Scanner API
* GPS / Location Services

**Security**

* Device integrity check (Play Integrity)
* Biometric auth
* Root / emulator detection

---

### 📱 Faculty Mobile App

**Platform**

* Android / iOS

**Tech**

* Flutter / React Native
* Secure session initiation
* OTP generation UI
* Live attendance view

---

### 🖥️ SmartBoard Web App

**Platform**

* Web (Chrome / Edge kiosk mode)

**Tech**

* React.js / Next.js
* WebSocket client
* QR rendering (Canvas / SVG)
* Full-screen kiosk mode

**Purpose**

* Display rotating QR
* Live seating grid
* Visual attendance feedback

---

### 🧑💼 Admin Dashboards (Web)

#### Super Admin Dashboard

* React.js + TypeScript
* Role-based routing
* Feature flags
* System analytics

#### College Admin Dashboard

* React.js
* Reports & exports
* Academic config UI

---

## 3️⃣ BACKEND STACK (THE NEXUS 🧠)

### 🔥 Core Backend

**Runtime**

* Python (FastAPI) **[ACTIVE]**
* Node.js (Legacy / Transitioning)
  *(or Firebase Cloud Functions for v1)*

**Responsibilities**

* Session orchestration
* Token generation
* Validation engine
* RBAC enforcement
* Fraud detection hooks

---

### 🔄 Real-Time Engine

**Tech**

* WebSockets
* Firebase real-time listeners

**Used For**

* QR rotation sync
* Live seating grid
* Session heartbeat

---

## 4️⃣ AUTHENTICATION & IDENTITY

### 🔐 Authentication

* Firebase Authentication
* JWT (short-lived)
* Refresh token strategy

**Users**

* Super Admin
* College Admin
* Faculty
* Student

---

### 🔐 Device & App Trust

* Google Play Integrity API
* Hardware-backed attestation
* App authenticity verification

---

## 5️⃣ DATABASE & STORAGE

### 🗄️ Primary Database

**Cloud Firestore**

**Why**

* Structured documents
* Real-time updates
* Horizontal scalability
* Strong querying for sessions

**Stores**

* Tenants (colleges)
* Users & roles
* Sessions
* Attendance records
* Room metadata
* Audit logs (metadata)

---

### 📦 File Storage

**Cloud Storage**

* Student photos
* Faculty images
* Reports (PDF/CSV)

---

### 🧾 Logs & Audit Storage

* Append-only collections
* Versioned config snapshots
* Immutable records

---

## 6️⃣ LOCATION & PROXIMITY STACK

### 📍 GPS

* Native OS location services
* Accuracy threshold enforcement
* Cluster averaging

---

### 📡 Wi-Fi

* BSSID fingerprinting
* Signal strength validation
* Anti-hotspot detection

---

### 📶 BLE

* BLE beacons
* UUID + RSSI range
* Room-level proximity validation

---

## 7️⃣ SECURITY & FRAUD PREVENTION

### 🔒 Anti-Fraud Layers

* Rotating QR (5s)
* Token expiration
* BLE + Wi-Fi + GPS triangulation
* Device integrity checks
* Multi-device detection

---

### 🛡️ Platform Security

* RBAC engine
* MFA for admins
* IP allow-listing (Super Admin)
* Rate limiting
* Feature locks

---

## 8️⃣ NOTIFICATION & MESSAGING

### 🔔 Push Notifications

* Firebase Cloud Messaging (FCM)

**Used For**

* Session start alerts
* Attendance confirmations
* Admin alerts
* Incident notifications

---

## 9️⃣ ANALYTICS & MONITORING

### 📊 Analytics

* Firebase Analytics
* Custom event tracking
* Attendance success rate
* Fraud indicators

---

### 🩺 System Monitoring

* Cloud Logging
* Error reporting
* Latency tracking
* SmartBoard health

---

## 🔁 10️⃣ DEVOPS & DEPLOYMENT

### ☁️ Cloud Platform

* Google Cloud Platform (GCP)

### 🚀 Deployment

* Firebase Hosting (web)
* Cloud Functions / Cloud Run (backend)
* CI/CD via GitHub Actions

---

### 🔁 Environment Separation

* Development
* Staging
* Production

---

## 11️⃣ ROLE–TECH MAPPING (VERY IMPORTANT)

| Role                | Tech Interaction                  |
| ------------------- | --------------------------------- |
| Super Admin         | Dashboard, Config Engine, Logs    |
| Infrastructure Mode | Provisioning App, BLE, Wi-Fi, GPS |
| College Admin       | Web Dashboard, Reports            |
| Faculty             | Mobile App, SmartBoard            |
| Student             | Mobile App, Sensors               |

---

## 12️⃣ FUTURE TECH (ROADMAP)

* AI-based fraud scoring
* Edge QR rendering fallback
* Offline attendance buffering
* iOS Secure Enclave integration
* Compliance certification tooling

---

## 🧠 FINAL TECH TRUTH

> **Your tech stack matches your architecture decisions.**
> There is **no mismatch**, no shortcut, no hack.

This stack:

* Scales
* Secures
* Explains itself
* Impresses reviewers
* Survives real usage

---
