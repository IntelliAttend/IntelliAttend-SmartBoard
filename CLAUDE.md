# CLAUDE.md — IntelliAttend SmartBoard

## What This Is

Flutter/Dart interactive classroom display app. Runs on Android, Windows, macOS, and Web. Shows live attendance status, timetable, and notifications. Has an embedded Python backend for local processing.

## Architecture

```
lib/
├── main.dart                 # Flutter entry point
├── screens/                  # UI screens (idle, workspace, attendance, etc.)
├── services/                 # WebSocket, API, notification services
├── models/                   # Data models (Isar schemas)
├── controllers/              # State controllers
├── widgets/                  # Reusable UI widgets
├── core/                     # Utils, constants, theme
└── backend/                  # Embedded Python backend
    └── python/
        ├── main.py           # FastAPI server
        ├── services/         # Auth, alert, registration services
        └── models/           # SQL models
```

## Key Entry Points

- `lib/main.dart` — Flutter app entry
- `lib/screens/workspace_screen.dart` — Main workspace display
- `lib/screens/idle_screen.dart` — Idle/welcome screen
- `lib/services/websocket_service.dart` — WebSocket connection to Server
- `lib/services/api_service.dart` — REST API client
- `lib/models/isar_schemas.dart` — Local database schemas
- `backend/python/main.py` — Embedded Python backend

## Commands

```bash
flutter pub get          # Install dependencies
flutter run              # Run on connected device
flutter run -d chrome    # Run on web
flutter test             # Run tests
dart format .            # Format code
dart analyze             # Static analysis
```

## Platform Targets

| Platform | Status | Notes |
|----------|--------|-------|
| Android | ✅ Primary | Target device for classroom |
| Windows | ✅ Secondary | Desktop display |
| macOS | ✅ Secondary | Desktop display |
| Web | ✅ Secondary | Browser access |
| iOS | ❌ Not supported | Not needed for SmartBoard |
| Linux | ❌ Not supported | Not needed for SmartBoard |

## Conventions

- **State:** Controllers (not Provider or Bloc)
- **Database:** Isar (local NoSQL)
- **WebSocket:** Custom service with reconnection logic
- **Commit messages:** Conventional Commits: `fix(smartboard): description`, `feat(smartboard): description`
- **Branch:** `school-main` (production), `school-dev` (development)

## Gotchas

- Isar is the local database. Schemas defined in `lib/models/isar_schemas.dart`.
- WebSocket must reconnect on network changes. Check `websocket_service.dart`.
- Embedded Python backend runs alongside Flutter. Check `backend/python/`.
- `release-iasb4208.zip` is a release artifact — don't modify.
- `.flutter-version` pins Flutter version for CI consistency.

## graphify

```bash
graphify query "<question>"
graphify update .
```

## Key Relationships

- **→ Server:** WebSocket for real-time attendance, REST for config
- **← Faculty App:** Receives attendance updates
- **← Admin Panel:** Receives board configuration
- **→ Embedded Python:** Local processing, registration
