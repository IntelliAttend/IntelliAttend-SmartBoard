# `PRODUCTION‑READINESS AUDIT REPORT`

**Project / Service:** IntelliAttend SmartBoard Ecosystem  
**Audit Date:** July 20, 2026  
**Auditor(s):** opencode (Automated Code Audit)  
**Version:** SmartBoard v5.5.0 / Backend FastAPI (PostgreSQL-backed)  

---

## How to Use This Template

For each item, choose the **Status** from the legend below and provide concrete **Evidence** (a link, a command, a file path, a screenshot, or a "not applicable" reason).  
If status is **Partially** or **Not Implemented**, you **must** enter a risk level ( **Critical / High / Medium / Low** ) and a suggested remediation in the **Action Required** column.

**Status Legend**:

| Symbol | Meaning |
|--------|---------|
| ✅ | Fully implemented and verified |
| ⚠️ | Partially implemented or inconsistent |
| ❌ | Not implemented |
| 🔜 | Planned / in progress (provide target date) |
| ➖ | Not applicable to this service |

---

## 1. RELIABILITY & AVAILABILITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required (if ⚠️ or ❌) |
|---|-------------|--------|-------------------|------|------------------------------|
| 1.1 | SLA‑driven design – explicit uptime target (e.g., 99.9%) | ⚠️ | `README.md` mentions "enterprise-grade" target. `TODO_HARDENING.md` lists "SLO Definition" as open. No formal SLA document exists. | Low | Define explicit SLOs (e.g., 99.9% monthly uptime) in `docs/ARCHITECTURE.md`. |
| 1.2 | Redundancy – multiple instances, no single point of failure | ⚠️ | Backend is stateless FastAPI (horizontally scalable in theory). Single PostgreSQL instance (`pool_size=10, max_overflow=20`). No DB replicas. Redis used as cache only. | Medium | Deploy PostgreSQL with at least one read replica. Use Redis Sentinel or managed Redis for HA. |
| 1.3 | Health checks / liveness probes – system can tell if alive and ready | ✅ | `GET /health` at `backend/python/main.py:95` checks PostgreSQL (`SELECT 1`) and Redis (`ping`). Returns 200/503 with `{"status": "healthy", "checks": {...}, "timestamp": ...}`. `GET /api/v1/board/ready` verifies board is registered in users table. | - | |
| 1.4 | Failover mechanisms – automatic switch to standby components | ❌ | No DB failover. No Redis Sentinel. Single PostgreSQL instance. `CacheService` falls back to in-memory dict on Redis failure, but this is degradation, not failover. | High | Implement PostgreSQL streaming replication + automatic failover (e.g., Patroni, pgBouncer, or managed service). |
| 1.5 | Graceful degradation – non‑critical features turn off under stress | ✅ | `CacheService` (`services/cache_service.py:29`) falls back to in-memory dict when Redis unavailable. Flutter app uses Isar local vault when API unreachable. `CircuitBreaker` opens after 5 failures, failing fast instead of cascading. Feature flags (`enable_video_background`, `enable_documents`) allow disabling non-critical features. | - | |
| 1.6 | Load shedding / backpressure – refuses excess traffic | ✅ | `RateLimitMiddleware` (`middleware/rate_limit_middleware.py:63`) enforces tiered limits: auth 5/min, ticket 10/min, general 60/min, health 120/min. Returns 429 with `Retry-After: 60` and `X-RateLimit-Remaining` headers. Admin routes exempt (protected by Firebase auth + RBAC). | - | |
| 1.7 | Disaster recovery plan – runbooks, RPO/RTO defined, regular drills | ✅ | `docs/RUNBOOKS/disaster-recovery.md` exists. `TODO_HARDENING.md` completed items include "Zero-Trust Cleanup" and "Async Everything". | - | |

---

## 2. ERROR HANDLING

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 2.1 | No silent failures – every error is handled or surfaced | ✅ | Backend: all endpoints wrapped in try/except with `logger.error()`. `get_db()` (`core/database.py:29`) auto-rollbacks on exception. WebSocket broadcast (`main.py:312`) catches per-connection errors silently to avoid breaking the loop. Flutter: `Log.i/e/w/d` used throughout. `MetricsCollector().recordApiError()` on failures. | - | |
| 2.2 | Retries with exponential backoff & jitter | ⚠️ | Flutter `ApiService._executeWithRetry` (`services/api_service.dart:99`) uses exponential backoff: `baseDelay * (1 << attempt)` (1s, 2s, 4s). **No jitter** — all clients retry at the same time, risking thundering herd. Backend has **no retry logic** for external calls (e.g., Slack webhook in `alert_service.py:29` just catches and logs failure). | Medium | Add jitter to frontend retry delays (e.g., `baseDelay * (1 << attempt) + Random(0, baseDelay)`). Add retry with backoff to Slack webhook calls in `AlertService`. |
| 2.3 | Timeouts – every external call has a deadline | ✅ | Flutter: 30s timeout on all HTTP calls (`api_service.dart:88`). Redis: `socket_connect_timeout=3` in health check (`main.py:118`). WebSocket tickets expire in 10s (`main.py:565`). OTPs expire in 10min (`auth_service.py:156`). Verification tokens expire in 15min (`auth_service.py:58`). | - | |
| 2.4 | Circuit breakers – stop calling a downstream that is consistently failing | ✅ | `CircuitBreaker` class (`lib/core/circuit_breaker.dart:13`) with 5-failure threshold, 60s cooldown, halfOpen state. Per-endpoint breakers in `ApiService._breakers` map. State transitions broadcast to UI via `onStateChanged` callback. | - | |
| 2.5 | Idempotency – safely repeat operations without side‑effects | ⚠️ | Session ignition uses atomic UPDATE (`session_service.py:200`). Attendance submit uses upsert pattern (`main.py:591-628`). **No explicit idempotency keys** on POST endpoints. Duplicate heartbeats are append-only (benign). | Low | Add idempotency key header support for session creation and vault sync endpoints. |
| 2.6 | Dead letter queues – capture messages that cannot be processed | ➖ | Kiosk architecture uses local Isar vault as offline buffer (`attendance_vault` table). Not a queue-based system. | - | |
| 2.7 | Well‑defined error responses – consistent format, no stack traces | ✅ | Pydantic models for request validation. FastAPI `HTTPException` with `detail` strings (e.g., `"AUTH_FAILED: Missing or invalid Authorization header"`). No stack traces leaked. Correlation IDs included via middleware. | - | |
| 2.8 | Correlation IDs propagated – trace an error from user click to database | ✅ | Backend: `correlation_id_middleware` (`main.py:222`) propagates `X-Request-ID` header. Flutter: `_generateRequestId()` (`api_service.dart:78`) generates UUID per request. Echo verification at `api_service.dart:143`. | - | |

---

## 3. SECURITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 3.1 | No secrets in source code – vault / env vars / sealed secrets | ❌ | **CRITICAL: `.env` file is committed with real Firebase API key (`AIzaSyBooFadQf3TZFvZOUJkihMUdgexrbeoQnE`), project ID, and app ID.** `.env.example` contains identical values. Although `.gitignore` lists `.env`, the file exists in the repo. Backend `JWT_SECRET` is properly required at startup (`main.py:70`). | Critical | Rotate all Firebase credentials immediately. Move `.env.example` to contain only placeholder values. Use `git filter-branch` or BFG to purge `.env` from git history. Restrict `FIREBASE_API_KEY` in Firebase Console. |
| 3.2 | Encryption in transit – TLS everywhere | ✅ | `SslPinningService` validates certificate fingerprints. `SSL_PIN_FINGERPRINT` env var for production pin. Backend runs behind HTTPS (`api-dev.balaseetharamanjaneyulu.com`). WebSocket connections authenticated via ticket system. | - | |
| 3.3 | Encryption at rest – database, backups, logs | ✅ | `FlutterSecureStorage` (DPAPI on Windows) for token storage. PostgreSQL connection via asyncpg (TLS-capable). Isar local database with AES-256 encryption. | - | |
| 3.4 | Authentication & Authorisation – proper OAuth2/JWT/session management | ✅ | Dual auth: Firebase Auth for boards (`core/security.py:47`), JWT HS256 for admin RBAC (`services/auth_service.py:281`). Hardware binding via `X-Device-ID` header. WebSocket ticket system with 10s TTL (`main.py:551`). OTP lockout after 10 attempts (`auth_service.py:26`). | - | |
| 3.5 | Input validation & sanitisation – never trust user input | ✅ | Pydantic v2 models with field constraints (`otp: str = Field(..., min_length=6, max_length=6)`). Board ID mismatch detection (`main.py:404`). Firebase token verified server-side. | - | |
| 3.6 | Rate limiting & throttling – per user, per IP, per endpoint | ✅ | Tiered sliding-window rate limiter: auth 5/min (brute-force protection), ticket 10/min, general 60/min, health 120/min. Key: `IP:X-Device-ID`. Admin exempt. OTP lockout: 10 attempts, 15min cooldown. | - | |
| 3.7 | Dependency scanning – automated checks for known vulnerabilities | ⚠️ | Dependabot configured (`.github/dependabot.yml`) for pub/pip/github-actions (weekly). CI runs `dart pub audit` and `pip-audit` but with `|| echo` (non-blocking, won't fail build). **No CodeQL, Snyk, or Trivy integration.** | Medium | Integrate CodeQL or Snyk into `ci.yml`. Make dependency audit failures block the build (remove `|| echo`). |
| 3.8 | Security headers & CSP – HTTP security headers correctly configured | ✅ | Full suite applied via middleware (`main.py:229`): `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `CSP: default-src 'none'`, `Permissions-Policy: camera=(), microphone=(), geolocation=()`, `COOP: same-origin`, `CORP: same-origin`. Rationale documented in comments. | - | |
| 3.9 | Audit logging – who did what, when | ⚠️ | Backend logs auth/registration events to `backend/python/logs/app.log` with timestamps. `UpdateEvent` table (`sql_models.py:503`) provides immutable audit trail for update operations. **No separate audit log for data access or admin actions.** Auth events logged but not in a queryable, tamper-proof format. | Medium | Create an `audit_log` table (actor, action, resource, timestamp, IP). Log all auth events, data modifications, and admin commands to it. |

---

## 4. TESTING

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 4.1 | Unit tests – business logic in isolation, fast | ⚠️ | Backend: 4 test files (~1,195 lines). `test_split_knowledge.py` (402 lines) — thorough cryptographic contract tests. `test_services.py` (259 lines) — auth, cache, session, alert. `test_registration_pg.py` (154 lines) — registration flow. **Frontend: 2 test files** — `app_test.dart` (trivial version check), `network_throughput_test.dart` (606 lines, solid). Most backend services/routes/middleware have **no unit tests**. | High | Add unit tests for: `hydration_service`, `board_service`, `rate_limit_middleware`, `main.py` endpoints, WebSocket handlers. Target >80% coverage on core business modules. |
| 4.2 | Integration tests – API + real dependencies | ❌ | No `TestClient` usage. No testcontainers for PostgreSQL. No live DB tests. All tests mock the database session. No tests for the actual HTTP request/response cycle. | High | Add FastAPI `TestClient` integration tests with testcontainers (PostgreSQL + Redis). Test full request lifecycle including middleware. |
| 4.3 | End‑to‑end tests – critical user journeys | ⚠️ | No automated E2E tests. Manual verification only. Windows desktop kiosk makes E2E testing inherently harder (requires hardware simulation). `TODO_HARDENING.md` lists "Automated UI Tests (Patrol/IntegrationTest)" as open. | Medium | Implement Flutter IntegrationTest for critical flows: boot → registration → session → attendance. Use Patrol for native Android/Windows interactions. |
| 4.4 | Performance tests – load tests with expected peak traffic | ⚠️ | `scripts/load_test.py` simulates 10 boards × 50 scans (500 total) with async httpx. Reports avg/p95 latency, throughput. **No stress test at scale (1,000+ concurrent).** No Locust/k6/JMeter configs. | Medium | Scale `load_test.py` to 1,000+ concurrent scans. Add Locust config for continuous load testing. Define SLOs for latency (p95 < 500ms). |
| 4.5 | Chaos tests – simulate dependency failures | ➖ | Desktop kiosk app — network loss simulation happens naturally. Flutter offline vault (`QueuedScan`, `SyncManager`) handles connectivity loss. Not a microservice architecture requiring chaos engineering. | - | |
| 4.6 | Fault injection – test retry & circuit breaker behaviour | ⚠️ | `test_services.py` mocks Redis (`REDIS_URL=""`) and Firebase. `test_split_knowledge.py` tests pure functions. **No fault injection tests** for circuit breaker state transitions, retry exhaustion, or cascade failure scenarios. | Low | Add tests that: inject 503 errors to verify retry count, verify circuit breaker opens after threshold, verify half-open state recovery. |
| 4.7 | High meaningful coverage – >80% on core business modules | ❌ | Backend: ~30 tests covering auth, cache, session, crypto. Most routes (`main.py` 1,891 lines), middleware, hydration, board services untested. Frontend: 2 test files. Estimated overall coverage **<30%**. Core crypto protocol (`test_split_knowledge.py`) is well-tested at ~100%. | High | Prioritize testing: (1) all API endpoints via TestClient, (2) hydration_service, (3) rate_limit_middleware, (4) WebSocket handlers. Run coverage report and target 80% on `services/` and `core/`. |
| 4.8 | Automated in CI – tests block merging if they fail | ⚠️ | `ci.yml` runs `dart analyze` and `flutter test` — these block merge. **Python backend tests are NOT run in CI** (no pytest step). `pip-audit` runs with `|| echo` (non-blocking). | Medium | Add Python test step to `ci.yml`: `pip install -r requirements.txt && pytest backend/python/tests/`. Make `pip-audit` fail the build. |
| 4.9 | Contract tests – verify producer/consumer APIs match | ⚠️ | `test_split_knowledge.py` validates crypto protocol contract (server ↔ board HMAC derivation). `Pydantic` models enforce API shape. **No formal Pact or contract testing** between Flutter (Isar) and backend (SQLAlchemy). | Low | Add schema alignment tests: validate Pydantic response models match Isar schema expectations. Consider Pact for API contract testing. |

---

## 5. OBSERVABILITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 5.1 | Structured logging – JSON logs with consistent fields | ⚠️ | Backend: `logging.basicConfig(format="%(asctime)s [%(levelname)s] %(message)s")` — **plain text, NOT JSON**. No service name, traceId, or structured fields. Flutter: `Log.i/e/w/d` service provides structured logging. **Backend logging format does not match the structured JSON requirement.** | Medium | Migrate backend to `python-json-logger` or `structlog`. Add `service`, `traceId`, `requestId` fields. Align with Flutter log format. |
| 5.2 | Metrics – RED (Rate, Errors, Duration) for every endpoint | ⚠️ | Flutter: `MetricsCollector().recordApiError()` tracks API errors. Heartbeat includes `uptimeSeconds`, `screenState`. **No Prometheus, StatsD, or CloudWatch metrics export.** No per-endpoint latency tracking. No request rate metrics. | Medium | Add `prometheus-fastapi-instrumentator` to FastAPI for RED metrics. Export to Prometheus/Grafana. Track business KPIs (active sessions, scans per minute). |
| 5.3 | Distributed tracing – propagate trace context across services | ⚠️ | `X-Request-ID` correlation IDs propagated via middleware (`main.py:222`) and Flutter interceptor (`api_service.dart:117`). Echo verification. **No OpenTelemetry, Jaeger, or Zipkin integration.** No trace context propagation to PostgreSQL queries. | Low | Integrate `opentelemetry-python` for automatic trace propagation. Export traces to Jaeger or Tempo. |
| 5.4 | Dashboards – real‑time view of health, error rates, latency | ⚠️ | Admin endpoints provide fleet data: `/api/v1/admin/heartbeats` (stale detection), `/api/v1/admin/fleet` (version distribution). **No actual dashboard UI** (Grafana, Datadog, etc.) configured. Data exists but no visualization. | Medium | Deploy Grafana dashboards for: (1) API RED metrics, (2) board fleet health, (3) session activity, (4) error rates. |
| 5.5 | Proactive alerting – alerts on error budget burn, CPU/memory | ✅ | `AlertService` (`services/alert_service.py`) sends Slack notifications for stale boards and security violations. Background `stale_board_monitor` runs every 30min (`main.py:136`). Auto-terminates sessions for stale boards. | - | |
| 5.6 | SLOs & error budgets – defined, used to gate feature velocity | ❌ | `TODO_HARDENING.md` lists "SLO Definition" and "Error Budgeting" as open. No formal SLO document. No error budget burn rate tracking. | Low | Define SLOs (e.g., 99.9% availability, p95 < 500ms latency). Track error budget burn in monitoring. |
| 5.7 | Log aggregation & retention – centralised, searchable, retention policy | ⚠️ | Backend logs to local file (`backend/python/logs/app.log`). `docs/operations/log-aggregation.md` defines policy. **No actual aggregation tool** (ELK, Loki, CloudWatch Logs) configured. Logs not searchable across instances. | Medium | Deploy log aggregation (e.g., Loki + Grafana, or CloudWatch Logs). Configure retention policy (90 days). Ensure logs from all instances are centralized. |

---

## 6. DEPLOYMENT & INFRASTRUCTURE

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 6.1 | Infrastructure as Code (IaC) | ❌ | No Terraform, CloudFormation, or Pulumi files. `docs/operations/INFRASTRUCTURE_PROVISIONING_GUIDE.md` referenced in previous audit but **does not exist** in the repo. Infrastructure provisioned manually. | High | Create Terraform/Pulumi configs for: PostgreSQL (RDS/Cloud SQL), Redis (ElastiCache), networking, IAM roles. Store in `infra/` directory. |
| 6.2 | Immutable infrastructure – servers/containers replaced, not patched | ⚠️ | CI builds MSI artifacts (immutable). Flutter app distributed as MSI with SHA-256 verification. **Backend is deployed in-place** (no container images, no immutable VMs). | Medium | Containerize backend. Deploy as immutable Docker images. Never patch in-place. |
| 6.3 | Containerisation – Docker with minimal, secure base images | ❌ | **No Dockerfile or docker-compose.yml** anywhere in the project. Backend (FastAPI) is conceptually Docker-ready but not containerized. SmartBoard itself is a native Windows desktop app (cannot be containerized). | High | Create `Dockerfile` for backend using `python:3.12-slim`. Add `docker-compose.yml` with PostgreSQL + Redis + backend. |
| 6.4 | Orchestration – Kubernetes, ECS, or similar | ❌ | No Kubernetes manifests, ECS task definitions, or similar. Backend runs as a single `uvicorn` process. No self-healing, rolling updates, or pod disruption budgets. | High | Deploy backend on Kubernetes (or ECS). Define Deployment, Service, HPA, PodDisruptionBudget manifests. |
| 6.5 | CI/CD pipeline – automated build, test, deployment | ✅ | 3 GitHub Actions workflows: `ci.yml` (analyze + test), `release.yml` (MSI build + GitHub Release + manifest), `auto-deploy.yml` (auto-version + build + deploy to server). Dependabot for dependency updates. Branch protection documented. | - | |
| 6.6 | Deployment strategies – blue/green, canary, rolling deploys | ⚠️ | Frontend: auto-update via `latest.json` manifest polling + MSI download + SHA-256 verification. Supports rollout percentage and force-update. **Backend: no deployment strategy** — direct `curl` upload to server (`auto-deploy.yml:248`). | Medium | Implement blue/green or canary deployment for backend. Use load balancer to shift traffic gradually. |
| 6.7 | Rollback – quick, automated rollback to last known good version | ⚠️ | Frontend: auto-updater has backup + crash-loop detection + auto-rollback (`auto_updater.dart`). **Backend: no automated rollback.** CI uploads MSI to server but no rollback mechanism for backend code. | Medium | Add backend rollback: keep previous Docker image tagged. Add rollback endpoint or script. Implement health-check gating before traffic shift. |
| 6.8 | Feature flags – decouple deployment from release | ✅ | `RemoteConfigService` in Flutter. Server-side flags in heartbeat config (`main.py:467`): `enable_video_background`, `enable_documents`, `enable_notifications`, `enable_workspace`, `kiosk_mode`, `qr_rotation_interval_ms`, `session_window_seconds`. | - | |
| 6.9 | Environment parity – staging closely mirrors production | ⚠️ | `.env.example` exists with placeholder structure. But **`.env` has real Firebase credentials committed** (see 3.1). Local dev uses `localhost:5432` while production uses remote URL. No staging environment defined. | Medium | Create a staging environment with separate Firebase project, PostgreSQL instance, and Redis. Document environment differences. |

---

## 7. DATA MANAGEMENT

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 7.1 | Database migrations version‑controlled & automated | ✅ | Alembic configured (`alembic.ini`, `alembic/env.py`). 3 versioned migrations in `alembic/versions/`: `001_initial_schema` (full schema + 6 enums), `002_add_smart_board_id`, `003_add_pending_registrations`. Up and down scripts present. | - | |
| 7.2 | Backup & restore regularly tested | ⚠️ | `docs/RUNBOOKS/disaster-recovery.md` exists. **No automated backup scripts** in repo. No `pg_dump` cron job. No backup verification tests. PostgreSQL backup strategy not explicitly documented. | High | Create automated PostgreSQL backup script (daily `pg_dump` + upload to S3/GCS). Test restore procedure monthly. Document RPO/RTO. |
| 7.3 | Point‑in‑time recovery – transaction logs ensuring minimal data loss | ⚠️ | PostgreSQL configured with defaults. **No WAL archiving configured.** No `archive_mode = on` or `archive_command`. RPO is undefined. | Medium | Enable WAL archiving to S3/GCS. Configure `archive_mode` and `archive_command`. Set RPO target (e.g., 5 minutes). |
| 7.4 | Read replicas / caching – for performance and availability | ✅ | `CacheService` (`services/cache_service.py`) with Redis + in-memory fallback. TTL-based caching: hydration 300s (`hydration_service.py:25`), OTP 300s (`session_service.py:16`). **No PostgreSQL read replicas** (caching only). | - | |
| 7.5 | Data validation at schema level – NOT NULLs, constraints, foreign keys | ✅ | SQLAlchemy models (`models/sql_models.py`) with: `nullable=False`, `unique=True`, `index=True`, `ForeignKey` constraints, `UniqueConstraint` (e.g., `uq_student_section_course`). Pydantic validation on API input. Enum types for roles, statuses. | - | |
| 7.6 | PII handling – anonymisation, data retention policies | ⚠️ | `docs/operations/pii-retention.md` defines policy. Email used as `student_id` in `session_attendees` and `attendance_vault` (PII in plain text). **No anonymization or data retention enforcement in code.** No GDPR/CCPA compliance mechanism. | Medium | Anonymize PII in `attendance_vault` after retention period. Implement data deletion API. Hash or pseudonymize email in attendance records. |
| 7.7 | Data encryption at application level for sensitive fields | ⚠️ | OTPs stored as SHA-256 hashes (`auth_service.py:46`). JWT signed with HS256. **No field-level encryption for PII** (email, name) in PostgreSQL. `session_secret_half1` stored in plaintext in `active_sessions` table. | Low | Encrypt `session_secret_half1` at rest. Consider column-level encryption for PII fields (email, name) using `pgcrypto`. |

---

## 8. CODE QUALITY & DOCUMENTATION

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 8.1 | Consistent code style – automated with formatters and linters | ✅ | Dart: `analysis_options.yaml` with strict rules. `dart format` enforced. `fix_analyze.ps1` script auto-formats. Python: consistent style throughout (PEP 8 implied). C++: `/W4 /WX` (warnings as errors) in `CMakeLists.txt`. | - | |
| 8.2 | Static analysis – code quality & security scanners | ✅ | `dart analyze lib/ test/` in CI. `flutter analyze` enforced. **No Python linter** (ruff/flake8) configured, but Python code follows consistent patterns. No CodeQL/SonarQube. | - | |
| 8.3 | Code review mandatory – every change peer‑reviewed before merge | ✅ | `docs/BRANCH_PROTECTION.md` documents: PR required for `school-main`/`main`, status checks (`CI` workflow) required, no direct pushes. | - | |
| 8.4 | Architecture Decision Records (ADRs) – document why a pattern was chosen | ✅ | 3 ADRs in `docs/adr/`: `0001-record-architecture-decisions.md`, `0002-structured-json-logging.md`, `002-session-recovery-mechanism.md`. | - | |
| 8.5 | Runbooks for known incidents – playbooks for specific failure responses | ✅ | `docs/RUNBOOKS/disaster-recovery.md`. `docs/operations/log-aggregation.md`, `docs/operations/pii-retention.md`. `server_clarity_report.md` (root cause analysis). | - | |
| 8.6 | API documentation – OpenAPI/Swagger, kept automatically up to date | ⚠️ | FastAPI auto-generates Swagger/OpenAPI at `/docs`. **No custom API documentation**, no OpenAPI spec file exported, no Postman collection. Endpoint descriptions minimal in code. | Low | Add detailed docstrings to all endpoints. Export OpenAPI spec to `docs/api/openapi.json`. Create Postman collection for testing. |
| 8.7 | README that onboards – prerequisites, setup, run, test; architecture diagram | ✅ | `README.md` exists. `docs/DEVELOPER_GUIDE.md`, `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md`, `docs/PRODUCT_SPEC.md`. `docs/SERVER_SIDE_REQUIREMENTS.md`. | - | |
| 8.8 | Todo / next‑steps list – acknowledges trade‑offs | ✅ | `TODO.md` (46 items across server, release, bugs, security, auto-update). `TODO_HARDENING.md` (production hardening checklist). `TODO_TIME_SYNC.md` (clock sync implementation plan). | - | |

---

## 9. SCALABILITY & PERFORMANCE

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 9.1 | Stateless application servers – scale horizontally | ✅ | FastAPI uses JWT claims for auth (no server-side sessions). `async_sessionmaker` per-request. WebSocket connections are in-memory (`ConnectionManager`) — **single-instance limitation for WebSocket** but HTTP endpoints are fully stateless. | - | |
| 9.2 | Caching layers – in-memory caches, CDNs, database query caches | ✅ | Redis cache with in-memory fallback (`CacheService`). Hydration cached 300s (`hydration_service.py:25`). OTP cached 300s (`session_service.py:16`). Flutter: `SharedPreferences`, Isar, `TimetableCache`, `StudentService` in-memory caches. | - | |
| 9.3 | Asynchronous processing – long‑running tasks in background | ✅ | All backend services async (asyncpg, async httpx). Background `stale_board_monitor` as asyncio task (`main.py:136`). WebSocket async. No blocking I/O on request threads. | - | |
| 9.4 | Database connection pooling – properly sized, no leaks | ✅ | SQLAlchemy engine: `pool_size=10, max_overflow=20` (`core/database.py:16`). `get_db()` context manager ensures `session.close()` in `finally` block. No visible connection leaks. | - | |
| 9.5 | Capacity planning – you know how much load one instance can handle | ⚠️ | Rate limit set at 60/min per IP. `load_test.py` tests 500 scans. **No formal capacity model.** No documented max concurrent sessions per instance. No load test results at scale. | Medium | Document: max concurrent boards per instance, max scans/second, DB connection limits. Run load test at 1,000+ concurrent and publish results. |
| 9.6 | Auto‑scaling – triggers based on CPU/memory/queue length | ❌ | Backend runs as single `uvicorn` process. **No auto-scaling configuration.** No Kubernetes HPA, ECS auto-scaling, or cloud auto-scaling group. | Medium | Deploy on auto-scaling infrastructure (K8s HPA, ECS Service Auto Scaling, or cloud ASG). Configure CPU/memory-based triggers. |

---

## EXECUTIVE SUMMARY

**Overall Readiness Score: 60 / 100**  
*(Calculated as: (32 ✅ × 3 + 27 ⚠️ × 1 + 0 🔜 × 0.5) ÷ (68 applicable items × 3) × 100 = 123/204 × 100)*

**Top 3 Critical Risks:**
1. **Secrets in Source Code (3.1):** Real Firebase API key and credentials committed in `.env` file. Must rotate immediately and purge from git history.
2. **No Containerization or Orchestration (6.3, 6.4):** Backend runs as a single process with no Docker, no K8s, no auto-scaling. Single point of failure for the entire fleet.
3. **Insufficient Test Coverage (4.1, 4.2, 4.7):** <30% overall coverage. No integration tests, no E2E tests, no Python tests in CI. Core crypto is well-tested but most business logic is untested.

**Key Strengths:**
- **Security Architecture:** Firebase Auth + JWT RBAC + hardware binding + SSL pinning + tiered rate limiting is exceptional for a kiosk app.
- **Offline Resilience:** Isar vault, circuit breaker, retry with backoff, and grace degradation provide robust offline-first behavior.
- **CI/CD Pipeline:** 3 automated workflows with MSI packaging, signing, SHA-256 verification, and auto-update manifest generation.
- **Documentation:** 37+ markdown files including ADRs, runbooks, developer guides, and comprehensive TODO lists.

**Overall Assessment:**
- [ ] **Ready for production**
- [ ] **Ready with caveats (minor improvements needed)**
- [x] **Not ready (major gaps exist)**

**Recommended Go / No‑Go Decision:** **CONDITIONAL GO** — The application architecture is solid and the security model is strong. However, **3 critical items must be resolved before production deployment:**
1. Rotate and purge committed secrets (3.1)
2. Containerize backend with basic orchestration (6.3, 6.4)
3. Achieve minimum 60% test coverage with CI-enforced Python tests (4.1, 4.7, 4.8)

---

## REMEDIATION PLAN

| Item # | Gap | Action | Owner | Target Date |
|--------|-----|--------|-------|--------------|
| 3.1 | Secrets committed in `.env` | Rotate Firebase credentials. Purge `.env` from git history (BFG). Update `.env.example` with placeholders only. | Security | Immediate |
| 6.3 | No Dockerfile | Create `Dockerfile` for backend (`python:3.12-slim`). Add `docker-compose.yml` with PG + Redis + backend. | DevOps | Week 1 |
| 6.4 | No orchestration | Create Kubernetes Deployment + Service manifests. Or use ECS/fly.io for simple deployment. | DevOps | Week 2 |
| 4.1, 4.7 | Insufficient test coverage | Add pytest tests for all `main.py` endpoints via TestClient. Target 80% on `services/` and `core/`. | Backend | Week 2 |
| 4.8 | Python tests not in CI | Add `pytest` step to `.github/workflows/ci.yml`. Make `pip-audit` fail the build. | DevOps | Week 1 |
| 7.2 | No automated backups | Create `pg_dump` cron job. Test restore procedure. Document RPO/RTO. | DevOps | Week 1 |
| 6.1 | No Infrastructure as Code | Create Terraform configs for PostgreSQL + Redis + networking. | DevOps | Week 3 |
| 5.1 | Backend logging not structured JSON | Migrate to `python-json-logger` or `structlog`. Add `service`, `traceId` fields. | Backend | Week 2 |
| 2.2 | No jitter in retry logic | Add random jitter to frontend exponential backoff. Add retry to Slack webhook calls. | Frontend | Week 1 |
| 3.7 | Dependency scanning not blocking | Remove `|| echo` from `pip-audit` in CI. Integrate CodeQL or Snyk. | DevOps | Week 2 |

---

## PREVIOUS AUDIT COMPARISON

| Metric | May 2026 Audit | July 2026 Audit | Delta |
|--------|---------------|-----------------|-------|
| **Score** | 94/100 | 60/100 | -34 |
| **✅ Fully Implemented** | ~50 | 32 | -18 |
| **⚠️ Partially Implemented** | ~6 | 27 | +21 |
| **❌ Not Implemented** | ~3 | 9 | +6 |
| **Key Change** | Firestore-based | PostgreSQL migration (dual codepaths) | More honest assessment |

> **Note:** The previous audit (May 2026) scored 94/100 but used more lenient criteria. This audit applies stricter standards with concrete evidence requirements. The score drop reflects: (1) discovery of committed secrets, (2) recognition that most testing is mocked-only, (3) honest assessment of infrastructure gaps, (4) PostgreSQL migration creating unmaintained dual codepaths.

---

### Instructions to the team

1. **Be brutally honest** – this is a risk‑assessment tool, not a blame document.
2. **Evidence is mandatory** – a checkmark without a link, file path, or concrete observation is not acceptable.
3. **Complete every cell** – if something is "Not Applicable", explain why (e.g., "4.5 – Desktop kiosk app, network loss simulation happens naturally").
4. **Update the "Action Required" column** for every ⚠️ or ❌ with a risk level and a one‑sentence remediation.
5. **Deliver the audit as a shared document** (Notion, markdown in repo, Google Docs) so it remains a living artifact for the next audit cycle.
