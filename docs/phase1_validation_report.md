# Phase 1 — Update System Stabilization: Validation Report

**Status:** PASS
**Date:** 2026-08-01
**Build under test:** v5.5.0+17 (`fb27994`) on `school-main`
**Machine:** Windows 11 Home Single Language 10.0 (Build 26200)
**Toolchain:** Flutter 3.44.7 stable / Dart 3.12.2
**Full machine-generated report:** `build/validation/Phase1ValidationReport.md` (Markdown) and `.json`

---

## 0. Review Decision (2026-08-01)

**Approved as a VALIDATION CANDIDATE — not production-ready.**

| Decision | Verdict |
|----------|---------|
| Approve Phase 1 code for merge into `school-main` | ✅ Approved |
| Tag the release | ✅ `validation-candidate-v1` (NOT "Production Ready") |
| Freeze updater feature development during validation | ✅ In effect (bug fixes only) |
| Proceed to Phase 2 (Hardware & Operational Validation) | ✅ `docs/phase2_hardware_validation_plan.md` |
| Fleet-wide deployment | ❌ Blocked until the 40 pending scenarios are executed with evidence |

The 40 pending scenarios (power failure, reboot, crash, soak, fleet ramp, memory
measurement, hardware-bound installer/backup/security tests) are now executable
test plans in the Phase 2 document.

---

## 1. Executive Verdict

> **GATE = PASS — 75 / 75 executed scenarios passed (100.0%), 0 failed, 40 pending.**

The Phase 1 validation harness ran the full CI-testable scenario matrix for the
self-update system. Every scenario that can be proven without real hardware or a
deployed fleet **passed**. The 40 non-executed scenarios are **declared and
pending** — they require a hardware lab (power-cut, reboot, UAC installer,
handle/RSS measurement) or a fleet (soak, ramp, bandwidth telemetry) and do not
gate the merge.

A PASS here does **not** claim hardware-lab or fleet evidence. The remaining 40
scenarios must be executed on real equipment before the corresponding
production claims (rollback-under-power-loss, reboot recovery, memory-leak
stability, fleet soak) can be made.

---

## 2. Scope & Methodology

- **Suite:** `test/validation/phase1_validation_test.dart` (115 scenarios across 20 categories).
- **Fault injection:** local loopback `HttpServer` fixtures (`test/validation/fault_http_server.dart`) inject
  truncated bodies, connection resets mid-stream, HTTP errors, redirects, DNS failures, hangs, and throttling —
  exercised against the **real** `http.Client()` path in `AutoUpdater` (real loopback networking restored by
  clearing Flutter test's mock HTTP overrides).
- **Seams used (no code changes for the test):** installed-version override, disk-probe override, agent-launcher
  override, exit-on-completion flag, download-timeout override.
- **Gate semantics:** any CI-testable scenario failure rethrows and fails `flutter test`. Hardware-lab/fleet
  scenarios are registered as PENDING and never gate.
- **Report emission:** `tearDownAll` writes `build/validation/Phase1ValidationReport.{md,json}` with per-scenario
  verdicts, evidence, metrics, acceptance metrics, and the category gap matrix.

---

## 3. Results by Category

| # | Category | Executed | Passed | Failed | Pending |
|---|----------|----------|--------|--------|---------|
| 1 | Manifest Validation | 14 | 14 | 0 | 0 |
| 2 | Download | 14 | 14 | 0 | 0 |
| 3 | Hash Verification | 6 | 6 | 0 | 0 |
| 4 | Backup | 3 | 3 | 0 | 2 |
| 5 | Installer | 1 | 1 | 0 | 2 |
| 6 | Update Agent / State | 7 | 7 | 0 | 1 |
| 7 | Power Failure | 0 | — | — | 15 |
| 8 | Unexpected Reboot | 0 | — | — | 2 |
| 9 | Crash Injection | 2 | 2 | 0 | 2 |
| 10 | File Locks | 2 | 2 | 0 | 2 |
| 11 | Resource Exhaustion | 3 | 3 | 0 | 2 |
| 12 | Security | 5 | 5 | 0 | 2 |
| 13 | Version Migration | 4 | 4 | 0 | 0 |
| 14 | Configuration Preservation | 3 | 3 | 0 | 0 |
| 15 | User Data Preservation | 3 | 3 | 0 | 0 |
| 16 | Stress Testing | 3 | 3 | 0 | 0 |
| 17 | Memory / Resource Leaks | 1 | 1 | 0 | 1 |
| 18 | Concurrency | 4 | 4 | 0 | 0 |
| 19 | Long Soak | 0 | — | — | 3 |
| 20 | Fleet Testing | 0 | — | — | 6 |
| **Total** | | **75** | **75** | **0** | **40** |

---

## 4. Acceptance Metrics

| Metric | Requirement | Evidence / Status |
| --- | --- | --- |
| Update success rate | ≥ 99.9% | **100.0%** of 75 executed scenarios |
| Rollback success on injected failures | 100% | HARDWARE-LAB required (real installer/reboot restore) |
| Data corruption | 0 cases | CI: every scenario asserted no corruption; hardware-lab pending |
| Boot failures after update | 0 | HARDWARE-LAB required (real power cut / reboot) |
| Partial installations | 0 | CI: download-failure scenarios assert no orphan/partial files remain |
| State recovery after unexpected reboot | 100% | HARDWARE-LAB required (real reboot injection) |
| Memory leaks over repeated runs | none | HARDWARE-LAB required (real handle/RSS measurement) |
| Concurrent update | exactly one installer | CI: single-flight scenarios assert exactly one pipeline start |
| Backup integrity verified every update | verified | CI: backup created and verified before download in every pipeline scenario |
| SHA-256 validation failures accepted | 0 | CI: every wrong-hash scenario asserts installer deleted, never launched |
| Invalid manifests installed | 0 | CI: every denied-manifest scenario asserts no download occurs |

---

## 5. Defects Found & Fixed During Validation

Five real production defects and one test-fixture defect were found and fixed as
a direct result of running this harness. Each is documented in detail in
`docs/phase1_session_changelog.md`. Scenario IDs below refer to the generated
report.

| # | Severity | Scenario(s) that exposed it | Defect | Fix |
|---|----------|----------------------------|--------|-----|
| 1 | High | Disk-space block scenarios | `_hasEnoughDiskSpace` used `return diskSpaceProbeOverride!();` — a Future returned in an async function flattens errors *outside* the try/catch, so a throwing probe **blocked updates** instead of failing open | `return await diskSpaceProbeOverride!();` |
| 2 | High | SC-019 — Connection reset mid-stream | The fault server's reset mode called `detachSocket()` *after* writing body bytes → `Bad state: Headers already sent`, so the connection hung open and the download never failed/settled | Fixture now detaches the socket **before** any response bytes, hand-crafts the raw HTTP response, then destroys the socket |
| 3 | High | SC-026 — User cancels mid-download | `dismiss()` could not delete the partial file while its stream handle was open (Windows rejects deleting open files) and the stream was not aborted → orphan file + stale overlay | `_downloadWithProgress` checks `_dismissRequested` per chunk (throws `_DownloadCancelled`), deletes the partial file in its `finally` after the sink closes; dismiss paths also clean up defensively |
| 4 | High | SC-027, SC-083 — Duplicate/replayed manifest | `_startUpdate` cleared `_lastCheckedManifestFingerprint` on **success**, so re-delivering the identical manifest started a second download/install | Keep the dedup fingerprint after success (failure path still clears it to allow retry) |
| 5 | High | SC-100 — Circuit breaker opens after 3 failures | The failed-state guard (`progress == failed && !force → return false`) blocked every non-force re-check, so consecutive failures could never accumulate and the circuit breaker never opened (Settings "Retry" for non-force updates was a dead end) | Removed the failed-state guard; the circuit breaker is now the single anti-retry mechanism (opens after 3 consecutive failures) |
| 6 | Low | All scenarios | `setUp()` called `ValidationSuite.reset()` per test, wiping accumulated results → `tearDownAll` report showed `executed=0, pending=1` | Removed the per-test reset so all scenarios aggregate into the report |
| 7 | Low | All download scenarios (log noise) | `UpdateHealthMonitor._saveToRegistry` wrote `Data\update_health.json` before the `Data\` directory existed → `PathNotFoundException`, silently dropped health state | `_prefsFile.parent.createSync(recursive: true)` before write |

### Test adjustments (harness, not production code)

Two harness tests assumed the old (incorrect) "re-process identical manifest"
behavior; after defect #4 they now simulate distinct admin pushes to preserve
their original intent:

- **"20 repeated downloads leave no orphans"** — alternates the `force` flag per
  iteration (distinct fingerprint) while keeping the identical installer path and
  leak assertions.
- **"Missing backup is recreated"** — the second drive now targets v5.6.0
  (a distinct fingerprint, simulating the *next* update) instead of re-driving
  the same v5.5.0 manifest.

---

## 6. Remaining Work — 40 Pending Scenarios

These require a hardware lab or a fleet and were **declared, not executed**:

- **Power Failure (15)** — power cut at each pipeline stage; verify rollback & reboot recovery.
- **Unexpected Reboot (2)** — reboot injection before/after marker write.
- **Long Soak (3)** — 500+ run stability, handle/RSS growth.
- **Fleet Testing (6)** — production ramp, soak, bandwidth telemetry.
- **Partial (1–2 each):** Backup, Installer, Update Agent/State, Crash Injection,
  File Locks, Resource Exhaustion, Security (hardware-bound), Memory/Resource Leaks.

**Owner required:** Hardware Lab / Fleet team. These are the only items standing
between this CI PASS and full end-to-end production validation claims.

---

## 7. How to Reproduce

```bash
# Full Phase 1 validation suite (writes build/validation/Phase1ValidationReport.{md,json})
flutter test test\validation\phase1_validation_test.dart

# Regression suites
flutter test tests\update_simulation_test.dart
flutter test test\reinstall_simulation_test.dart
flutter test test\update_state_checksum_test.dart
flutter test test\app_test.dart test\network_throughput_test.dart

# Static analysis
flutter analyze lib\services\auto_updater.dart lib\services\update_health_monitor.dart test\validation
```

**Observed results (2026-08-01):**

| Suite | Result |
| --- | --- |
| Phase 1 validation | 115 total — 75 pass, 0 fail, 40 pending |
| Update simulation | 59 pass |
| Reinstall simulation | 14 pass |
| Update-state checksum | 4 pass |
| App + network throughput | 46 pass |
| `flutter analyze` (changed files) | clean (0 warnings/errors) |
