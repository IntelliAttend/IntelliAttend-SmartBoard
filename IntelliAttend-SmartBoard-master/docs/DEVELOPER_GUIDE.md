# 👨‍💻 Developer Guide

## 🚀 Quick Start

### Prerequisites
- Flutter SDK 3.35.6+
- Python 3.11+
- Windows 10/11 (for full feature testing)

### 1. Environment Setup
Create a `.env` file in the root directory:
```bash
API_BASE_URL=https://api.yourdomain.com
FIREBASE_API_KEY=AIzaSy...
FIREBASE_PROJECT_ID=intelliattend-prod
```

### 2. Frontend (Flutter)
```powershell
# Install dependencies
flutter pub get

# Run on Windows
flutter run -d windows

# Build Release
flutter build windows --release
```

### 3. Backend (FastAPI)
```bash
cd backend/python
pip install -r requirements.txt
uvicorn main:app --reload
```

---

## 🛠️ Development Workflow

### 📋 Code Standards
- **Naming:** Follow PEP 8 for Python and Effective Dart for Flutter.
- **Async/Await:** Use async-native clients for Firestore. Avoid blocking the event loop.
- **Errors:** Use custom exception types and appropriate HTTP status codes.

### 🧪 Testing
```powershell
# Run Flutter tests
flutter test

# Run Python tests
cd backend/python
pytest
```

---

## 🩺 Monitoring & Debugging

### Logging
- The app uses a structured `Log` service.
- **Sensitive Data:** Never log PII, device IDs, or JWT tokens to stdout.
- **Release Mode:** Standard `print()` is filtered out; use `Log.i()`/`Log.e()`.

### Common Issues
- **Firestore C++ Crash (Windows):** Occurs if `persistenceEnabled: false` is set. Keep it enabled (default).
- **Registry Failures:** Ensure the app is running with appropriate permissions to write to `HKCU`.
- **QR Skew:** If student app fails to scan, verify that the SmartBoard clock is synced with NTP.

---

## 🤝 Contribution Guidelines
1.  **Strictly Human:** All new features must respect the manual "PIN-to-Start" security protocol.
2.  **Zero-Trust:** Every API call must be validated with a confidence score.
3.  **Performance:** Keep the SmartBoard UI lightweight. Most work should happen in background services.
