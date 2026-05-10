# Session Log — 2026-05-10

## Theme
Production readiness hardening: infrastructure resilience, backend hardening, testing, and crash investigation.

---

## Completed Work

### S3 — main.dart 3-Tier Startup Refactor
- Split `main()` initialization into blocking (tier 1), timed (tier 2), fire-and-forget (tier 3) phases.
- `_initTier3()` wrapped with `unawaited().catchError()` for error-tolerant background init.
- `_initializeBackgroundProtocols()` changed from `async void` to `Future<void>` so callers can `.catchError()`.
- Verified: `flutter analyze` 0 errors, `flutter test` 40/40 passing.

### Warning Cleanup
- Fixed 20+ unused imports, unused fields, dead code across 8 files:
  - `kiosk_service.dart`, `window_orchestrator_service.dart`, `main.dart`
  - `heartbeat_service.dart`, `attendance_screen.dart`, `boot_screen.dart`
  - `settings_screen.dart`, `idle_screen.dart`, `timetable_screen.dart`

### Backend Heartbeat Endpoints (O1/O2)
- `GET /api/v1/admin/heartbeats` — all boards with status, last heartbeat, IP, version.
- `GET /api/v1/admin/heartbeats/stale` — boards missing ≥5 min heartbeat.
- `HeartbeatService.get_all_status()` in Python backend.

### Security Hardening
- **O3**: `SslPinningService` reads `SSL_PIN_FINGERPRINT` from `.env`.
- **O6**: `dart pub audit` + `pip-audit` steps added to CI workflow.
- **O13**: `docs/BRANCH_PROTECTION.md` — required PR reviews, status checks, no bypass, restricted push.

### Logging & Observability
- **O7**: `docs/RUNBOOKS/disaster-recovery.md` — rollback procedure with RTO/RPO.
- **O5**: `docs/operations/log-aggregation.md` — Fluentd / CloudWatch / custom forwarder options.
- **O4**: `_JsonPrinter` in `kReleaseMode` — structured JSON lines logging.
- **O10-O15**: PII retention policy, RUNBOOKS directory, ADR directory (2 ADRs), FastAPI OpenAPI docs.

### Remote Config (O8)
- `lib/services/remote_config_service.dart` — Firestore-backed feature flags.
- 5-minute auto-refresh interval.
- In-memory map storage; fallback defaults on Firestore failure.

### Rate Limiting (O10)
- `backend/python/middleware/rate_limit_middleware.py` — sliding window, 60 req/min per IP+device.
- Skips `/api/v1/admin/*` endpoints.
- Emits `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers.
- Returns 429 with `Retry-After` on throttle.
- Integrated into `backend/python/main.py` at line 49.

### Testing Expansion
- **T1-T5**: 14 new unit tests:
  - `RateLimiter` — 5 tests (basic throttle, window expiration, fractional TUs, multi-identity isolation, unlimited safe).
  - `ApiException` — 4 tests (user-safe messages, `UnregisteredException`, `UnauthorizedException`, factory `fromStatusCode`).
  - `IntegrityVerifier` — 2 tests (valid HMAC passes, tampered payload fails).
  - `SessionManager` — 2 tests (verify admin PIN success, wrong PIN fails).
- **Integration (AUDIT-4.2)**: `test/integration/api_service_test.dart` — 11 tests against local `HttpServer`:
  - 200 success, 401 forbidden, 404 unregistered, 503 triggers retry.
  - `X-Request-ID` header present on all outbound requests.
  - `X-Retry-Attempt` increments across 3 retries.
  - Heartbeat `send()` best-effort (never throws).
  - `verifyAdminPin` error isolation (no cross-test leakage).
- Total: **40 tests passing** (up from 29).

### Resilience (I1-I6)
- **30s timeout** on all HTTP requests via `httpClient.timeout()`.
- **UUID v4 `X-Request-ID`** on every outbound API call.
- **CI workflow** with `dart analyze lib/ test/` (skips `local_plugins/`).
- **`INTEGRITY_HASH`** via `--dart-define=INTEGRITY_HASH=...`.
- **Retry interceptor** — exponential backoff 1s/2s/4s, max 3 retries, only on 5xx.
- **Circuit breaker** (`circuit_breaker.dart`) — 5-failure threshold, 60s cooldown, half-open trial, 6 tests.

### Error Handling
- **O16**: Fixed unused `_streamError` field — renamed to `_errorMessage`, now displayed in UI.
- **`runZonedGuarded`**: Wraps entire `main()` body including `WidgetsFlutterBinding.ensureInitialized()` to prevent zone mismatch.
- **`FlutterError.onError`**: Registered to complement `runZonedGuarded`.
- **Brightness warnings**: `screen_brightness` plugin `"Problem getting monitor brightness"` caught gracefully in `kiosk_service.dart` try-catch.

### Crash Investigation
- **Confirmed**: EXE standalone crash within ~10s of launch (verified via `Start-Process` + PID monitoring loop — process terminates with exit code, not a debugger disconnect).
- **Diagnosis**: No Dart exception caught by `runZonedGuarded` — strongly suggests **native-level abort** (plugin segfault, native `exit()`, or Fatal Error in native code).
- **Hypothesis candidates**:
  1. `screen_brightness` plugin calling native Windows API on unsupported monitor.
  2. `window_manager` plugin native call.
  3. `connectivity_plus` plugin stream listener in `SyncManager.init()`.
  4. `firebase_*` plugin native initialization on Windows (not officially supported).
  5. Periodic timer callbacks running on isolate/thread that triggers native abort.

---

## Test Results
| Suite | Count | Status |
|-------|-------|--------|
| `test/services/api_exception_test.dart` | 4 | ✅ |
| `test/services/secure_storage_service_test.dart` | 2 | ✅ |
| `test/services/rate_limiter_test.dart` | 5 | ✅ |
| `test/services/integrity_verifier_test.dart` | 2 | ✅ |
| `test/services/session_manager_test.dart` | 2 | ✅ |
| `test/core/circuit_breaker_test.dart` | 6 | ✅ |
| `test/integration/api_service_test.dart` | 11 | ✅ |
| Other pre-existing | 8 | ✅ |
| **Total** | **40** | **✅ All passing** |

---

## Files Created
| File | Purpose |
|------|---------|
| `lib/services/remote_config_service.dart` | Firestore feature flags |
| `lib/core/network/retry_interceptor.dart` | Exponential backoff retry |
| `lib/core/network/circuit_breaker.dart` | Circuit breaker pattern |
| `test/services/rate_limiter_test.dart` | Rate limiter unit tests |
| `test/services/api_exception_test.dart` | API exception tests |
| `test/services/integrity_verifier_test.dart` | HMAC integrity tests |
| `test/services/session_manager_test.dart` | Session manager tests |
| `test/integration/api_service_test.dart` | API service integration tests |
| `test/core/circuit_breaker_test.dart` | Circuit breaker tests |
| `backend/python/middleware/rate_limit_middleware.py` | Sliding window rate limiter |
| `docs/RUNBOOKS/disaster-recovery.md` | Rollback procedure |
| `docs/operations/log-aggregation.md` | Log aggregation options |
| `docs/BRANCH_PROTECTION.md` | Branch protection configuration |
| `docs/adr/*` | Architecture Decision Records |

---

## Blockers
- **Isar encryption (O9)**: `SecureStorageService.storeIsarEncryptKey()` written but blocked — Isar 3.1.0+1 lacks `encryptKey`. Requires Isar ≥3.2.0.

---

## Next Session Tasks
1. **Root-cause silent crash** — Add file-based timestamp logger at init; narrow by disabling services; check Windows Event Viewer.
2. **Complete remaining O-items** from production readiness audit.
3. **Consider CI/CD pipeline** (GitHub Actions: analyze → test → build MSI).
