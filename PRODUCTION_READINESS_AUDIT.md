# PRODUCTION‑READINESS AUDIT REPORT

**Project / Service:** IntelliAttend SmartBoard  
**Audit Date:** 2026-05-14  
**Auditor(s):** opencode  
**Version:** 5.4.0+1  

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Fully implemented and verified |
| ⚠️ | Partially implemented or inconsistent |
| ❌ | Not implemented |
| 🔜 | Planned / in progress |
| ➖ | Not applicable to this service |

---

## 1. RELIABILITY & AVAILABILITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 1.1 | SLA‑driven design – explicit uptime target | ❌ | No SLA defined. Single-process Windows app. | Low | Define recovery-time objective for classroom kiosk |
| 1.2 | Redundancy – no single point of failure | ⚠️ | Single Flutter process = SPOF. Backend uses Firebase (multi-region). | High | Implement Windows service wrapper with auto-restart on crash |
| 1.3 | Health checks / liveness probes | ✅ | Heartbeat every 5 min (`heartbeat_service.dart`). Boot canary `GET /api/v1/board/ready`. PreFlight T-10/T-3 checks. | — | — |
| 1.4 | Failover mechanisms | ⚠️ | Isar corruption → auto-wipe+recreate. Auth → JWT primary + API Key fallback. No process-level failover. | Medium | Documented in `docs/PRODUCTION_READINESS_AUDIT.md` item 1.2 |
| 1.5 | Graceful degradation | ✅ | 3-tier init system (`main.dart`). Offline queue for attendance. Firestore REST fallback. Non-fatal components (`TimeSync`, `Heartbeat`) degrade independently. | — | — |
| 1.6 | Load shedding / backpressure | ⚠️ | Client-side rate limiter (5/15min) on PIN/OTP. No server-side rate limiting. | High | Backend rate limiter per device per endpoint needed |
| 1.7 | Disaster recovery plan | ⚠️ | `docs/RUNBOOKS/disaster-recovery.md` covers 5 scenarios. Missing: theft, hardware failure, keychain corruption. RTO/RPO not defined. | Medium | Expand runbook; define RTO/RPO |

**Section score:** 4.5 / 7 ✅

---

## 2. ERROR HANDLING

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 2.1 | No silent failures | ✅ | Custom exception hierarchy (`ApiException`, `UnregisteredException`, `UnauthorizedException`, `CircuitBreakerOpenException`). `runZonedGuarded` global handler. | — | — |
| 2.2 | Retries with exponential backoff & jitter | ⚠️ | `ApiService._executeWithRetry` uses exp backoff (1s,2s,4s). **No jitter**. Dio layer has no retry interceptor. | Medium | Add jitter to backoff; add Dio retry interceptor |
| 2.3 | Timeouts – every external call has a deadline | ⚠️ | Most calls timed: Dio 15s, HTTP 30s, Firestore 10-15s. Some raw `http.Client` calls lack explicit timeout. | Medium | Audit all raw `http.Client` calls for timeout |
| 2.4 | Circuit breakers | ⚠️ | `CircuitBreaker` class exists (5 failures, 60s cooldown). Used in `ApiService` per-endpoint. Not in Dio interceptor chain. | Low | Wire into Dio interceptor chain |
| 2.5 | Idempotency | ✅ | OTP single-use. Attendance idempotent per student/session. Registration checks existing state. Session teardown verifies both vaults empty. | — | — |
| 2.6 | Dead letter queues | ❌ | `QueuedScan` in Isar retried indefinitely every 30s. No eviction, no alerting on queue growth. | Medium | Add max-retry count and stale message alerting |
| 2.7 | Well‑defined error responses | ✅ | `ApiException` carries `userMessage` + `statusCode`. `_userFriendlyMessage` maps all HTTP codes. No stack traces leaked. | — | — |
| 2.8 | Correlation IDs propagated | ⚠️ | `X-Request-ID` (UUID) on `ApiService._request()`. `X-Retry-Attempt` on retries. **Not** in Dio interceptor chain. **Not** in log entries. | Medium | Add correlation ID to Dio chain and structured log output |

**Section score:** 5.5 / 8 ✅

---

## 3. SECURITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 3.1 | No secrets in source code | ⚠️ | No hardcoded keys in Dart source. **`.env` with live Firebase API key is committed** (`AIzaSyBazEmYqABDjU9627m5AaVH47piSsB78G8`). `.gitignore` excludes `.env` but it was committed before rule. | **Critical** | Rotate Firebase API key immediately; add `.env` to `.gitignore` pre-commit hook |
| 3.2 | Encryption in transit – TLS | ⚠️ | `API_BASE_URL` uses HTTPS. `SSL_PIN_FINGERPRINT` env var supports cert pinning but is **commented out** in `.env`. `LOCAL_API_URL` is HTTP (loopback, acceptable). | **High** | Enable SSL pinning before production |
| 3.3 | Encryption at rest | ❌ | OS keychain (DPAPI) for secrets: ✅. **Isar local DB is NOT encrypted**. `SecureStorageService.storeIsarEncryptKey()` exists but never called. TODO at `session_manager.dart:10`. | **Critical** | Wire up Isar encryption key before production |
| 3.4 | Authentication & Authorisation | ✅ | Firebase Identity Toolkit REST API (JWT). Token auto-refresh with 60s safety margin. Custom token exchange. Auth interceptor on all Dio calls. | — | — |
| 3.5 | Input validation & sanitisation | ✅ | Form validators with `maxLength: 6`. `TextInputType.number` for PIN. API params via `jsonEncode` (no string interpolation). Pydantic models server-side. | — | — |
| 3.6 | Rate limiting & throttling | ⚠️ | **Client-side only** (`RateLimiter`: 5 attempts/15min sliding window). Trivially bypassed. **No server-side rate limiting.** | **High** | Implement per-device per-endpoint rate limits on backend |
| 3.7 | Dependency scanning | ⚠️ | CI runs `dart pub audit` and `pip-audit`. Both use `\|\| echo "::warning::"` — **failures silently hidden**. No Dependabot/Snyk config. | Medium | Make audit failures break the build; add Dependabot |
| 3.8 | Security headers & CSP | ➖ | Native Windows desktop app. CSP not applicable. | — | — |
| 3.9 | Audit logging | ⚠️ | Structured JSON logging in production. Secret redaction (`eyJ...`, `session_secret_*`). **No central audit log**: critical events not shipped to Firestore. | Medium | Ship critical events (registration, session start/end, tamper) to Firestore audit collection |
| — | Screen capture prevention | ✅ | `SetWindowDisplayAffinity(WDA_MONITOR)` via FFI in `absoluteLocked` mode. Blocks screenshot, recording, screen share. | — | — |
| — | Single-instance guard | ✅ | PID-based exclusive file lock prevents duplicate processes (`main.dart:148-228`). | — | — |
| — | Runtime integrity verification | ✅ | `IntegrityVerifier` checks build-time hash + code signature at startup. Tamper blocks startup + wipes keychain. | — | — |

**Section score:** 7 / 10 ✅ (+ 3 bonus items)

---

## 4. TESTING

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 4.1 | Unit tests – business logic in isolation | ✅ | 8 unit files in `test/unit/`: circuit_breaker, rate_limiter, totp_engine, split_knowledge, kiosk_service, session_manager, api_exception, integrity_verifier. | — | — |
| 4.2 | Integration tests – API + real dependencies | ⚠️ | `test/integration/api_service_test.dart` tests HTTP pipeline with real sockets. `test/secure_storage_test.dart` tests keychain CRUD. Missing: Firestore, Isar, presentation integration tests. | Medium | Add integration tests for Firestore client, Isar operations |
| 4.3 | End‑to‑end tests – critical user journeys | ❌ | No full E2E tests for boot→registration→session→attendance→teardown flow. | High | Add E2E tests for critical user journey |
| 4.4 | Performance tests – load tests | ⚠️ | QA test files include performance checks: render latency (10k iterations), drift accumulation (100k iterations), CPU stress timing. No structured load testing with expected peak traffic. | Low | Add load test script for QR scanning at capacity |
| 4.5 | Chaos tests – simulate dependency failures | ❌ | No chaos tests. No simulated network failure, isolate crash, or keychain unavailability tests. | Medium | Add chaos tests for dependency failure scenarios |
| 4.6 | Fault injection – test retry & circuit breaker | ⚠️ | Integration test verifies retry on 503. Unit test verifies circuit breaker opens after 3 failures. No Dio interceptor fault injection. | Low | Add Dio interceptor fault injection tests |
| 4.7 | High meaningful coverage (>80% core) | ⚠️ | 14 test files (7,000+ lines). `scripts/run_coverage.ps1` exists but coverage data not tracked in CI. | Medium | Enforce 80% coverage gate in CI |
| 4.8 | Automated in CI – tests block merging | ⚠️ | `flutter test` runs in CI. No coverage gate. Audit step failures suppressed with `\|\| echo "::warning::"`. | High | Make test & audit failures block PR merge |
| 4.9 | Contract tests – producer/consumer API match | ✅ | TOTP Golden Contract (`test/unit/totp_engine_test.dart`). Split-Knowledge Protocol tests (`test/unit/split_knowledge_test.dart` + `backend/python/tests/test_split_knowledge.py`). `scripts/golden_test.ps1` runner. | — | — |

**Section score:** 5 / 9 ✅

---

## 5. OBSERVABILITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 5.1 | Structured logging – JSON with traceId | ⚠️ | `_JsonPrinter` in release mode: `{"timestamp","level","message","logger"}`. **Missing: traceId, service name, version, environment**. INFO/DEBUG suppressed in release (only WARN+ emitted). | Medium | Add traceId, service, version fields; emit INFO in release for operational events |
| 5.2 | Metrics – RED for every endpoint | ❌ | `SystemMetricsService` collects memory/CPU via PowerShell (4min cache). `HeartbeatService` sends metrics. **No Prometheus, no RED (Rate/Errors/Duration), no request counters.** | **High** | Add key business metrics: QR scans/min, session duration, API error rate |
| 5.3 | Distributed tracing | ➖ | Single-process desktop app. No service mesh. Correlation IDs exist per-request but not in logs. | — | — |
| 5.4 | Dashboards – real-time health view | ❌ | No Grafana/Datadog config. Backend has `GET /api/v1/admin/heartbeats` and `/stale` endpoints (data source, not dashboard). | Medium | Build simple heartbeat dashboard from Firestore data |
| 5.5 | Proactive alerting | ❌ | Stale heartbeat detection exists (5min threshold). **No alerting channel** (email, Slack, PagerDuty) connected. | **High** | Wire heartbeat failure alerts to IT notification channel |
| 5.6 | SLOs & error budgets | ❌ | Not defined. No error budget tracked. | Low | Define SLO for QR scan success rate and session availability |
| 5.7 | Log aggregation & retention | ❌ | Local files only. `docs/operations/log-aggregation.md` documents 3 options (Fluentd, CloudWatch Agent, custom forwarder) but **none implemented**. | Medium | Implement log forwarding to central sink (e.g., Loki, CloudWatch) |

**Section score:** 0.5 / 7 ✅

---

## 6. DEPLOYMENT & INFRASTRUCTURE

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 6.1 | Infrastructure as Code | ❌ | No Terraform, CloudFormation, or Pulumi anywhere. Backend deployed manually. | **High** | IaC for backend infrastructure (Firestore rules, IAM, networking) |
| 6.2 | Immutable infrastructure | ❌ | No containerisation. No image-based deployment. | Medium | Containerise backend with Docker |
| 6.3 | Containerisation – Docker | ❌ | **No Dockerfile, no docker-compose** anywhere in project. | **High** | Add Dockerfile + docker-compose for backend |
| 6.4 | Orchestration – Kubernetes, ECS | ❌ | No orchestrator config (Helm, ECS task defs, etc.). | Low | Not needed at current scale; add when multi-board |
| 6.5 | CI/CD pipeline – automated build → deploy | ⚠️ | CI exists (`dart analyze`, `flutter test`, `dart pub audit`). **No CD** — deployment is manual (`flutter build windows`, manual MSI install). | **High** | Add automated Windows build artifact + release pipeline |
| 6.6 | Deployment strategies – blue/green, canary | ➖ | Kiosk installed per-classroom. Canary/blue-green not applicable for physical deployment. | — | — |
| 6.7 | Rollback – quick automated rollback | ❌ | Manual rollback: reinstall previous MSI from GitHub Releases. No automated rollback. | Medium | Keep last 3 versions as downloadable MSIs; document rollback procedure |
| 6.8 | Feature flags – decouple deploy from release | ⚠️ | `RemoteConfigService` reads from Firestore `config/feature_flags` (5min refresh). `AppConfig` reads `.env`. Partial coverage — not all features flag-gated. | Low | Add feature flag for major new features |
| 6.9 | Environment parity – staging mirrors production | ⚠️ | `.env.example` documents dev config. Production URL (`api.intelliattend.com`) referenced in comments but not actively configured. No separate staging/prod env separation in CI. | High | Set up staging environment that mirrors production |

**Section score:** 1.5 / 9 ✅

---

## 7. DATA MANAGEMENT

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 7.1 | Database migrations version-controlled | ⚠️ | Isar schema is code-defined (no formal migration scripts). Firestore is schemaless. Migration scripts exist in `backend/` for hierarchical model migration. | Low | Add schema version number to Isar for future migrations |
| 7.2 | Backup & restore regularly tested | ❌ | **No backup mechanism for local Isar DB.** DeviceRegistration loss = IT-assisted re-registration. Firestore has GCP auto-backup (not tested). | **Critical** | Implement Isar DB export/backup; test Firestore restore |
| 7.3 | Point‑in‑time recovery | ➖ | Local Isar: not applicable. Firestore: GCP-managed PITR. | — | — |
| 7.4 | Read replicas / caching | ✅ | Multiple caching layers: Isar (local), Redis (optional backend), in-memory caches with TTLs (4min metrics, process-lifetime fingerprint, 5min remote config). | — | — |
| 7.5 | Data validation at schema level | ✅ | Isar schemas define types + indexes. Backend uses Pydantic models. API responses explicitly type-checked. | — | — |
| 7.6 | PII handling – retention, compliance | ⚠️ | `docs/operations/pii-retention.md` documents all PII collected with retention periods. **No DPIA document.** Auto-purge via Firestore TTL configured but not verified active. Student names lack documented retention policy. | **High** | Complete DPIA; verify Firestore TTLs active; document name retention |
| 7.7 | Data encryption at application level | ❌ | OS keychain encrypted (DPAPI). **Isar DB not encrypted** — student IDs, registration data in plaintext locally. Infrastructure exists (`SecureStorageService.storeIsarEncryptKey()`) but not wired. | **Critical** | Connect Isar encryption key before production |

**Section score:** 3 / 7 ✅

---

## 8. CODE QUALITY & DOCUMENTATION

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 8.1 | Consistent code style – formatters & linters | ✅ | `flutter_lints` ruleset. Default `dart format`. No custom strict rules but `flutter analyze` passes with 0 errors. | — | — |
| 8.2 | Static analysis – code quality & security | ⚠️ | `dart analyze lib/ test/` in CI. `dart pub audit` + `pip-audit` run but **failures are hidden** (`\|\| echo "::warning::"`). | Medium | Make static analysis failures break the build |
| 8.3 | Code review mandatory | ⚠️ | `docs/BRANCH_PROTECTION.md` specifies 1-reviewer policy. **No `CODEOWNERS` file.** `CONTRIBUTING.md` references obsolete architecture. | Medium | Add CODEOWNERS; update CONTRIBUTING.md |
| 8.4 | Architecture Decision Records (ADRs) | ⚠️ | 2 ADRs exist (`0001`, `0002`). Missing ADRs for Isar vs SQLite, Firebase vs WebSocket, HMAC split-knowledge, flutter_secure_storage. | Low | Document remaining key decisions as ADRs |
| 8.5 | Runbooks for known incidents | ⚠️ | `docs/RUNBOOKS/disaster-recovery.md` covers 5 scenarios. Missing: theft, hardware failure, keychain corruption. RTO/RPO undefined. | Medium | Expand runbook; define RTO/RPO |
| 8.6 | API documentation – OpenAPI/Swagger | ⚠️ | FastAPI auto-generates OpenAPI at `/docs`. Dart client has extensive inline docs. No published OpenAPI spec in repo. | Low | Publish OpenAPI spec to `docs/api/` |
| 8.7 | README that onboards new developers | ✅ | 478-line README with: badges, TOC, quick start, security model, backend API spec, architecture table, project tree, version history. Missing: CI/CD badge, coverage badge. | — | — |
| 8.8 | Todo / next-steps list acknowledges trade-offs | ✅ | `Known Issues & TODOs` in README. 17 TODO/FIXME patterns in code (well-tracked, low count). `docs/PRODUCTION_HARDENING.md` lists 7-phase hardening plan. | — | — |

**Additional documentation found:**

| Document | Quality |
|----------|---------|
| `docs/ARCHITECTURE_DIAGRAM.md` — 12 Mermaid diagrams (C4, sequence, flowcharts) | ✅ Excellent |
| `docs/HMAC_SPLIT_SECRET.md` — 12-section protocol specification | ✅ Excellent |
| `docs/SECURE_AUTH_ARCHITECTURE.md` — Auth migration documentation | ✅ Excellent |
| `docs/PRODUCTION_HARDENING.md` — 7-phase hardening checklist | ✅ Excellent |
| `lib/` code comments — AUDIT references, rationale, race condition notes | ✅ Excellent |

**Section score:** 6 / 8 ✅

---

## 9. SCALABILITY & PERFORMANCE

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|----------------|
| 9.1 | Stateless application servers | ⚠️ | **App is stateful** (Isar local DB, SecureStorage, in-memory caches). This is by design — single kiosk per classroom. Backend (FastAPI) is stateless. | — | — |
| 9.2 | Caching layers | ✅ | Isar local vault (persistent), Redis (optional server-side), in-memory caches (fingerprint: process-lifetime, metrics: 4min, config: 5min). | — | — |
| 9.3 | Asynchronous processing | ✅ | Timers for background services (heartbeat 5min, sync 30s, preflight 1min, orchestrator 1min, watchdog 10s). Dart Isolate for TOTP generation. Serialization guards on all timer callbacks. | — | — |
| 9.4 | Database connection pooling | ✅ | Single-instance Isar (local embedded DB). Dio connection pool (15s connect/receive timeout). Firebase Admin SDK handles its own pooling. | — | — |
| 9.5 | Capacity planning – know per-instance limits | ❌ | No load tests. No data on max concurrent QR scans. Assumption: 60-100 students/session, ~1 scan/sec. | Low | Run load test to validate assumptions |
| 9.6 | Auto-scaling | ➖ | Single kiosk per classroom. Auto-scaling not applicable. | — | — |

**Section score:** 3.5 / 6 ✅

---

## EXECUTIVE SUMMARY

**Overall Readiness Score: 36 / 64 applicable items = 56%**

### Top 5 Critical Risks

1. **🔴 Isar local database not encrypted** — `SecureStorageService.storeIsarEncryptKey()` exists but is never called. Student IDs, registration data, and queued scans are in plaintext on disk. (`session_manager.dart:10`)

2. **🔴 Live Firebase API key committed to repo** — `.env` contains key `AIzaSyBazEmYqABDjU9627m5AaVH47piSsB78G8`. Even though `.gitignore` excludes `.env`, it was committed before the rule was added. Rotate immediately.

3. **🔴 No server-side rate limiting** — Client-side `RateLimiter` (5/15min) is trivially bypassed. Backend must enforce per-device per-endpoint limits.

4. **🔴 No backup for local Isar DB** — `DeviceRegistration` loss requires IT-assisted re-registration. No export/backup mechanism.

5. **🔴 SSL certificate pinning disabled** — `SSL_PIN_FINGERPRINT` is commented out in `.env`. MITM on classroom network could intercept all API traffic.

### Key Strengths

- **Graceful degradation** — Tiered init, offline attendance queue, Isar corruption auto-recovery, component-level failure isolation.
- **Comprehensive security architecture** — JWT auth, HMAC split-knowledge, DPAPI keychain, runtime integrity verification, screen capture prevention, single-instance guard.
- **Excellent documentation** — 12 Mermaid architecture diagrams, ADRs, runbook, PII retention policy, security model docs, HMAC protocol spec.
- **Crash recovery as first-class feature** — Mid-session crash recovery, stale session cleanup, vault teardown verification.
- **Defensive coding patterns** — Circuit breakers, rate limiters, correlation IDs, serialization guards, `runZonedGuarded` global handler.

### Category Scores

| Category | Score | Status |
|----------|-------|--------|
| 1. Reliability & Availability | 4.5 / 7 (64%) | ⚠️ Needs improvement |
| 2. Error Handling | 5.5 / 8 (69%) | ⚠️ Needs improvement |
| 3. Security | 7 / 10 (70%) | ⚠️ Needs improvement |
| 4. Testing | 5 / 9 (56%) | ❌ Major gaps |
| 5. Observability | 0.5 / 7 (7%) | ❌ Critical gaps |
| 6. Deployment & Infrastructure | 1.5 / 9 (17%) | ❌ Critical gaps |
| 7. Data Management | 3 / 7 (43%) | ❌ Major gaps |
| 8. Code Quality & Documentation | 6 / 8 (75%) | ✅ Strong |
| 9. Scalability & Performance | 3.5 / 6 (58%) | ⚠️ Needs improvement |

### Overall Assessment

- [ ] **Ready for production**
- [ ] **Ready with caveats (minor improvements needed)**
- [x] **Not ready (major gaps exist)**

### Recommended Go / No‑Go Decision

**NO-GO** — 5 critical risks must be resolved before production deployment. Minimum viable production gate requires:
1. Isar encryption wired up
2. SSL pinning enabled
3. Firebase API key rotated
4. Server-side rate limiting implemented
5. Local DB backup mechanism added

---

## REMEDIATION PLAN

| Item # | Gap | Action | Owner | Target Date | Priority |
|--------|-----|--------|-------|-------------|----------|
| C1 | Isar DB not encrypted | Wire `SecureStorageService.storeIsarEncryptKey()` into `SessionManager.init()` | — | — | Critical |
| C2 | Live Firebase API key committed | Rotate key `AIzaSyBazEmYqABDjU9627m5AaVH47piSsB78G8`; add `.env` to pre-commit hook | — | — | Critical |
| C3 | SSL pinning disabled | Set `SSL_PIN_FINGERPRINT` in production `.env` | — | — | Critical |
| C4 | No server-side rate limiting | Implement per-device per-endpoint rate limits on FastAPI backend | — | — | Critical |
| C5 | No local DB backup | Add Isar DB export mechanism (manual + automatic) | — | — | Critical |
| H1 | Observability near-zero | Add structured log shipping + heartbeat dashboard + stale-device alerting | — | — | High |
| H2 | No CI/CD deployment | Add Windows MSI build pipeline + release automation | — | — | High |
| H3 | No Docker / IaC | Containerise backend; add Terraform for Firestore rules + IAM | — | — | High |
| H4 | PII/DPIA incomplete | Complete Data Protection Impact Assessment; verify Firestore TTLs | — | — | High |
| H5 | Test coverage not enforced | Add coverage gate (80%) to CI; make audit failures break the build | — | — | High |
| M1 | No E2E tests | Add critical user journey E2E tests | — | — | Medium |
| M2 | Runbook incomplete | Add theft, hardware failure, keychain corruption scenarios | — | — | Medium |
| M3 | Correlation IDs incomplete | Add correlation ID to Dio interceptor chain + structured log output | — | — | Medium |
| M4 | No chaos tests | Add fault injection tests for network failure, isolate crash | — | — | Medium |
| M5 | Dead letter queue absent | Add max-retry count + stale queue alerting for QueuedScan | — | — | Medium |
| L1 | No load tests | Run load test to validate 60-100 concurrent scan assumptions | — | — | Low |
| L2 | Missing ADRs | Document Isar, Firebase, HMAC split-knowledge decisions as ADRs | — | — | Low |
| L3 | CONTRIBUTING.md outdated | Update to match current Flutter/FastAPI architecture | — | — | Low |
| L4 | CODEOWNERS missing | Add CODEOWNERS file for automated reviewer assignment | — | — | Low |

---

*Audit generated 2026-05-14. All evidence collected from codebase at `D:\Dev\IntelliAttend-SmartBoard`.*
