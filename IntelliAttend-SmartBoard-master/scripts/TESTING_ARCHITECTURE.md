# Testing Architecture — IntelliAttend SmartBoard

> **Version:** 1.0 — May 9, 2026  
> **Scope:** Flutter SmartBoard client + Python mock backend  
> **Goal:** Production-grade testing infrastructure with clear ownership, measurable coverage, and CI-ready automation.

---

## Table of Contents

1. [Directory Layout](#1-directory-layout)
2. [The Three Testing Tiers](#2-the-three-testing-tiers)
3. [Scripts Reference](#3-scripts-reference)
4. [Mock Backend](#4-mock-backend)
5. [Coverage Targets](#5-coverage-targets)
6. [CI Integration](#6-ci-integration)
7. [TDD Workflow](#7-tdd-workflow)
8. [Adding a New Test](#8-adding-a-new-test)
9. [Golden Contracts](#9-golden-contracts)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Directory Layout

```
intelliattend_smartboard/
├── test/                          # Flutter test files (mirrors lib/ structure)
│   ├── unit/                      #   Pure logic tests (no widget tree)
│   │   ├── totp_engine_test.dart  #     TOTP golden contract
│   │   ├── rate_limiter_test.dart #     Rate limiter logic
│   │   └── ...
│   ├── services/                  #   Service-level tests (may mock IO)
│   │   ├── secure_storage_test.dart
│   │   ├── api_service_test.dart
│   │   └── ...
│   ├── widget/                    #   Widget tests (pump, tap, find)
│   │   ├── attendance_timer_test.dart
│   │   └── ...
│   ├── integration/               #   Full flow tests (mock backend)
│   │   ├── registration_flow_test.dart
│   │   └── ...
│   └── widget_test.dart           #   Smoke test (basic renders)
│
├── scripts/                       # Automation & tooling
│   ├── run_tests.ps1              #   Main test orchestrator
│   ├── run_coverage.ps1           #   Coverage report generator
│   ├── test_watch.ps1             #   TDD watch mode
│   ├── mock_server.py             #   Python mock backend
│   ├── seed_firestore.ps1         #   Firestore seed data
│   ├── check_deps.ps1             #   Dependency vulnerability scan
│   ├── fix_analyze.ps1            #   Auto-format + analyze fix
│   ├── golden_test.ps1            #   Golden contract verification
│   └── TESTING_ARCHITECTURE.md    #   This document
│
└── coverage/                      # Generated (gitignored)
    ├── lcov.info                  #   Raw coverage data
    └── html/                      #   HTML report (if genhtml installed)
```

**Key rule:** The `test/` directory mirrors `lib/` one-to-one. Every file in `lib/services/` has a corresponding `test/services/` file.

---

## 2. The Three Testing Tiers

### Tier 1 — Unit Tests (`test/unit/`)
- **What:** Pure logic in isolation. No widget tree, no IO.
- **Target coverage:** 100% of core algorithms
- **Examples:**
  - TOTP token derivation (golden contract)
  - HMAC split-knowledge combination
  - Rate limiter sliding window logic
  - `ApiException._userFriendlyMessage()` mapping
  - `IntegrityVerifier` hashing
- **No mocking needed** — pure functions with known inputs/outputs.

### Tier 2 — Service Tests (`test/services/`)
- **What:** Service classes with mocked dependencies (HTTP, keychain, Isar).
- **Target coverage:** 90%+ of `lib/services/`
- **Examples:**
  - `SecureStorageService` — store/retrieve/expire/clear
  - `ApiService` — auth header generation, token refresh, fallback chain
  - `SessionManager` — session lifecycle
  - `HeartbeatService` — periodic firing
- **Mocking strategy:** Use `flutter_secure_storage` mock, `http.MockClient`, or `Mockito`.

### Tier 3 — Integration / Widget Tests (`test/widget/`, `test/integration/`)
- **What:** UI rendering + full flow with mock backend.
- **Target coverage:** Critical user journeys only
- **Examples:**
  - Registration flow: login → OTP → verify → complete
  - Session flow: initiate → secret → attendance
  - Boot screen state rendering
  - Attendance timer countdown
- **Mock backend:** `scripts/mock_server.py` handles all API calls.

---

## 3. Scripts Reference

### `.\scripts\run_tests.ps1` — Primary test runner
```
USAGE:   .\scripts\run_tests.ps1 [-Coverage] [-Verbose] [-TestPath <path>]
DEFAULT: flutter analyze → flutter test
FLAGS:   -Coverage   also generate coverage report
         -Verbose    show full output on failure
         -TestPath   run specific test file/directory
EXIT:    0 = all pass, 1 = any failure
```

### `.\scripts\run_coverage.ps1` — Coverage reports
```
USAGE:   .\scripts\run_coverage.ps1 [-Quiet] [-Open]
DEFAULT: Run flutter test --coverage, parse lcov.info, print summary
FLAGS:   -Quiet     suppress per-file breakdown
         -Open      open HTML report in browser (requires genhtml)
```

### `.\scripts\mock_server.py` — Mock backend server
```
USAGE:   python scripts/mock_server.py
PORTS:   http://127.0.0.1:8080 (override via MOCK_PORT env var)
DEFAULT BOARD: IASB-4208
DEFAULT OTP:   123456
RESET:   POST /__mock/reset  (clears & re-seeds all state)
STATE:   GET  /__mock/state  (inspect store)
```

### `.\scripts\seed_firestore.ps1` — Seed real Firestore data
```
USAGE:   .\scripts\seed_firestore.ps1 [-Clean] [-ClassroomId room_4208]
NOTE:    Requires serviceAccountKey.json in backend/python/
WARNING: -Clean DELETES all documents in seeded collections!
```

### `.\scripts\check_deps.ps1` — Vulnerability scanning
```
USAGE:   .\scripts\check_deps.ps1 [-Fix] [-Verbose]
CHECKS:  dart pub audit, pip-audit, pip list --outdated
FLAGS:   -Fix   attempt to upgrade outdated Python packages
```

### `.\scripts\test_watch.ps1` — TDD watch mode
```
USAGE:   .\scripts\test_watch.ps1 [-TestPath <path>]
NOTE:    Polls every 2 seconds. Ctrl+C to exit.
```

### `.\scripts\fix_analyze.ps1` — Auto-format then re-analyze
```
USAGE:   .\scripts\fix_analyze.ps1
STEPS:   dart format lib/ test/ → flutter analyze
```

### `.\scripts\golden_test.ps1` — Golden contract tests
```
USAGE:   .\scripts\golden_test.ps1 [-Generate]
CHECKS:  flutter test test/unit/
FLAGS:   -Generate  save golden vectors to test/golden/golden_vectors.json
```

---

## 4. Mock Backend

The mock server (`scripts/mock_server.py`) is a **drop-in replacement** for the real Python backend. It:

- Requires **no Firebase** — all state is in-memory
- Resets to a known state on startup
- Supports explicit reset via `POST /__mock/reset`
- Has **zero dependencies** beyond FastAPI + uvicorn

### How integration tests use it

```
┌─────────────────┐     HTTP     ┌──────────────────┐
│  Flutter Test   │ ──────────►  │  Mock Server     │
│  (integration)  │ ◄──────────  │  :8080           │
└─────────────────┘              └──────────────────┘
                                        │
                                   In-Memory
                                   Store
```

The Flutter test configures `API_BASE_URL` to `http://127.0.0.1:8080`, then runs the real registration/session flow against the mock.

### Pre-seeded test data

| Field | Value |
|---|---|
| Board ID | `IASB-4208` |
| Classroom ID | `room_4208` |
| OTP | `123456` |
| API Key | `bk_live_mock_test_key_12345` |
| JWT | Valid 15-min token (auto-generated) |
| Refresh Token | `rt_<random_hex>` |

### Available mock endpoints

```
POST /api/v1/device/register/login      → OTP sent (123456)
POST /api/v1/device/register/verify     → verification_token
POST /api/v1/device/register/complete   → api_key + JWT + refresh_token
POST /api/v1/device/heartbeat           → stores heartbeat
GET  /api/v1/board/time                 → server timestamp
GET  /api/v1/board/ready                → readiness check
GET  /api/v1/board/preflight?slot_id=X  → pre-allocated session
POST /api/v1/board/session/initiate     → session secret
POST /api/v1/board/auth/refresh         → new JWT
POST /api/v1/board/telemetry            → acknowledged
POST /v1/board/session/create           → session + OTP
POST /__mock/reset                      → RESET state
GET  /__mock/state                      → inspect state
```

---

## 5. Coverage Targets

| Module | Target | Priority | Notes |
|---|---|---|---|
| `lib/services/` | 90% | Critical | Core auth, storage, sync, heartbeat |
| `lib/core/utils/` | 100% | High | Logger, config, helpers |
| `lib/models/` | 100% | High | Schema validation |
| `lib/presentation/screens/` | 70% | Medium | Widget tests for critical screens |
| `lib/presentation/widgets/` | 80% | Medium | Reusable components |
| `lib/data/repositories/` | 80% | High | Repository layer |
| **Overall** | **80%** | **Critical** | Audit requirement |

**Gap to close:** Current coverage is ~5% (4 tests, mostly stale). Need ~50 new tests across all tiers.

---

## 6. CI Integration

The scripts are designed to be CI-native. Every script returns a proper exit code:

```
# GitHub Actions step example
- name: Run tests
  shell: pwsh
  run: ./scripts/run_tests.ps1 -Coverage

- name: Check dependencies
  shell: pwsh
  run: ./scripts/check_deps.ps1
```

### Proposed GitHub Actions workflow

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: ./scripts/run_tests.ps1 -Coverage
      - run: ./scripts/check_deps.ps1
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/
```

---

## 7. TDD Workflow

```
1. Pick a test from the backlog or write a failing test first
2. Run: .\scripts\test_watch.ps1 -TestPath test/services/rate_limiter_test.dart
3. Write implementation code until test passes
4. Run full suite: .\scripts\run_tests.ps1 -Coverage
5. Commit
```

**Recommended test-first order** (from the Production Readiness Audit):

| Sprint | Tests to Write | Script |
|---|---|---|
| Week 1 | `ApiException`, `RateLimiter`, `SecureStorageService` | `.\scripts\test_watch.ps1 test/services/` |
| Week 2 | HMAC derivation, `IntegrityVerifier`, `SessionManager` | `.\scripts\golden_test.ps1` |
| Week 3 | `ApiService` auth headers, token refresh, fallback | `.\scripts\mock_server.py` + integration tests |
| Week 4 | Widget tests: BootScreen, IdleScreen states | `.\scripts\test_watch.ps1 test/widget/` |

---

## 8. Adding a New Test

### For a unit test (`test/unit/`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/utils/my_logic.dart';

void main() {
  group('MyLogic', () {
    test('should compute correctly', () {
      expect(myFunction(2, 2), equals(4));
    });
  });
}
```

### For a service test (`test/services/`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/services/my_service.dart';
// Use Mockito or manual mocks for dependencies

void main() {
  group('MyService', () {
    test('should handle success', () async {
      // 1. Mock HTTP client
      // 2. Call service method
      // 3. Assert expected behavior
    });
  });
}
```

### For an integration test (`test/integration/`):

```dart
// 1. Start mock server (or assume it's running)
// 2. Configure API_BASE_URL to http://127.0.0.1:8080
// 3. Run the full registration flow
// 4. Assert final state via /__mock/state endpoint
```

---

## 9. Golden Contracts

Golden contracts are **immutable test vectors** that define the expected cryptographic output for known inputs. They catch silent regressions in:
- TOTP token derivation
- HMAC split-knowledge combination
- JWT format
- QR code payload encoding

### How they work

1. A known input set is defined (seed, timestamp, session_id)
2. The expected output is computed once and stored as a "golden" value
3. Every test run compares current output against the golden value
4. A mismatch = a breaking change that must be explicitly accepted

### Running golden tests

```
.\scripts\golden_test.ps1           # Verify all golden contracts
.\scripts\golden_test.ps1 -Generate  # Regenerate golden vectors (after intentional change)
```

### Golden vector storage

```
test/golden/golden_vectors.json
```

This file is **checked into version control** and only updated when cryptographic logic is intentionally changed.

---

## 10. Troubleshooting

| Problem | Likely Cause | Solution |
|---|---|---|
| `flutter test` hangs | Firebase not initialized in test | Mock Firebase or use `setupAll` to init once |
| Mock server connection refused | Server not running | Start with `python scripts/mock_server.py` in separate terminal |
| Coverage report is 0% | Tests not hitting any `lib/` code | Check imports — tests may be exercising mocks, not real code |
| `dart pub audit` fails | Known vulnerability in dependency | Update package or add override; suppress with `--ignore` if acceptable |
| Flutter analyze errors in test files | Test code style violations | Run `.\scripts\fix_analyze.ps1` |
| Tests pass locally, fail in CI | Platform difference (macOS vs Windows) | Ensure mock server starts in CI step; check path separators |
| `flutter_secure_storage` fails in test | No platform implementation | Use `setMockInitialValues({})` in `setUp()` |

### Quick diagnostic commands

```powershell
# List all test files
Get-ChildItem -Recurse test/*_test.dart

# Check Flutter + Dart version
flutter --version

# Verify mock server is running
curl http://127.0.0.1:8080/health

# Run a single test file
flutter test test/services/secure_storage_test.dart

# Run tests with verbose logging
flutter test --reporter expanded
```

---

## Appendix: Audit Gap Closure

This testing architecture directly addresses the **Production Readiness Audit** gaps:

| Audit Item | Requirement | How We Close It |
|---|---|---|
| 4.1 | Unit tests | `test/unit/` directory, golden contracts |
| 4.2 | Integration tests | `test/integration/` + `mock_server.py` |
| 4.3 | E2E tests | Mock server full flow + `seed_firestore.ps1` |
| 4.7 | 80% coverage | `run_coverage.ps1` measures and enforces |
| 4.8 | Automated in CI | `run_tests.ps1` returns proper exit codes |
| 3.7 | Dependency scanning | `check_deps.ps1` (dart pub audit + pip-audit) |
| 6.5 | CI/CD pipeline | All scripts are CI-ready with exit codes |
| 2.2 | Retry with backoff | Testable via `ApiService` mock in `test/services/` |
| 2.8 | Correlation IDs | Mock server echoes `X-Request-ID` header |

---

*This document is a living artifact. Update it when new test categories, scripts, or conventions are introduced.*
