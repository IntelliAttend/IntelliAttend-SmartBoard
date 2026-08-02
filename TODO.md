# SmartBoard — Master Task List

> Auto-generated from codebase audit. Last updated: 2026-08-01.

---

## 🟣 Phase 2 — Hardware & Operational Validation (updater)

> **Updater feature freeze in effect.** Only bug fixes allowed; no features, no
> refactors. Phase 1 approved as **Validation Candidate** (not production-ready).
> Full plan: `docs/phase2_hardware_validation_plan.md`. 40 scenarios pending.

| # | Gate | Owner | Status | Details |
|---|------|-------|--------|---------|
| 27 | **A — Power Failure** (SC-051…SC-065, 15) | HW Lab | ❌ Open | PDU power cuts at every pipeline stage; Machine C |
| 28 | **B — Recovery** (SC-066/067/070/071/041/042/050/086/087, 9) | HW Lab | ❌ Open | Crash/reboot/integrity injection; Machine C |
| 29 | **C — Persistence & Integrity** (SC-038/039/074/075 + data matrix) | HW Lab | ❌ Open | ACL/backup/locks + config/data byte-identical checks |
| 30 | **D — Performance & Capacity** (SC-079/080) | HW Lab | ❌ Open | RAM 95/99%, CPU 100%; baseline vs loaded times |
| 31 | **E — Soak** (SC-102 500 cycles; SC-107/108/109) | Soak Eng | ❌ Open | Machine D real update/rollback/restart; fleet 7/14/30-day |
| 32 | **F — Pilot Fleet Ramp** (SC-110…SC-115) | Fleet Ops | ❌ Open | 1→5→20→100→500→1000 boards, staged observe |
| 33 | **Gate 4 — Operations** | Ops | ❌ Open | Dashboard, telemetry, rollback metrics, alerts |
| 34 | **Gate 5 — Disaster Recovery Drill** | Ops | ❌ Open | v5.6 critical bug → safe revert of every board to v5.5 |
| 35 | **Release Readiness Review (RRR)** | All 4 roles | ❌ Open | Dev/QA/Ops/Product sign-off; one NO holds release |
| 36 | **Tag `validation-candidate-v2`** | Dev | ✅ Done | CI-green candidate (product commit `82d43d9`). v1 (`5e89dc0`) superseded — red CI. Notebook: `docs/release/validation-candidate-v2/` |
| 37 | **Fleet deploy gate** | Dev | ✅ Done | Auto-Deploy `ci-upload` gated behind manual `promote=true`; artifacts archived (setup, agent, cert, SHA256SUMS, build-info) |
| 38 | **Branch protection** | Dev | ⏸ Deferred | PR-review flow off the table for now; revisit when a PR-based version bump is acceptable |
| 39 | **Canonical validated artifact** | Dev | ✅ Done | Release `v5.5.0.22` (2026-08-02) with all evidence artifacts. +19/+20/+21 were version bumps with no release. Notebook updated |
| 40 | **Auto-Deploy Authenticode hang** | Dev | ✅ Done | Offline verification (PE cert table + SignedCms + chain-to-root, zero network). Verified on runner: 3 binaries in 1s (run 30730843811); fleet step skipped |

---

## 🔴 Server-Side (Backend Team — Python/FastAPI)

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 1 | **Mount device registration router** in `main.py` | 🔴 Critical | ✅ Done | New `/api/v1/device/register/*` router mounted; PostgreSQL-backed (no Firestore) |
| 2 | **Reset board `is_registered` flag** for IASB-4208 | 🔴 Critical | ❌ Open | Firestore doc `smart_boards/IASB-4208` has `is_registered: true` → set to `false` |
| 3 | **Verify `/device/register/complete` returns `custom_token`** | 🔴 Critical | ✅ Done | Returns Firebase custom token + classroom profile |
| 4 | **Verify `/device/register/login` response shape** | 🟡 Medium | ✅ Done | Returns `already_registered` or `otp_required` with profile |
| 5 | **Add WebSocket ticket endpoint** if missing | 🟡 Medium | ❌ Open | `POST /api/v1/websocket/ticket` — returns 10s-expiry ticket for WS auth |
| 6 | **Implement session pre-flight allocation** | 🟡 Medium | ❌ Open | `GET /api/v1/board/preflight?slot_id=<uuid>` → pre-allocate session ID |

> **Full contract details:** See `docs/SERVER_SIDE_REQUIREMENTS.md`

---

## 🔴 Release & Runtime

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 7 | **Bundle `.env` with release binary** | 🔴 High | ❌ Open | App crashes if `.env` missing. Options: `--dart-define`, embed in installer |
| 8 | **Fix release build AOT data path** | 🔴 High | ❌ Open | `launch_err.txt`: `Can't load AOT data from .../Release/data/app.so` — file missing |
| 9 | **Set `SSL_PIN_FINGERPRINT` in `.env`** | 🔴 High | ❌ Open | Production boards need SHA-256 pinning to prevent MITM on classroom network |

---

## 🟡 Stability & Known Bugs

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 10 | **RenderFlex overflow in idle screen** | 🟡 Medium | ✅ Fixed | Row overflows 67px on right. Fix: wrapped title `Text` in `Flexible` with `TextOverflow.ellipsis` |
| 11 | **WebSocket rapid reconnect cycles** | 🟡 Medium | ❌ Open | Logs show rapid connect/disconnect. Not blocking but noisy |
| 12 | **DPAPI file-lock contention on boot** | 🟡 Medium | ❌ Open | `flutter_secure_storage.dat` locked by concurrent processes (`errno = 32`). Retry loop handles it |
| 13 | **Startup watchdog fires at 45s** on slow HW | 🟡 Low | ❌ Open | Briefly releases kiosk constraints. Increase timeout or suppress false alarms |

---

## 🟡 Environment & Config

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 14 | **Set real `FIREBASE_APP_ID`** | 🟡 Medium | ⚠️ Placeholder | Get from Firebase Console → Project Settings |
| 15 | **Set real `FIREBASE_MESSAGING_SENDER_ID`** | 🟡 Low | ⚠️ Placeholder | Get from Firebase Console (only used for logging currently) |
| 16 | **`FIREBASE_API_KEY` restriction** | 🟡 Medium | ❌ Open | Restrict in Firebase Console to Identity Toolkit + Secure Token APIs only |

---

## 🟡 Dependency Health

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 17 | **Update 23 outdated packages** | 🟡 Medium | ❌ Open | Run `flutter pub upgrade` |
| 18 | **Replace 3 discontinued packages** | 🟡 Medium | ❌ Open | `js`, `build_resolvers`, `build_runner_core` are discontinued |
| 19 | **Fix `local_plugins/` test imports** | 🟢 Low | ❌ Open | Missing `import 'package:flutter_test/flutter_test.dart'` generates 370 analyzer warnings |

---

## 🟡 Security & Hardening

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 20 | **CI security scanning** | 🟡 Medium | ❌ Open | Integrate CodeQL/Snyk into `.github/workflows/ci.yml` |
| 21 | **Load test simulation** | 🟡 Medium | ❌ Open | Simulate 1,000 concurrent scans via `scripts/load_test.py` |
| 22 | **Automated E2E UI tests** | 🟡 Medium | ❌ Open | Add Patrol or IntegrationTest for kiosk UX flows |
| 23 | **Stale heartbeat alerting** | 🟡 Medium | ❌ Open | Pipe stale heartbeat events to Slack/email |
| 24 | **Contract validation tests** | 🟢 Low | ❌ Open | Add automated schema alignment tests (Pydantic ↔ Isar) |

---

## 🟡 Time Sync Auto-Correction

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 25 | **Auto-correct system clock** when skew > 1s | 🟡 Medium | ❌ Open | Call PowerShell `Set-Date` from `time_sync_service.dart` |
| 26 | **NTP auto-configuration** via `w32tm` | 🟢 Low | ❌ Open | Configure NTP peers on first boot |
| 27 | **Timezone detection** from server response | 🟢 Low | ❌ Open | Apply IANA → Windows zone via `tzutil` |

---

## 🟡 Hydration Display Gaps (Data Stored But Not Displayed)

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 28 | **Display `roomNumber` in timeline slot & timetable** | 🟡 Medium | ✅ Fixed | `timeline_slot.dart` + `timetable_screen.dart` show room with icon |
| 29 | **Display `subjectCode`/`courseCode` in timetable** | 🟡 Medium | ✅ Fixed | Shown as a badge next to course name in timetable screen |
| 30 | **Display `sectionName` in timetable** | 🟡 Medium | ✅ Fixed | Shown next to faculty name in teal color |
| 31 | **Display `classType` badge (Lab/Tutorial)** | 🟡 Medium | ✅ Fixed | Color-coded badge (purple for Lab, amber for Tutorial), hidden for Lecture |
| 32 | **Persist `timezone` from hydration response** | 🟢 Low | ❌ Open | Server returns `timezone` in both profile and top-level payload; not stored |

---

## 🔵 Auto-Update System (Implemented — See `docs/AUTO_UPDATE_STRATEGY.md`)

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 36 | **Implement `RemoteConfig` model** | 🔵 High | ✅ Done | `lib/models/remote_config.dart` — `RemoteConfig` + `UpdateManifest` with rollout %, SHA-256, force flag |
| 37 | **Implement `RemoteConfigService`** | 🔵 High | ✅ Done | `lib/services/remote_config_service.dart` — apply, persist to SharedPreferences, serve flags |
| 38 | **Extend heartbeat to parse `config` block** | 🔵 High | ✅ Done | `heartbeat_service.dart` — parses `config` from heartbeat response, applies, triggers `UpdateChecker` |
| 39 | **Add feature flag gates to screens** | 🔵 High | ⏳ Pending | Use `RemoteConfigService.isFeatureEnabled()` in idle, timetable, workspace, nav — requires manual gating per screen |
| 40 | **Implement binary auto-updater** | 🔵 Medium | ✅ Done | `lib/services/auto_updater.dart` — download MSI, SHA-256 verify, msiexec silent install, rollout cohort |
| 41 | **Add update overlay UI** | 🔵 Medium | ✅ Done | `lib/presentation/widgets/update_overlay.dart` — blurred full-screen overlay with progress bar |
| 42 | **Add config endpoint to backend** | 🔵 High | ❌ Open | Server must return `config` block in heartbeat response or via `GET /api/v1/board/config` |
| 43 | **Integrate Shorebird CLI** | 🔵 Low | ❌ Open | `shorebird init`, `shorebird release` for rapid Dart code patches (see strategy doc) |
| — | **Version utilities** | 🔵 High | ✅ Done | `lib/core/utils/version.dart` — semver parsing and comparison |
| — | **Update checker (scheduled + event-driven)** | 🔵 High | ✅ Done | `lib/services/update_checker.dart` — periodic timer + heartbeat-triggered check |
| — | **WiX MSI configuration** | 🔵 Medium | ✅ Done | `windows/installer/product.wxs` — file-based MSI with auto-start, Start Menu shortcut |
| — | **CI/CD release workflow** | 🔵 High | ✅ Done | `.github/workflows/release.yml` — build MSI, sign, SHA-256, GH Release on `v*` tag push |

---

## 🟢 Cleanup

| # | Task | Priority | Status | Details |
|---|------|----------|--------|---------|
| 33 | **Remove stale Isar migration path** | 🟢 Low | ❌ Open | Old path in `session_manager.dart:_migrateFromOldPath()` — migrate from `Documents/` to `%APPDATA%` |
| 34 | **Update `.env.example`** to match actual `.env` | 🟢 Low | ❌ Open | Missing `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `ENABLE_DOCUMENTS` |
| 35 | **Fix test lint warnings** | 🟢 Low | ❌ Open | `avoid_print`, `curly_braces_in_flow_control_structures`, unused vars in test files |

---

## ✅ Recently Completed

- ✅ **Registration flow fixed** — `signInWithCustomToken()` exists, `completeRegistration()` sends metadata + exchanges custom token, `_authHeaders()` uses Firebase token directly
- ✅ **TokenManager singleton** — unified token lifecycle (cache → refresh → hard re-auth)
- ✅ **AuthInterceptor 401 replay** — transparent recovery with isolated Dio instance
- ✅ **Structured auth exceptions** — `NoCredentialsException`, `InvalidCredentialsException`
- ✅ **RenderFlex overflow in idle screen** — title wrapped in `Flexible`
- ✅ **Server-side requirements documented** — `docs/SERVER_SIDE_REQUIREMENTS.md`
- ✅ **Hydration display gaps closed** — `roomNumber`, `subjectCode`, `sectionName`, `classType` now rendered in timeline + timetable UI

## ✅ Recently Completed (2026-06-30)

- ✅ **Device registration router mounted** — New `/api/v1/device/register/*` endpoints (`/login`, `/verify`, `/complete`) mounted in `main.py`
- ✅ **PostgreSQL-only registration flow** — Replaced all Firestore auth code with SQLAlchemy 2.0 + asyncpg
- ✅ **`smart_board_id` added to `users` table** — Alembic migration `002_add_smart_board_id.py`
- ✅ **`PendingRegistration` table created** — Alembic migration `003_add_pending_registrations.py`
- ✅ **New Pydantic request schemas** — `DeviceRegisterInitiateRequest`, `DeviceRegisterVerifyRequest`, `DeviceRegisterCompleteRequest`
- ✅ **New `AuthService` registration methods** — `register_initiate_pg`, `register_verify_pg`, `register_complete_pg`
- ✅ **Firebase Admin SDK initialized** — `main.py` now initializes `firebase_admin` for token verification + custom token generation
- ✅ **Deprecated code removed** — Deleted dead Firestore auth code from `main.py`, `core/security.py`, `auth_service.py`
- ✅ **Backend registration tests added** — `tests/test_registration_pg.py` with 5 passing tests (async + mocked DB)
