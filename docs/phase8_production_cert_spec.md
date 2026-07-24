# Phase 8 — Production Certification

**Status:** Complete
**Date:** 2026-07-22
**Priority:** Highest — proves the architecture works under real conditions

---

## 1. Objective

Production certification is **testing, not coding**. It proves that the
architecture (Phases 0–6) behaves correctly under the full range of
conditions encountered in real school deployments.

Every scenario below must be executed, result recorded, and signed off
before the release is certified.

---

## 2. Test Matrix

### 2.1 Installation Scenarios

| ID | Scenario | Expected Result | Priority |
|---|---|---|---|
| I-01 | Clean install (no prior version) | App installs, directories created, env.json written, app launches | P0 |
| I-02 | Upgrade from previous version | Binary replaced, config preserved, registration intact | P0 |
| I-03 | Silent install (`/qn`) | Exit code 0, no UI shown | P0 |
| I-04 | Passive install (`/passive`) | Progress bar shown, completes | P1 |
| I-05 | Install to existing directory | Overwrites binaries, preserves Data/ and Config/ | P0 |
| I-06 | Install with `--post-update` flag | App launches in post-update mode | P1 |
| I-07 | MSI exit code 3010 (reboot required) | Installer exits cleanly, reboot flag set | P1 |
| I-08 | Install on non-English Windows | Paths, registry, locale handled correctly | P1 |
| I-09 | Install on Windows 10 22H2 | All features functional | P0 |
| I-10 | Install on Windows 11 23H2 | All features functional | P0 |
| I-11 | Install with spaces in username path | `%LOCALAPPDATA%` resolves correctly | P1 |

### 2.2 Uninstallation Scenarios

| ID | Scenario | Expected Result | Priority |
|---|---|---|---|
| U-01 | Silent uninstall | Exit code 0, binaries removed, Config/ and Data/ preserved | P0 |
| U-02 | Uninstall with `-PreserveData` | All directories preserved except App/ | P0 |
| U-03 | Uninstall without `-PreserveData` | App/, Cache/, Updates/, Logs/, Backup/ removed | P0 |
| U-04 | Uninstall when app is running | MSI waits or terminates gracefully | P1 |
| U-05 | Uninstall then reinstall | Clean state, no leftover artifacts | P0 |
| U-06 | Uninstall non-existent version | Graceful error, no crash | P1 |

### 2.3 Update Scenarios

| ID | Scenario | Expected Result | Priority |
|---|---|---|---|
| U-07 | Manifest with `schema_version=99` | Rejected by ManifestValidator | P0 |
| U-08 | Manifest expired (`expires_at` in past) | Rejected, logged | P0 |
| U-09 | Manifest wrong channel (beta→stable) | Rejected | P0 |
| U-10 | Manifest downgrade (installed > minimum) | Rejected | P0 |
| U-11 | Manifest above ceiling (installed > maximum) | Rejected | P0 |
| U-12 | Manifest OS below minimum | Rejected | P0 |
| U-13 | Manifest outside rollout cohort | Rejected (unless force=true) | P0 |
| U-14 | HMAC signature mismatch | Rejected | P0 |
| U-15 | SHA-256 mismatch after download | Rejected, file deleted | P0 |
| U-16 | Download timeout | Retry 5x exponential, then fail | P1 |
| U-17 | Download 404 | Fail immediately | P1 |
| U-18 | Force update (`force=true`) | Bypasses rollout, shows overlay | P0 |
| U-19 | Update during active session | Deferred (not during session) | P1 |
| U-20 | Multiple rapid update attempts | Dedup by fingerprint | P1 |

### 2.4 Recovery Scenarios

| ID | Scenario | Expected Result | Priority |
|---|---|---|---|
| R-01 | Crash loop (3+ consecutive failures) | RecoveryScreen shown with diagnostics | P0 |
| R-02 | Crash loop → auto-recovery succeeds | App relaunches normally | P0 |
| R-03 | Crash loop → auto-recovery fails | User sees FAILED state, can retry or close | P0 |
| R-04 | Integrity failure (hash mismatch) | RecoveryScreen shown, "Launch Anyway" NOT available | P0 |
| R-05 | Startup timeout (watchdog 60s) | RecoveryScreen shown with timing data | P1 |
| R-06 | Lifecycle failure (DB error) | RecoveryScreen shown with phase info | P0 |
| R-07 | RecoveryScreen → Retry | Recovery runs again | P0 |
| R-08 | RecoveryScreen → Close | App exits cleanly | P0 |
| R-09 | RecoveryScreen → Launch Anyway (crash loop only) | App starts despite crash history | P1 |
| R-10 | Recovery after interrupted update | Stale state cleaned, app recovers | P0 |

### 2.5 Enterprise Deployment Scenarios

| ID | Scenario | Expected Result | Priority |
|---|---|---|---|
| E-01 | deploy_config.json with valid config | Validator passes, app reads config | P0 |
| E-02 | deploy_config.json with invalid board_id | Validator rejects with error | P0 |
| E-03 | deploy_config.json with HTTP server URL | Validator warns (not blocks) | P1 |
| E-04 | deploy_config.json with no SSL pin | Validator warns | P1 |
| E-05 | deploy_config.json with placeholder Firebase | Validator warns | P1 |
| E-06 | Fleet deployment (10 boards) | All boards install, register, come online | P0 |
| E-07 | Config backward compat (env.json fallback) | App reads legacy env.json if deploy_config absent | P0 |
| E-08 | Upgrade preserves deploy_config.json | Config intact after MSI upgrade | P0 |

### 2.6 Stability Scenarios

| ID | Scenario | Expected Result | Priority |
|---|---|---|---|
| S-01 | 24-hour continuous run | No memory leaks, heartbeat stable | P0 |
| S-02 | 100 rapid session starts/stops | No state corruption | P1 |
| S-03 | Disk full during download | Graceful error, no crash | P1 |
| S-04 | Disk full during install | MSI rolls back, app intact | P1 |
| S-05 | DLL locked by antivirus | Installer retries or fails gracefully | P2 |
| S-06 | Power loss during install | MSI rollback, system recoverable | P0 |
| S-07 | Power loss during update download | Partial file cleaned on next start | P1 |
| S-08 | Network loss during heartbeat | App continues in offline mode | P1 |
| S-09 | Concurrent app instances | Single-instance guard prevents duplicate | P1 |

---

## 3. Certification Matrix

| Category | Scenarios | Pass Required | Signed Off |
|---|---|---|---|
| Installation | I-01 to I-11 | All P0 | ☐ |
| Uninstallation | U-01 to U-06 | All P0 | ☐ |
| Updates | U-07 to U-20 | All P0 | ☐ |
| Recovery | R-01 to R-10 | All P0 | ☐ |
| Enterprise | E-01 to E-08 | All P0 | ☐ |
| Stability | S-01 to S-09 | S-01, S-06 | ☐ |

**Release gate:** All P0 scenarios must pass. P1 scenarios must have
documented workarounds. P2 scenarios are tracked for future fixes.

---

## 4. Automated Test Script

The `cert_test.ps1` script automates scenarios that can be validated
programmatically:

```powershell
.\scripts\cert_test.ps1 -MsiPath ".\build\IASB-5.5.0.msi" -Verbose
```

Scenarios requiring manual verification (UI, physical power loss, etc.)
are marked as `[MANUAL]` in the output.

---

## 5. Evidence Collection

For each test run, the following evidence must be captured:

1. **Console output** from `cert_test.ps1`
2. **Screenshots** of RecoveryScreen scenarios (R-01 through R-09)
3. **Log files** from `%LOCALAPPDATA%\IntelliAttendSmartBoard\Logs\`
4. **Registry entries** confirming auto-start registration
5. **Event Log entries** from the Update Agent (Application source)
6. **MSI verbose log** (`msiexec /L*V`) for install/uninstall

---

## 6. Files Created

| File | Purpose |
|---|---|
| `scripts/cert_test.ps1` | Automated certification test runner |
| `docs/phase8_production_cert_spec.md` | This document |
