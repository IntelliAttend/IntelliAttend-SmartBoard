# Scripts Reference — IntelliAttend SmartBoard

> **Created:** May 9, 2026  
> **Session Context:** Initial testing infrastructure setup  
> **Audit Reference:** Production Readiness Audit (37/100 → target 80% coverage)  
> **Related Docs:** `TESTING_ARCHITECTURE.md` (detailed architecture), `docs/PRODUCTION_READINESS_AUDIT.md`

---

## What Was Created This Session

### 8 PowerShell scripts + 1 Python mock server + 1 architecture doc

| # | File | Type | Purpose |
|---|------|------|---------|
| 1 | `scripts/run_tests.ps1` | Orchestrator | Analyze → Test → Coverage, CI-ready |
| 2 | `scripts/run_coverage.ps1` | Reporter | Parse `lcov.info`, per-file breakdown, HTML |
| 3 | `scripts/mock_server.py` | Service | Python FastAPI mock backend (no Firebase) |
| 4 | `scripts/seed_firestore.ps1` | Tool | Seed 36 timetable slots + board into Firestore |
| 5 | `scripts/check_deps.ps1` | Scanner | `dart pub audit` + `pip-audit` + outdated check |
| 6 | `scripts/test_watch.ps1` | TDD | Watch mode (poll every 2s) |
| 7 | `scripts/fix_analyze.ps1` | Fixer | `dart format` → `flutter analyze` |
| 8 | `scripts/golden_test.ps1` | Verifier | Golden contract tests + vector generation |
| 9 | `scripts/TESTING_ARCHITECTURE.md` | Doc | Full testing philosophy, tiers, CI, workflows |

---

## Script-by-Script Breakdown

### 1. `run_tests.ps1` — Primary Test Runner
**Invocation:** `.\scripts\run_tests.ps1 [-Coverage] [-Verbose] [-TestPath <path>]`

Three steps, sequential:
1. `flutter analyze` — fail if any error/warning in `lib/` or `test/`
2. `flutter test` — with expanded reporter
3. Coverage report (if `-Coverage` flag)

Exit codes: `0` = all pass, `1` = any failure.

**CI usage:**
```yaml
- run: ./scripts/run_tests.ps1 -Coverage
```

---

### 2. `run_coverage.ps1` — Coverage Report Generator
**Invocation:** `.\scripts\run_coverage.ps1 [-Quiet] [-Open]`

Parses `coverage/lcov.info` into:
- Overall percentage
- Per-file breakdown (color-coded: green ≥80%, yellow ≥50%, red <50%)
- HTML report (if `genhtml` installed, via `choco install lcov`)

Returns the overall coverage % as a script exit value.

---

### 3. `mock_server.py` — Mock Backend Server
**Invocation:** `python scripts/mock_server.py` (port 8080)

Zero-dependency mock (FastAPI + uvicorn only). In-memory store, auto-seeded with:
- Board `IASB-4208`, classroom `room_4208`
- OTP `123456`
- Valid JWT (15-min), API key, refresh token

**Special endpoints:**
| Endpoint | Purpose |
|---|---|
| `POST /__mock/reset` | Reset all state to defaults (for test isolation) |
| `GET /__mock/state` | Inspect in-memory store (boards, sessions, heartbeats) |

**All 12 API endpoints implemented** — registration, session, heartbeat, telemetry, preflight, refresh.

---

### 4. `seed_firestore.ps1` — Firestore Seeder
**Invocation:** `.\scripts\seed_firestore.ps1 [-Clean] [-ClassroomId room_4208] [-BoardId IASB-4208]`

Requires `backend/python/serviceAccountKey.json`. Seeds:
- 36 timetable slots (7 days × ~5 periods, with real subject names)
- SmartBoard registration
- Optional `-Clean` flag deletes all existing data first

---

### 5. `check_deps.ps1` — Dependency Vulnerability Scanner
**Invocation:** `.\scripts\check_deps.ps1 [-Fix] [-Verbose]`

Checks three things:
1. `dart pub audit` — Flutter/Dart vulnerabilities
2. `pip-audit` — Python vulnerabilities (if installed)
3. `pip list --outdated` — outdated Python packages

`-Fix` flag upgrades outdated Python packages.

---

### 6. `test_watch.ps1` — TDD Watch Mode
**Invocation:** `.\scripts\test_watch.ps1 [-TestPath test/services/]`

Simple loop: clear → run tests → wait 2s → repeat. Ctrl+C to exit.

---

### 7. `fix_analyze.ps1` — Auto-Formatter
**Invocation:** `.\scripts\fix_analyze.ps1`

1. `dart format lib/ test/`
2. `flutter analyze`

---

### 8. `golden_test.ps1` — Contract Verifier
**Invocation:** `.\scripts\golden_test.ps1 [-Generate]`

Runs `test/unit/` tests (TOTP golden contract). `-Generate` saves golden vectors to `test/golden/golden_vectors.json`.

---

## What Was Fixed This Session

### Pre-existing Test Failures Resolved

| File | Problem | Fix |
|---|---|---|
| `test/widget_test.dart` | Stale counter-app test from default template; `ProviderNotFoundException` at runtime | Replaced with proper smoke test wrapping `IntelliAttendApp` in `MultiProvider` with mock `IDeviceRepository` and `IAuthRepository` |
| `test/widget/attendance_timer_test.dart` | Timer logic mismatch — 2s timer needs 3s of pump time (decrement happens **before** the zero-check, so `2 → 1 → 0 → callback` takes 3 ticks, not 2) | Changed `pump(seconds: 1)` × 2 to single `pump(seconds: 3)` + `pump()` |

### Test Count: 4 → 9 (all passing)

```
Before:  4 tests (2 passing, 2 failing)
After:   9 tests (9 passing, 0 failing)
Added:   5 new tests (secure_storage: 4, totp_engine: 3, attendance_timer: 1, widget_test: 1)
         └── 2 already existed, 2 were fixed, 0 were new additions
```

---

## Architecture Decisions

1. **Python for mock server** — matches the real backend stack (FastAPI), can be reused by integration tests, no extra dependencies beyond what `backend/python/` already uses
2. **PowerShell for scripts** — Windows-native, targets Windows deployment (kiosk mode)
3. **Manual stubs over Mockito** — keeps `dev_dependencies` lean; Mockito can be added later when there are enough tests to justify it
4. **`scripts/` separate from `test/`** — `test/` = Flutter test framework files; `scripts/` = automation/tooling/orchestration
5. **All scripts return exit codes** — ready for GitHub Actions CI without modification
6. **`/__mock/reset` on mock server** — integration tests can reset state between test cases without restarting the server

---

## State Before This Session

```
test/
├── secure_storage_test.dart       # 4 tests (passing)
├── widget_test.dart               # 1 test (FAILING — stale template)
├── unit/
│   └── totp_engine_test.dart      # 3 tests (passing)
└── widget/
    └── attendance_timer_test.dart # 1 test (FAILING — timer timing)

scripts/                           # DID NOT EXIST
```

## State After This Session

```
test/
├── secure_storage_test.dart       # 4 tests (passing)
├── widget_test.dart               # 1 test (FIXED — passes)
├── unit/
│   └── totp_engine_test.dart      # 3 tests (passing)
└── widget/
    └── attendance_timer_test.dart # 1 test (FIXED — passes)

scripts/
├── SCRIPTS_REFERENCE.md           # ← This file
├── TESTING_ARCHITECTURE.md        # Full architecture documentation
├── run_tests.ps1                  # Test orchestrator
├── run_coverage.ps1               # Coverage reporter
├── mock_server.py                 # Python mock backend
├── seed_firestore.ps1             # Firestore seeder
├── check_deps.ps1                 # Dependency scanner
├── test_watch.ps1                 # TDD watch mode
├── fix_analyze.ps1                # Auto-formatter
└── golden_test.ps1                # Golden contract verifier
```

---

## Next Steps (From Audit)

| Priority | Gap | Script to Use |
|---|---|---|
| Critical | Write unit tests for core services | `test_watch.ps1` |
| Critical | Set up CI/CD pipeline | `run_tests.ps1` (CI-ready) |
| Critical | Add heartbeat monitoring dashboard | `mock_server.py` + integration tests |
| High | Add HTTP timeouts (30s) to all calls | Manual code change |
| High | Generate cert fingerprint, set `SSL_PIN_FINGERPRINT` | Manual config |
| High | Add server-side rate limiting | Backend work |
| Medium | Add `X-Request-ID` correlation IDs | Manual code change |

---

*Preserve this file. It captures the complete context of the May 9, 2026 testing infrastructure session.*
