# IntelliAttend SmartBoard

> **Enterprise-grade offline-resilient attendance system for university classrooms**

[![Flutter Version](https://img.shields.io/badge/Flutter-3.35.6-blue.svg)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.9.2-blue.svg)](https://dart.dev)
[![Security](https://img.shields.io/badge/Security-v5.4_Cryptographic_Trust-green.svg)]()

---

## 🔐 Security Status: v5.4 Cryptographic Trust (UPDATED)

### ⚠️ CRITICAL SECURITY UPDATE

**v5.3 (OLD - VULNERABLE):** Used MAC address as authentication token  
**v5.4 (CURRENT - SECURE):** Implements JWT + API Key authentication

| Security Aspect | v5.3 | v5.4 |
|-----------------|------|------|
| Authentication | MAC Address (public) | JWT + API Key (secret) |
| Token Expiry | Never | 15 minutes |
| Spoofing Risk | **HIGH** | **NONE** |
| Local Storage | Plain text | **Encrypted** |

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Security Model](#security-model)
3. [Backend API Specification](#backend-api-specification)
4. [Frontend Architecture](#frontend-architecture)
5. [Installation](#installation)
6. [Firebase Setup](#firebase-setup)
7. [Team Handoff](#team-handoff)
8. [Documentation](#documentation)

---

## Quick Start

### Prerequisites
- Flutter SDK 3.35.6+
- Dart SDK 3.9.2+
- Xcode 15+ (for macOS builds)
- Firebase project (optional, for real-time features)

### Build & Run
```bash
# Clone repository
git clone [repo-url]
cd intelliattend_smartboard

# Install dependencies
flutter pub get

# Run on macOS (development)
flutter run -d macos

# Build release
flutter build macos
```

---

## Security Model

### v5.4: Cryptographic Trust (Current)

#### Authentication Flow
```
1. Device Registration (OTP verification)
   ↓
2. Server returns: api_key, access_token (JWT), refresh_token
   ↓
3. Device stores tokens SECURELY (encrypted local storage)
   ↓
4. API calls use: Authorization: Bearer <JWT>
   ↓
5. JWT expires in 15 minutes → Auto-refresh with refresh_token
```

#### Token Types
| Token | Lifetime | Purpose |
|-------|----------|---------|
| **Access Token** | 15 min | Authenticate API requests (JWT) |
| **Refresh Token** | 1 year | Obtain new access tokens |
| **API Key** | Years | Fallback authentication |

#### Security Features
- ✅ JWT-based authentication (short-lived)
- ✅ Automatic token refresh
- ✅ Encrypted local storage (OS keychain via flutter_secure_storage)
- ✅ Certificate pinning (SHA-256 via SSL_PIN_FINGERPRINT)
- ✅ HMAC split-knowledge session secret delivery
- ✅ MAC address NO LONGER used for auth
- ✅ Replay attack protection (token expiry + QR nonce)
- ✅ Re-registration without deadlocks
- ✅ Runtime integrity verification (startup block on tamper)

#### Critical Security Fix
**Problem:** v5.3 used `X-Board-MAC` header as password (MAC is public, static, spoofable)

**Solution:** v5.4 uses cryptographically secure tokens:
```dart
// OLD (v5.3 - VULNERABLE):
headers['X-Board-MAC'] = macAddress;  // NEVER DO THIS

// NEW (v5.4 - SECURE):
headers['Authorization'] = 'Bearer $jwtToken';  // Expires in 15min
```

---

## Backend API Specification

### ⚠️ Backend Team: Critical Changes Required

The frontend v5.4 **requires** the following changes:

#### 1. Registration Endpoint Must Return Tokens
**Endpoint:** `POST /api/v1/board/register/verify-otp`

**Required Response:**
```json
{
  "success": true,
  "api_key": "bk_live_a1b2c3d4...",
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "rt_1a2b3c4d...",
  "expires_in_ms": 900000,
  "token_type": "Bearer"
}
```

#### 2. New Refresh Endpoint Needed
**Endpoint:** `POST /api/v1/board/auth/refresh`

**Request:**
```json
{"refresh_token": "rt_1a2b3c4d..."}
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_in_ms": 900000
}
```

#### 3. Update Authentication Middleware
```javascript
// BEFORE (DELETE):
const mac = req.headers['x-board-mac'];

// AFTER (IMPLEMENT):
const authHeader = req.headers['authorization'];
const token = authHeader.split(' ')[1];
const decoded = jwt.verify(token, process.env.JWT_SECRET);
```

### Full Backend Documentation
📖 **[Backend API Security v5.4](./docs/technical/BACKEND_API_SECURITY_v5.4.md)** - Complete specification  
🚀 **[Backend Quick Start](./docs/operations/BACKEND_QUICKSTART_v5.4.md)** - 2.5 hour implementation guide

---

## Frontend Architecture

### Key Components

#### v5.7 Security Services
| File | Purpose |
|------|---------|
| `lib/core/security/secure_storage_service.dart` | OS keychain-backed encrypted storage (no Isar) |
| `lib/services/api_service.dart` | JWT auth + auto-refresh + pinned HTTP client |
| `lib/services/device_service.dart` | Token extraction on registration, strips session_secret from Firestore |
| `lib/core/security/ssl_pinning_service.dart` | SHA-256 certificate pinning |
| `lib/core/security/integrity_verifier.dart` | Runtime integrity + code signature verification |
| `lib/core/rate_limiter.dart` | Exponential backoff rate limiter |
| `lib/core/platform/kiosk_service.dart` | Windows kiosk hotkey blocking |
| `lib/core/utils/logger.dart` | Release-mode filter + secret redaction |

#### Screens
| Screen | Purpose |
|--------|---------|
| `boot_screen.dart` | Hardware lock verification + timetable sync |
| `registration_screen.dart` | OTP-based device registration |
| `idle_screen.dart` | Main display (current class, PIN input, timeline) |
| `attendance_screen.dart` | Active session attendance tracking |

#### Offline-First Design
- **Local Bedrock:** Isar database stores timetable + session data
- **Background Sync:** Queued scans uploaded when online
- **Graceful Degradation:** Full functionality without internet

---

## Installation

### 1. Clone & Setup
```bash
git clone [repo-url]
cd intelliattend_smartboard
flutter pub get
```

### 2. Environment Configuration
Create `.env` file:
```bash
API_BASE_URL=https://api-dev.balaseetharamanjaneyulu.com
LOCAL_API_URL=http://127.0.0.1:8000/v1/board/telemetry

```

### 3. Firebase Setup (Optional)
For real-time roster updates and alerts:

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create/select "IntelliAttend" project
3. Add macOS app with your bundle ID
4. Download `GoogleService-Info.plist`
5. Place in `macos/Runner/` directory
6. Enable Firestore Database

📖 **[Firebase Setup Guide](./docs/database/FIREBASE_QUICKSTART.md)**

### 4. Build & Run
```bash
# Development
flutter run -d macos

# Release build
flutter build macos --release
```

---

## Firebase Setup

Firebase is optional but enables:
- ✅ Live roster updates
- ✅ Real-time override notifications
- ✅ Cross-device synchronization

### Quick Setup
1. Add macOS app in Firebase Console
2. Download `GoogleService-Info.plist`
3. Copy to `macos/Runner/`
4. Register in Xcode workspace
5. Enable Firestore
6. Restart app

📖 **Detailed guide:** `docs/database/FIREBASE_QUICKSTART.md`

**Current Status:** App runs in **OFFLINE MODE** without Firebase. Real-time features activate once configured.

---

## Team Handoff

### Frontend Team ✅ (COMPLETE)
- [x] Secure storage implemented
- [x] JWT authentication working
- [x] Token refresh logic added
- [x] MAC address removed from auth
- [x] UI overflow issues fixed
- [x] Documentation updated

### Backend Team 🔨 (IN PROGRESS)
- [ ] Generate JWT secret
- [ ] Update registration to return tokens
- [ ] Create refresh endpoint
- [ ] Update authentication middleware
- [ ] Migrate database schema
- [ ] Remove `X-Board-MAC` dependency
- [ ] Test full flow

**⏱️ Estimated Time:** 2.5 hours  
**📖 Documentation:** `docs/operations/BACKEND_QUICKSTART_v5.4.md`

### DevOps/IT Team
- [ ] Firebase project setup (if using real-time features)
- [ ] Production environment variables
- [ ] Deploy backend with v5.4 endpoints
- [ ] Monitor authentication errors

---

## Documentation

### Core Documentation
| Document | Audience | Purpose |
|----------|-----------|---------|
| **[BACKEND_API_SECURITY_v5.4.md](./docs/technical/BACKEND_API_SECURITY_v5.4.md)** | Backend Team | Complete API specification |
| **[BACKEND_QUICKSTART_v5.4.md](./docs/operations/BACKEND_QUICKSTART_v5.4.md)** | Backend Team | 2.5hr implementation guide |
| **[SECURITY_IMPLEMENTATION_SUMMARY.md](./docs/technical/SECURITY_IMPLEMENTATION_SUMMARY.md)** | All Teams | What was done + why |
| **[FIREBASE_QUICKSTART.md](./docs/database/FIREBASE_QUICKSTART.md)** | DevOps/IT | Firebase setup guide |

### Security Documents
| Document | Purpose |
|----------|---------|
| `docs/technical/v5.4_SECURITY_MIGRATION.md` | Backend migration steps |
| `docs/technical/SECURITY_IMPLEMENTATION_SUMMARY.md` | Frontend changes summary |
| `docs/technical/BACKEND_API_SECURITY_v5.4.md` | Full API spec (60+ pages) |

### Quick References
```bash
# Backend: What do I need to do?
→ Read: docs/operations/BACKEND_QUICKSTART_v5.4.md (15 min read)

# Security: What was fixed and why?
→ Read: docs/technical/SECURITY_IMPLEMENTATION_SUMMARY.md (10 min read)

# Firebase: How to set it up?
→ Read: docs/database/FIREBASE_QUICKSTART.md (5 min read)
```

---

## Project Structure

```
intelliattend_smartboard/
├── lib/
│   ├── core/
│   │   ├── config/
│   │   │   └── app_config.dart
│   │   ├── network/
│   │   │   ├── api_client.dart
│   │   │   └── interceptors/
│   │   ├── platform/
│   │   │   ├── hardware_fingerprint_service.dart
│   │   │   ├── kiosk_service.dart          # Windows kiosk hotkey blocking
│   │   │   ├── notification_service.dart
│   │   │   └── window_orchestrator_service.dart
│   │   ├── security/
│   │   │   ├── integrity_verifier.dart      # Runtime tamper detection
│   │   │   ├── secure_storage_service.dart  # OS keychain (flutter_secure_storage)
│   │   │   └── ssl_pinning_service.dart     # SHA-256 certificate pinning
│   │   ├── theme/
│   │   │   └── app_theme.dart
│   │   ├── utils/
│   │   │   └── logger.dart                 # Release filter + secret redaction
│   │   ├── rate_limiter.dart               # Exponential backoff
│   │   └── startup_service.dart
│   ├── data/
│   │   └── repositories/
│   │       ├── auth_repository.dart
│   │       └── device_repository.dart
│   ├── models/
│   │   └── isar_schemas.dart               # No token fields (keychain only)
│   ├── presentation/
│   │   ├── providers/
│   │   │   └── registration_provider.dart
│   │   └── screens/
│   │       ├── boot_screen.dart
│   │       ├── idle_screen.dart             # HMAC split-knowledge, rate-limited PIN
│   │       ├── attendance_screen.dart       # Queued scan on network failure
│   │       ├── registration_screen.dart
│   │       ├── init_failure_screen.dart
│   │       ├── settings_screen.dart
│   │       ├── timetable_screen.dart
│   │       ├── analytics_screen.dart
│   │       └── notifications_screen.dart
│   ├── services/
│   │   ├── api_service.dart                # JWT auth + pinned client
│   │   ├── device_service.dart             # Token extraction, session secret stripping
│   │   ├── heartbeat_service.dart
│   │   ├── pre_flight_service.dart
│   │   ├── session_manager.dart
│   │   ├── sync_manager.dart               # Periodic queued scan flush
│   │   ├── telemetry_service.dart
│   │   ├── time_sync_service.dart
│   │   └── totp_engine.dart
│   ├── firebase_options.dart
│   └── main.dart                           # Integrity check blocks startup
├── scripts/                                # Automation & testing tooling
│   ├── run_tests.ps1
│   ├── run_coverage.ps1
│   ├── mock_server.py
│   ├── seed_firestore.ps1
│   ├── check_deps.ps1
│   ├── test_watch.ps1
│   ├── golden_test.ps1
│   ├── TESTING_ARCHITECTURE.md
│   └── SCRIPTS_REFERENCE.md
├── backend/
│   └── python/                             # FastAPI backend reference
├── test/                                    # Unit, widget, and integration tests
├── docs/                                    # Project documentation
│   ├── technical/
│   ├── product/
│   ├── operations/
│   ├── database/
│   ├── reports/
│   ├── guides/
│   └── admin/
├── .env                                     # Environment configuration
├── pubspec.yaml
└── README.md                                # This file
```

---

## Known Issues & TODOs

### Frontend (Low Priority)
- [ ] Server-side QR nonce dedup (backend work)
- [ ] Server-side rate limiting (backend work)
- [ ] Add token revocation UI for admins

### Backend (HIGH PRIORITY)
- [ ] **Implement v5.4 token-based authentication**
- [ ] **Remove X-Board-MAC header dependency**
- [ ] Add rate limiting on refresh endpoint
- [ ] Implement token revocation list

---

## Contributing

### Pull Request Checklist
- [ ] Code follows project style (run `flutter analyze`)
- [ ] Tests added/updated (run `flutter test`)
- [ ] Documentation updated
- [ ] Security considerations addressed
- [ ] No hardcoded secrets

### Security Guidelines
- ❌ **NEVER** commit `.env` file
- ❌ **NEVER** use MAC address as authentication
- ✅ **ALWAYS** use JWT for API authentication
- ✅ **ALWAYS** encrypt sensitive local storage
- ✅ **ALWAYS** set token expiry

---

## License

[Your License Here]

---

## Contact

**Project Lead:** [Name]  
**Frontend Team:** [Contact]  
**Backend Team:** [Contact]  
**Security Issues:** [Email]  

---

## Version History

### v5.4 (Current - May 1, 2026)
- 🔐 **CRITICAL SECURITY FIX:** Migrated from MAC-based auth to JWT + API Key
- ✅ Implemented encrypted token storage
- ✅ Added automatic token refresh
- ✅ Fixed UI overflow issues in idle screen
- ✅ Added comprehensive backend documentation

### v5.3 (Previous)
- ⚠️ Used vulnerable MAC address authentication
- ✅ Offline-first architecture
- ✅ OTP-based registration

### v5.2
- Initial production release
- Basic timetable sync
- Hardware locking mechanism

---

**Last Updated:** May 9, 2026  
**Current Version:** `5.4.0+1` (source of truth: `pubspec.yaml`)  
**Security Status:** ✅ Enterprise-Grade (Cryptographic Trust Model)
