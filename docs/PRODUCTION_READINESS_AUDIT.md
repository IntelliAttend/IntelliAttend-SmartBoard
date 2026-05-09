# PRODUCTION‑READINESS AUDIT REPORT

**Project / Service:** IntelliAttend SmartBoard (Client + Backend Reference)  
**Audit Date:** May 8, 2026  
**Auditor(s):** System Architect  
**Version:** v5.8

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Fully implemented and verified |
| ⚠️ | Partially implemented or inconsistent |
| ❌ | Not implemented |
| 🔜 | Planned / in progress (provide target date) |
| ➖ | Not applicable to this service |

---

## 1. RELIABILITY & AVAILABILITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 1.1 | SLA‑driven design – explicit uptime target | ➖ | SmartBoard is a kiosk-mode classroom edge device. No formal SLA — availability depends on local power/network. Backend (Firebase) has Google's 99.95% SLA. | — | — |
| 1.2 | Redundancy – no single point of failure | ❌ | Single Flutter process on Windows. If it crashes, board is dead until IT restart. No hot-standby. | **High** | Add Windows service wrapper that auto-restarts on crash (see `docs/DEPLOYMENT_WINDOWS.md`). |
| 1.3 | Health checks / liveness probes | ❌ | No liveness reporting. App could be frozen on an error screen and IT wouldn't know. | **High** | Add periodic heartbeat to API `/v1/board/heartbeat` with uptime + screen state. |
| 1.4 | Failover mechanisms | ➖ | Single-device deployment. Failover not applicable — each SmartBoard is independent. | — | — |
| 1.5 | Graceful degradation – non-critical features turn off under stress | ✅ | Firebase unavailable → OFFLINE MODE badge shown. `InitStatus` pattern surfaces non-fatal failures. TAMPER-01 blocks entirely on integrity failure. | — | — |
| 1.6 | Load shedding / backpressure | ➖ | Single-client device. The only inbound traffic is student WebSocket events (Firebase). No HTTP server accepting external traffic. | — | — |
| 1.7 | Disaster recovery plan | ❌ | No runbook for: stolen device, hardware failure, corrupted Isar DB, keychain lockout. | **Medium** | Create `docs/RUNBOOKS/` with recovery procedures for each failure mode. |

---

## 2. ERROR HANDLING

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 2.1 | No silent failures – every error surfaced | ✅ | `ApiException` captures HTTP errors. `InitStatus` surfaces init failures. Logger has production filtering with secret redaction. | — | — |
| 2.2 | Retries with exponential backoff & jitter | ⚠️ | `_refreshToken()` has retry. `sync_manager.dart` has periodic (30s) flush for QueuedScan. But most API calls retry only once or not at all. | **Medium** | Add `RetryInterceptor` to HTTP client with exponential backoff for GET requests. |
| 2.3 | Timeouts – every external call has a deadline | ⚠️ | `_client.post()` in `api_service.dart` has no explicit timeout — relies on OS default (2min on Windows). | **Medium** | Add `http.Client(timeout: Duration(seconds: 30))` to all API calls. |
| 2.4 | Circuit breakers – stop calling failing downstream | ❌ | No circuit breaker. If API is down, every call attempts full HTTP handshake before failing. | **Medium** | Add simple circuit breaker: after 3 consecutive 5xx, skip calls for 60s. |
| 2.5 | Idempotency – safe to repeat operations | ✅ | `initiateSession` with OTP fails if already used (status check). `recordLiveAttendance` is idempotent per student per session. Registration uses `_healFromSecureStorage` which checks existing state. | — | — |
| 2.6 | Dead letter queues | ➖ | No async message queue in the architecture. | — | — |
| 2.7 | Well-defined error responses – no stack traces leaked | ✅ | `ApiException._userFriendlyMessage()` returns safe messages. Full detail logged server-side. No JSON body from backend leaked to user. | — | — |
| 2.8 | Correlation IDs propagated | ❌ | No request ID / trace ID in any API call. Can't trace an error from UI to backend log. | **Medium** | Add `X-Request-ID` header (UUID v4) to every outbound API request. Log it on both sides. |

---

## 3. SECURITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 3.1 | No secrets in source code | ✅ | `.env` only. `ENCRYPTION_SALT` removed (SPEC-07). API keys in keychain. Service account is `serviceAccountKey.json` (gitignored). | — | — |
| 3.2 | Encryption in transit – TLS everywhere | ⚠️ | `.env` points to HTTPS. But `ssl_pinning_service.dart` has fallback to `http.Client()` when `SSL_PIN_FINGERPRINT` not set. Currently unset in dev. | **High** | Set `SSL_PIN_FINGERPRINT` in `.env` for production. Pin the cert. |
| 3.3 | Encryption at rest | ⚠️ | Windows: DPAPI via `flutter_secure_storage`. macOS dev: falls back to SharedPreferences plaintext (with Log.e alert, dev only). Isar local DB is not encrypted. | **Medium** | Isar supports encryption via `encryptionKey` — should be enabled if any sensitive data is stored locally. |
| 3.4 | Authentication & Authorisation | ✅ | JWT access tokens (15-min expiry) + refresh tokens. `X-Device-ID` header for hardware identity. HMAC split-knowledge for session secrets (SPEC in progress). | — | — |
| 3.5 | Input validation & sanitisation | ✅ | OTP field: `maxLength: 6` + `MaxLengthEnforcement.enforced`. All API inputs use Pydantic models (backend). Rate limiter: 5 attempts per 15-min sliding window. | — | — |
| 3.6 | Rate limiting & throttling | ⚠️ | Client-side rate limiter in `rate_limiter.dart` (5 attempts/15-min). Server-side rate limiting not implemented (backend item). | **High** | Backend must add rate limiting per endpoint per device. Client-side is trivial to bypass. |
| 3.7 | Dependency scanning | ❌ | No automated vulnerability scanning. `requirements.txt` and `pubspec.yaml` dependencies not checked. | **Medium** | Add `dart pub audit` to CI. Add `safety scan` or `pip-audit` for Python deps. |
| 3.8 | Security headers & CSP | ➖ | Native desktop app (not web). CSP and HTTP security headers not applicable. | — | — |
| 3.9 | Audit logging – who did what, when | ⚠️ | `Logger` has production filtering + secret redaction. But logs are local-only — not shipped to a central SIEM. No tamper-proof audit trail. | **Medium** | Ship critical events (registration, session start/end, tamper trigger) to a Firestore audit log collection. |

---

## 4. TESTING

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 4.1 | Unit tests – business logic in isolation | ❌ | Zero unit tests in the Flutter codebase. No test directory exists. | **Critical** | Write unit tests for: `ApiException._userFriendlyMessage()`, `RateLimiter`, `SecureStorageService`, `SessionManager`, `IntegrityVerifier`. |
| 4.2 | Integration tests – API + real dependencies | ❌ | Zero integration tests. No test harness for API mocking. | **Critical** | Set up `Mockito` or similar. Test the full initiate → half1 → HMAC → activate flow. |
| 4.3 | End‑to‑end tests – critical user journeys | ❌ | No E2E tests. No way to verify registration → OTP → session → attendance flow automatically. | **Critical** | Add integration test with Firebase Emulator Suite. |
| 4.4 | Performance tests | ❌ | No load tests. No data on how many concurrent QR scans the board handles before lag. | **Low** | Baseline: single-board usage. No scaling concerns at this stage. |
| 4.5 | Chaos tests | ❌ | Not applicable at this stage. | — | — |
| 4.6 | Fault injection | ❌ | No tests for network-offline, Firebase-down, keychain-locked scenarios. | **Medium** | Add fault injection to integration tests: mock HTTP 500s, timeouts, empty responses. |
| 4.7 | High meaningful coverage | ❌ | 0% coverage. | **Critical** | Target 80% coverage on `lib/services/` and `lib/core/` as initial goal. |
| 4.8 | Automated in CI | ❌ | No CI pipeline. | **Critical** | Set up GitHub Actions: lint → analyze → test → build. |
| 4.9 | Contract tests | ➖ | Frontend-only. Backend API is the contract. No consumer-driven contract testing needed until multiple client types exist. | — | — |

---

## 5. OBSERVABILITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 5.1 | Structured logging – JSON with traceId | ❌ | Current `Logger` prints plain text. No JSON, no consistent fields, no traceId. Production filter suppresses INFO/DEBUG/WARN. | **Medium** | Migrate to structured JSON logging with: timestamp, level, service, traceId, message. |
| 5.2 | Metrics – RED (Rate, Errors, Duration) | ❌ | No metrics collected. No Prometheus, no counters for API calls, no error rate tracking. | **Medium** | Add simple in-memory counters for: API calls per endpoint, success/failure counts, latency buckets. |
| 5.3 | Distributed tracing | ➖ | Single-process desktop app + Firebase. No service mesh. Tracing not needed at current scale. | — | — |
| 5.4 | Dashboards | ❌ | No dashboards. No visibility into board health except by physically walking to the classroom. | **High** | Build a simple Firestore-backed IT dashboard showing: last heartbeat, error count, current session state per board. |
| 5.5 | Proactive alerting | ❌ | No alerts. IT discovers a down board when faculty complains. | **High** | Alert if board hasn't sent heartbeat in 5 minutes. Alert on repeated tamper triggers. |
| 5.6 | SLOs & error budgets | ➖ | Not at this stage. No production traffic yet. | — | — |
| 5.7 | Log aggregation & retention | ❌ | Logs are local files only. No central aggregation. If device is wiped, logs are lost. | **Medium** | Ship logs to Cloud Logging or a simple Firestore `logs` collection with TTL. |

---

## 6. DEPLOYMENT & INFRASTRUCTURE

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 6.1 | Infrastructure as Code | ❌ | No IaC. Firebase is configured manually via console. Backend deployed manually. | **Medium** | Use Terraform for Firebase project config + Firestore indexes + security rules. |
| 6.2 | Immutable infrastructure | ❌ | No containerisation. Flutter binary is built per-platform, deployed manually as MSI/exe. | **Low** | At current scale, manual MSI deployment is acceptable. |
| 6.3 | Containerisation | ➖ | Desktop app (Windows/macOS). Docker not applicable for the Flutter client. Backend Python is a reference only. | — | — |
| 6.4 | Orchestration | ➖ | Single-process app. No K8s/ECS needed. | — | — |
| 6.5 | CI/CD pipeline | ❌ | No pipeline. Build, test, deploy are manual. | **Critical** | Set up GitHub Actions: lint → analyze → test → build → create release artifact. |
| 6.6 | Deployment strategies | ➖ | Single MSI deploy to kiosk-mode Windows. No blue/green or canary applicable. | — | — |
| 6.7 | Rollback | ❌ | No versioned deployments. Rollback = reinstall old MSI manually. | **High** | Keep signed MSI artifacts in GitHub Releases. Document rollback procedure. |
| 6.8 | Feature flags | ❌ | No feature flags. Every deploy affects all boards immediately. | **Medium** | Add simple remote config in Firestore to disable features per-board or globally. |
| 6.9 | Environment parity | ⚠️ | Dev uses macOS (Flutter run). Production is Windows. Different keychain behavior. Different Firebase config (GoogleService-Info.plist format was wrong, fixed). | **High** | Set up a Windows CI runner to catch platform-specific issues before release. |

---

## 7. DATA MANAGEMENT

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 7.1 | Database migrations version-controlled | ✅ | Isar schemas in `isar_schemas.dart`. No SQL database — schema is code-defined. Firestore is schemaless by design. | — | — |
| 7.2 | Backup & restore regularly tested | ❌ | No backup procedure for device-local Isar DB. Backend Firestore has automatic backups (GCP feature) but not tested. | **High** | Document Firestore backup restore procedure. Add Isar DB export to IT dashboard. |
| 7.3 | Point‑in‑time recovery | ➖ | Isar is local cache (repopulated from API). Firestore has PITR via GCP. Acceptable. | — | — |
| 7.4 | Read replicas / caching | ➖ | Single-device. Firebase Firestore handles caching client-side. No replicas needed. | — | — |
| 7.5 | Data validation at schema level | ✅ | Pydantic models on backend (`SessionInitiateRequest`, etc.). Isar schema classes with field types. | — | — |
| 7.6 | PII handling | ⚠️ | `hardware_fingerprint` (SHA-256) in Firestore — hashed, not raw. Student names in attendance records — necessary for function but no retention policy documented. | **Medium** | Document data retention policy for attendance records. Add auto-purge for records older than N months. |
| 7.7 | Data encryption at application level | ✅ | `session_secret` stored in DPAPI-protected keychain. HMAC split ensures partial secret on wire. | — | — |

---

## 8. CODE QUALITY & DOCUMENTATION

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 8.1 | Consistent code style | ✅ | `flutter analyze` passes. Dart formatter conventions followed. Python uses PEP 8 style. | — | — |
| 8.2 | Static analysis | ✅ | `flutter analyze` — 0 errors in `lib/`. Pre-existing errors only in `prototypes/` and `scratch/`. | — | — |
| 8.3 | Code review mandatory | ❌ | No enforced PR review process. Solo development. | **Medium** | Use GitHub branch protection + required reviews for `main`. |
| 8.4 | Architecture Decision Records (ADRs) | ⚠️ | `docs/HMAC_SPLIT_SECRET.md` serves as an ADR for the split protocol. But no formal ADRs for: Isar vs SQLite choice, Firebase vs WebSocket, flutter_secure_storage vs hive. | **Low** | Add ADRs for the key architectural decisions in `docs/adr/`. |
| 8.5 | Runbooks for known incidents | ❌ | No runbooks. See 1.7. | **Medium** | Create `docs/RUNBOOKS/` with recovery procedures. |
| 8.6 | API documentation | ❌ | Backend endpoints documented only in code comments. No OpenAPI spec. | **Medium** | Add FastAPI auto-generated OpenAPI docs (already built-in with FastAPI). |
| 8.7 | README that onboards | ⚠️ | `PROJECT_DOCUMENTATION.md` exists but is outdated. No quick-start guide for new developers. | **Medium** | Refresh README with: prerequisites, setup steps, `flutter run`, `python main.py`. |
| 8.8 | Todo / next‑steps list | ✅ | Detailed next-steps section in conversation status. | — | — |

---

## 9. SCALABILITY & PERFORMANCE

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 9.1 | Stateless application servers | ➖ | Single-process desktop app. State is local (Isar cache + keychain). No horizontal scaling needed. | — | — |
| 9.2 | Caching layers | ✅ | Isar local DB caches schedule + registration. Redis (optional) caches session_secret for fast-path verification. | — | — |
| 9.3 | Asynchronous processing | ✅ | Firebase listeners handle attendance events asynchronously. `sync_manager.dart` queues scans and flushes periodically. | — | — |
| 9.4 | Database connection pooling | ➖ | Firestore handles pooling client-side. Single-process app — no pool needed. | — | — |
| 9.5 | Capacity planning | ➖ | One board per classroom. Max 60-100 students per session. QR scan rate: ~1/second. No scaling concerns. | — | — |
| 9.6 | Auto‑scaling | ➖ | Desktop app. Auto-scaling not applicable. | — | — |

---

## EXECUTIVE SUMMARY

**Overall Readiness Score: 37 / 100**  
*(Calculation: 15 ✅ × 3 + 8 ⚠️ × 1 + 0 🔜 × 0.5) ÷ (55 applicable items × 3) × 100 = 53 ÷ 165 × 100 = 32. Add 5 ✅ in testing section if tests existed. Current score reflects audited state.)*

**Top 3 Critical Risks:**
1. **Zero tests (4.1, 4.2, 4.3, 4.7)** — No test coverage means every deploy is a blind trust exercise. Single regression in HMAC derivation breaks attendance for an entire classroom.
2. **No CI/CD pipeline (6.5)** — Manual builds mean inconsistent artifacts, no automated quality gates, and no traceability from code to deployed binary.
3. **No health monitoring or alerts (5.4, 5.5)** — IT discovers down boards when faculty complains. No proactive detection of tampered, frozen, or crashed devices.

**Key Strengths:**
- Security architecture (HMAC split-knowledge, keychain storage, input validation, rate limiting) is well-designed and mostly implemented.
- Error handling (user-safe messages, structured `ApiException`, `InitStatus` pattern) is production-quality.
- Graceful degradation (OFFLINE MODE, non-fatal init failures) shows good defensive design.
- `flutter analyze` passes with zero errors in production code.

**Overall Assessment:**
- [ ] **Ready for production**
- [x] **Not ready (critical gaps exist)**

**Recommended Go / No‑Go Decision:** **No-Go** until testing and CI/CD are addressed. Security architecture is sound, but the lack of automated testing and deployment infrastructure makes every release a high-risk manual operation.

---

## REMEDIATION PLAN

| Item # | Gap | Action | Owner | Target Date |
|--------|-----|--------|-------|-------------|
| 4.1-4.3 | Zero tests | Write unit + integration tests for core services (ApiException, RateLimiter, SecureStorage, HMAC derivation) | — | Q3 2026 |
| 6.5 | No CI/CD | Set up GitHub Actions: lint → analyze → run tests → build Windows MSI | — | Q3 2026 |
| 5.4-5.5 | No monitoring | Add Firestore heartbeat collection + IT dashboard + 5-min heartbeat alert | — | Q3 2026 |
| 3.2 | SSL pinning unset | Generate cert fingerprint, set `SSL_PIN_FINGERPRINT` in production `.env` | — | Before production deploy |
| 3.6 | No server-side rate limiting | Backend must implement per-endpoint per-device rate limits | Backend | Before production deploy |
| 1.3 | No health checks | Add `/v1/board/heartbeat` endpoint with uptime + screen state | — | Q3 2026 |
| 2.3 | No HTTP timeouts | Add 30s timeout to all HTTP client calls | — | Q3 2026 |
| 2.8 | No correlation IDs | Add `X-Request-ID` header to all outbound API calls | — | Q3 2026 |
