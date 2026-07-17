# Required GitHub Secrets and Variables

All CI/CD workflows require specific secrets and variables to be configured in the GitHub repository. This document lists every required entry and explains where each is used.

---

## Repository Secrets

These are sensitive values stored in **Settings → Secrets and variables → Actions → Secrets**.

| Secret | Description | Used By |
|--------|-------------|---------|
| `FIREBASE_API_KEY` | Firebase Web API key for Identity Toolkit auth | release.yml, auto-deploy.yml |
| `FIREBASE_APP_ID` | Firebase App ID | release.yml, auto-deploy.yml |
| `FIREBASE_MESSAGING_SENDER_ID` | Firebase Cloud Messaging sender ID | release.yml, auto-deploy.yml |
| `SSL_PIN_FINGERPRINT` | SHA-256 hash of production TLS certificate for certificate pinning | release.yml, auto-deploy.yml |
| `WIX_SIGN_CERT_BASE64` | Base64-encoded Authenticode signing certificate (optional — enables MSI signing) | release.yml |
| `WIX_SIGN_PASSWORD` | Password for the signing certificate (optional) | release.yml |

---

## Repository Variables

These are non-sensitive values stored in **Settings → Secrets and variables → Actions → Variables**.

| Variable | Description | Example | Used By |
|----------|-------------|---------|---------|
| `API_BASE_URL` | Production API base URL | `https://api.your-domain.com` | release.yml, auto-deploy.yml |
| `FIREBASE_PROJECT_ID` | Firebase project ID | `your-project-id` | release.yml, auto-deploy.yml |
| `LOCAL_API_URL` | Local Brain API endpoint for kiosk telemetry | `http://127.0.0.1:8000/v1/board/telemetry` | auto-deploy.yml |

---

## Backend Environment Variables

These are set on the production server (not in GitHub). See `backend/python/.env.example` for the full list.

| Variable | Required | Description |
|----------|----------|-------------|
| `JWT_SECRET` | Yes | Secret key for JWT signing. App crashes on startup if missing. |
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `REDIS_URL` | Yes | Redis connection string (default: `redis://localhost:6379`) |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | Yes | Path to Firebase service account JSON |
| `DEPLOY_KEY` | No | Shared secret for CI upload endpoint authentication |
| `CORS_ALLOWED_ORIGINS` | No | Comma-separated list of allowed CORS origins |
| `ENABLE_DOCUMENTS` | No | Enable document sharing features (default: `true`) |

---

## How Values Flow to the Flutter App

1. **CI/CD builds** inject values via `--dart-define=KEY=VALUE` flags
2. The app reads them at runtime via `AppConfig._env()` → `String.fromEnvironment(key)`
3. For local development, developers can either:
   - Pass `--dart-define` flags to `flutter run`
   - Or create a `.env` file (not bundled in production builds)
4. The `.env` file is **NOT** bundled in the MSI (removed from `pubspec.yaml` assets)

---

## Setup Checklist

Before deploying for the first time:

- [ ] Create all repository secrets listed above
- [ ] Create all repository variables listed above
- [ ] Set `API_BASE_URL` to your production API domain
- [ ] Set `FIREBASE_PROJECT_ID` to your Firebase project ID
- [ ] Generate `SSL_PIN_FINGERPRINT` from your production TLS certificate:
  ```bash
  openssl x509 -in cert.pem -outform DER | shasum -a 256 | cut -d' ' -f1
  ```
- [ ] Restrict `FIREBASE_API_KEY` in Firebase Console to only Identity Toolkit + Secure Token APIs
- [ ] Configure backend environment variables on the production server
- [ ] Verify `JWT_SECRET` is set on the backend (app will not start without it)
