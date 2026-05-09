Here’s a precise, ready‑to‑use **Production Readiness Audit & Report Template** you can hand directly to your team. It’s designed to force clear answers, evidence, and a meaningful gap analysis.

---

# `PRODUCTION‑READINESS AUDIT REPORT`

**Project / Service:** ____________________________  
**Audit Date:** ____________________________  
**Auditor(s):** ____________________________  
**Version:** ____________________________  

---

## How to Use This Template

For each item, choose the **Status** from the legend below and provide concrete **Evidence** (a link, a command, a file path, a screenshot, or a “not applicable” reason).  
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
| 1.1 | SLA‑driven design – explicit uptime target (e.g., 99.9%) | | | | |
| 1.2 | Redundancy – multiple instances, no single point of failure | | | | |
| 1.3 | Health checks / liveness probes – system can tell if alive and ready | | | | |
| 1.4 | Failover mechanisms – automatic switch to standby components (DB replicas, backup services) | | | | |
| 1.5 | Graceful degradation – non‑critical features turn off under stress instead of crashing | | | | |
| 1.6 | Load shedding / backpressure – refuses excess traffic rather than accepting and dying | | | | |
| 1.7 | Disaster recovery plan – runbooks, RPO/RTO defined, regular drills | | | | |

---

## 2. ERROR HANDLING

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 2.1 | No silent failures – every error is handled or surfaced (logged/alerted) | | | | |
| 2.2 | Retries with exponential backoff & jitter for all transient failures (network calls, queues) | | | | |
| 2.3 | Timeouts – every external call has a deadline; no unbounded waiting | | | | |
| 2.4 | Circuit breakers – stop calling a downstream that is consistently failing | | | | |
| 2.5 | Idempotency – safely repeat operations without side‑effects (especially payment/order flows) | | | | |
| 2.6 | Dead letter queues – capture messages that cannot be processed after retries | | | | |
| 2.7 | Well‑defined error responses – consistent format, no stack traces leaked to clients | | | | |
| 2.8 | Correlation IDs propagated – trace an error from user click to database | | | | |

---

## 3. SECURITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 3.1 | No secrets in source code – vault / env vars / sealed secrets | | | | |
| 3.2 | Encryption in transit – TLS everywhere, including internal service‑to‑service | | | | |
| 3.3 | Encryption at rest – database, backups, logs | | | | |
| 3.4 | Authentication & Authorisation – proper OAuth2/JWT/session management, least privilege | | | | |
| 3.5 | Input validation & sanitisation – never trust user input, protect against injection | | | | |
| 3.6 | Rate limiting & throttling – per user, per IP, per endpoint | | | | |
| 3.7 | Dependency scanning – automated checks for known vulnerabilities (Snyk, Dependabot) | | | | |
| 3.8 | Security headers & CSP – HTTP security headers correctly configured | | | | |
| 3.9 | Audit logging – who did what, when (separate from debug logs) | | | | |

---

## 4. TESTING

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 4.1 | Unit tests – business logic in isolation, fast | | | | |
| 4.2 | Integration tests – API + real (or containerised) dependencies | | | | |
| 4.3 | End‑to‑end tests – critical user journeys (e.g., login → purchase → confirmation) | | | | |
| 4.4 | Performance tests – load tests with expected peak traffic, stress tests | | | | |
| 4.5 | Chaos tests – simulate dependency failures, network latency, pod deletions | | | | |
| 4.6 | Fault injection – test retry & circuit breaker behaviour | | | | |
| 4.7 | High meaningful coverage – >80% on core business modules (quality over percentage) | | | | |
| 4.8 | Automated in CI – tests block merging if they fail | | | | |
| 4.9 | Contract tests – verify that producer/consumer APIs match (e.g., Pact) | | | | |

---

## 5. OBSERVABILITY

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 5.1 | Structured logging – JSON logs with consistent fields: timestamp, level, service, traceId, message | | | | |
| 5.2 | Metrics – RED (Rate, Errors, Duration) for every endpoint; business KPIs tracked | | | | |
| 5.3 | Distributed tracing – propagate trace context across all services/functions | | | | |
| 5.4 | Dashboards – real‑time view of health, error rates, latency percentiles | | | | |
| 5.5 | Proactive alerting – alerts on error budget burn, CPU/memory, queue depth (not just paging after crash) | | | | |
| 5.6 | SLOs & error budgets – defined, used to gate feature velocity vs. reliability work | | | | |
| 5.7 | Log aggregation & retention – centralised logs, searchable, with retention policy | | | | |

---

## 6. DEPLOYMENT & INFRASTRUCTURE

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 6.1 | Infrastructure as Code (IaC) – provisioned with Terraform, Pulumi, CloudFormation, etc. | | | | |
| 6.2 | Immutable infrastructure – servers/containers replaced, not patched in place | | | | |
| 6.3 | Containerisation – Docker with minimal, secure base images | | | | |
| 6.4 | Orchestration – Kubernetes, ECS, or similar; self‑healing, rolling updates | | | | |
| 6.5 | CI/CD pipeline – automated build, test, deployment; one‑click or automatic promotion | | | | |
| 6.6 | Deployment strategies – blue/green, canary, or rolling deploys to minimise risk | | | | |
| 6.7 | Rollback – quick, automated rollback to last known good version | | | | |
| 6.8 | Feature flags – decouple deployment from release; kill a broken feature without redeploying | | | | |
| 6.9 | Environment parity – staging closely mirrors production | | | | |

---

## 7. DATA MANAGEMENT

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 7.1 | Database migrations version‑controlled & automated – with up and down scripts | | | | |
| 7.2 | Backup & restore regularly tested – not just “we have a script” but verified | | | | |
| 7.3 | Point‑in‑time recovery – transaction logs ensuring minimal data loss | | | | |
| 7.4 | Read replicas / caching – for performance and availability | | | | |
| 7.5 | Data validation at schema level – NOT NULLs, constraints, foreign keys (where appropriate) | | | | |
| 7.6 | PII handling – anonymisation, data retention policies, GDPR/CCPA compliance | | | | |
| 7.7 | Data encryption at application level for sensitive fields (before DB storage) | | | | |

---

## 8. CODE QUALITY & DOCUMENTATION

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 8.1 | Consistent code style – automated with formatters and linters | | | | |
| 8.2 | Static analysis – code quality & security scanners (SonarQube, CodeQL) | | | | |
| 8.3 | Code review mandatory – every change peer‑reviewed before merge | | | | |
| 8.4 | Architecture Decision Records (ADRs) – document why a pattern was chosen | | | | |
| 8.5 | Runbooks for known incidents – playbooks for specific failure responses | | | | |
| 8.6 | API documentation – OpenAPI/Swagger, kept automatically up to date | | | | |
| 8.7 | README that onboards – prerequisites, setup, run, test; architecture diagram | | | | |
| 8.8 | Todo / next‑steps list – acknowledges trade‑offs and what’s left for “true productionisation” | | | | |

---

## 9. SCALABILITY & PERFORMANCE

| # | Requirement | Status | Evidence / Notes | Risk | Action Required |
|---|-------------|--------|-------------------|------|------------------|
| 9.1 | Stateless application servers – scale horizontally without sticky sessions | | | | |
| 9.2 | Caching layers – in‑memory caches, CDNs, database query caches | | | | |
| 9.3 | Asynchronous processing – long‑running tasks go to a background job/queue, not HTTP thread | | | | |
| 9.4 | Database connection pooling – properly sized, no leaks | | | | |
| 9.5 | Capacity planning – you know how much load one instance can handle before it degrades | | | | |
| 9.6 | Auto‑scaling – triggers based on CPU/memory/queue length | | | | |

---

## EXECUTIVE SUMMARY

**Overall Readiness Score: ______ / 100**  
*(Calculate as: (Total ✅ × 3 + Total ⚠️ × 1 + Total 🔜 × 0.5) ÷ (Total applicable items × 3) × 100)*

**Top 3 Critical Risks (if any):**
1.
2.
3.

**Key Strengths:**

**Overall Assessment:**
- [ ] **Ready for production**
- [ ] **Ready with caveats (minor improvements needed)**
- [ ] **Not ready (major gaps exist)**

**Recommended Go / No‑Go Decision:** ____________________________

---

## REMEDIATION PLAN (Optional)

| Item # | Gap | Action | Owner | Target Date |
|--------|-----|--------|-------|--------------|
|        |     |        |       |              |
|        |     |        |       |              |

---

### Instructions to the team

1. **Be brutally honest** – this is a risk‑assessment tool, not a blame document.
2. **Evidence is mandatory** – a checkmark without a link, file path, or concrete observation is not acceptable.
3. **Complete every cell** – if something is “Not Applicable”, explain why (e.g., “3.8 – Single‑page static app, no sensitive data”).
4. **Update the “Action Required” column** for every ⚠️ or ❌ with a risk level and a one‑sentence remediation.
5. **Deliver the audit as a shared document** (Notion, markdown in repo, Google Docs) so it remains a living artifact for the next audit cycle.

---

Hand this over as a **living audit document**. Demand updates every sprint or before every major release. It will immediately show you where your project stands and what needs to be fixed.