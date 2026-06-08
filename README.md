# 🛡️ IntelliAttend SmartBoard

> **Enterprise-grade, offline-resilient attendance engine for university classrooms.**

IntelliAttend SmartBoard is the classroom-facing component of the IntelliAttend ecosystem. It runs as a hardened Windows kiosk application, displaying rotating cryptographic QR tokens that prevent proxy attendance and ensure "Strictly Human" verification.

---

## 📖 Documentation Index

### 🏗️ [Architecture](./docs/ARCHITECTURE.md)
*System Purpose, Tech Stack (Flutter/FastAPI), Core Components, and Project Structure.*

### 🔐 [Security Model](./docs/SECURITY.md)
*Zero-Trust philosophy, JWT v5.4 Auth, QR v7.0 Binary Packing, and Windows Hardening.*

### 🔥 [Firebase & Firestore](./docs/FIREBASE.md)
*Collection schemas, Security Rules, and Real-time push logic.*

### 👨‍💻 [Developer Guide](./docs/DEVELOPER_GUIDE.md)
*Setup instructions, Build/Run commands, and Contribution guidelines.*

---

## 🚀 Quick Start

### 1. Prerequisites
- Flutter SDK 3.35.6+
- Python 3.11+
- Windows 10/11

### 2. Setup
```bash
# Clone and install dependencies
git clone [repo-url]
cd intelliattend_smartboard
flutter pub get

# Configure environment
cp .env.example .env
# Add your API_BASE_URL and FIREBASE_API_KEY
```

### 3. Run
```powershell
# Start SmartBoard (Development)
flutter run -d windows

# Start Backend (Development)
cd backend/python
pip install -r requirements.txt
uvicorn main:app --reload
```

---

## ✨ Key Features
- **Offline-First:** Full functionality without internet using Isar local vault.
- **Kiosk Hardened:** Registry-based auto-launch and window-state orchestration.
- **Real-Time:** Native Firestore `.snapshots()` for instant, cost-effective updates.
- **Anti-Fraud:** [CHROMA-GHOST](./docs/technical/CHROMA_GHOST.md) optical liveness detection (Spec).

---

## 🔐 Security Status: v5.4+ Cryptographic Trust
The system uses short-lived **JWTs** and **API Keys**, replacing legacy MAC-based authentication.

| Security Aspect | Current Status |
|-----------------|----------------|
| **Auth**        | JWT + API Key (15 min expiry) |
| **Local Storage**| Encrypted (OS Keychain) |
| **QR Format**   | v7.0 Binary (33 chars) |
| **Integrity**   | Runtime signature verification |

---

**Last Updated:** May 2026  
**Current Version:** `6.4.0` (SmartBoard) / `5.4.0` (Security Protocol)
