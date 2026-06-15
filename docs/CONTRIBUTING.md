# 🤝 Contributing to IntelliAttend

Thank you for your interest in contributing to the **IntelliAttend SmartBoard** project! We are building an enterprise-grade, offline-resilient attendance system for universities.

---

## 🚀 Development Stack
- **Frontend:** Flutter (Windows Desktop)
- **Backend:** Python (FastAPI)
- **Database:** Google Cloud Firestore (NoSQL)
- **Architecture:** Offline-First, TOTP-based cryptographic verification.

---

## 📝 Code Standards

### Flutter (Frontend)
- **State Management:** Use `provider` (ChangeNotifier).
- **Style:** Follow the official [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines.
- **Async/Await:** Avoid blocking the main UI thread; use Isolates for heavy cryptographic work.
- **Security:** Sensitive data (JWTs, session secrets) must **ONLY** be stored in the OS Keychain via `flutter_secure_storage`.

### Python (Backend)
- **Style:** Follow [PEP 8](https://www.python.org/dev/peps/pep-0008/).
- **Validation:** Use `Pydantic` models for all request/response schemas.
- **I/O:** Use async-native clients for all database and external API calls.
- **Security:** Enforce RBAC on all endpoints.

---

## 🌿 Git Workflow

### Branching
- `feature/name` - New features.
- `fix/name` - Bug fixes.
- `refactor/name` - Code improvements.
- `docs/name` - Documentation updates.

### Commits
Follow [Conventional Commits](https://www.conventionalcommits.org/):
- `feat(scope): ...`
- `fix(scope): ...`
- `docs(scope): ...`

---

## 🧪 Testing Requirements
- **Flutter:** All business logic (Services/Providers) must have unit tests.
- **Python:** All endpoints and services must be covered by `pytest` suite.
- **Validation:** Your changes must not break the `flutter analyze` or `ruff check` linting passes.

---

## 🔐 Security First
- **Secrets:** Never commit `.env` files or hardcoded credentials.
- **PII:** Be extremely careful with Student/Faculty data; use redaction in logs.
- **Integrity:** All board interactions must respect the "Strictly Human" protocol (manual PIN/OTP entry).

---

## 📖 Documentation
If you add a feature, you **MUST** update the relevant `.md` file in `docs/`:
- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)
- [`docs/SECURITY.md`](./docs/SECURITY.md)
- [`docs/FIREBASE.md`](./docs/FIREBASE.md)
- [`docs/DEVELOPER_GUIDE.md`](./docs/DEVELOPER_GUIDE.md)
