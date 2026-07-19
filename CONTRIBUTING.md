# IntelliAttend SmartBoard

Windows desktop kiosk application for classroom attendance. Built with Flutter, runs on physical SmartBoard hardware.

## Branch Model

```
school-main  ← production (auto-deploys to server + builds MSI)
school-dev   ← staging (CI runs, no deploy)
main         ← legacy (unused)
```

### Workflow

1. Create a feature branch from `school-dev`:
   ```bash
   git checkout school-dev
   git checkout -b feat/my-feature
   ```
2. Push your branch — CI will run tests
3. When ready, create a Pull Request → `school-dev`
4. After review and merge to `school-dev`, the owner promotes to `school-main`
5. Push to `school-main` triggers **production deploy** (builds MSI → uploads to server → SmartBoard devices auto-update)

### What happens on push to `school-main`

```
Push to school-main
  → CI builds Windows MSI (Flutter + WiX)
  → Creates GitHub Release (v5.5.0+NN)
  → Uploads MSI to production server (ci-upload endpoint)
  → Server creates update manifest in database
  → Admin Panel download page shows new version
  → Existing SmartBoard devices auto-update on next heartbeat
```

### Secrets Required

| Secret | Purpose |
|--------|---------|
| `FIREBASE_API_KEY` | Firebase Web API key |
| `FIREBASE_APP_ID` | Firebase App ID |
| `FIREBASE_MESSAGING_SENDER_ID` | FCM sender ID |
| `SSL_PIN_FINGERPRINT` | TLS certificate pin |
| `DEPLOY_KEY` | Server auth for CI upload |

### Variables Required

| Variable | Purpose |
|----------|---------|
| `API_BASE_URL` | Production backend URL |
| `SERVER_URL` | Backend URL for CI upload |
| `FIREBASE_PROJECT_ID` | Firebase project ID |

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md)

## Local Development

```bash
flutter pub get
flutter run -d windows
```

Use `.env` file at project root for local configuration.
