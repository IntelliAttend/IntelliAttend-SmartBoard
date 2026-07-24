# Phase 11 — Operational Readiness Specification

**Version**: 1.0  
**Status**: Complete  
**Phase**: 11 of 12  
**Architecture Freeze**: Applies (documentation and runbooks only)

---

## 1. Scope

Operational readiness for deploying, monitoring, and recovering the IntelliAttend SmartBoard application at scale across school environments. Covers: deployment runbooks, rollback procedures, monitoring dashboards, incident response playbooks, and go/no-go criteria.

---

## 2. Release Mindset

From "building features" → **"release candidates"**:

| Stage | Gate | Exit Criteria |
|-------|------|---------------|
| RC1 | Internal testing | All P0 cert scenarios pass (31/31) |
| RC2 | Pilot schools (3-5 sites) | 7-day uptime > 99%, zero data loss incidents |
| RC3 | Production rollout (10%→50%→100%) | 14-day uptime > 99.5%, zero rollback triggers |

---

## 3. Deployment Runbooks

### 3.1 Fresh Install (IT Admin)

**Prerequisites:**
- Windows 10/11 (x64), 4 GB RAM, 500 MB free disk
- Network access to `api.intelliattend.app`
- Local admin privileges (for MSI install)
- `deploy_config.json` provisioned (or server-side config)

**Steps:**
```
1. Download MSI from: https://api.intelliattend.app/api/v1/board/download/latest
2. Verify SHA-256 hash against manifest (optional but recommended)
3. Run: msiexec /i IntellAttend_SmartBoard.msi /qn /l*v install.log
4. Wait for agent to complete (check Event Log → Application → Source: "IntelliAttendAgent")
5. Verify install: %LOCALAPPDATA%\IntelliAttendSmartBoard\App\intelliattend_smartboard.exe
6. Launch app — registration flow begins automatically
```

**Expected Duration:** 2-5 minutes  
**Rollback:** `msiexec /x {ProductCode} /qn`

### 3.2 Silent Install (SCCM/Intune/GPO)

**Prerequisites:**
- `deploy_config.json` pre-provisioned at `%LOCALAPPDATA%\IntelliAttendSmartBoard\Config\deploy_config.json`
- Or: server-side config endpoint configured

**SCCM Command Line:**
```
msiexec /i IntellAttend_SmartBoard.msi /qn /l*v %TEMP%\intelliattend_install.log
```

**Intune Win32 App:**
- Install command: `msiexec /i IntellAttend_SmartBoard.msi /qn`
- Uninstall command: `msiexec /x {ProductCode} /qn`
- Detection: File exists at `%LOCALAPPDATA%\IntelliAttendSmartBoard\App\intelliattend_smartboard.exe`

**Expected Duration:** 3-8 minutes (including agent setup)  
**Rollback:** `msiexec /x {ProductCode} /qn` (or SCCM/Intune automatic rollback)

### 3.3 In-Place Upgrade (v3.x → v5.x)

**Trigger:** New manifest via heartbeat or WebSocket `update_available`  
**Owner:** Auto-updater (app-internal) + update agent (detached)

**Flow:**
```
1. App receives update manifest (via heartbeat config or WebSocket push)
2. ManifestValidator performs 8 checks (schema, expiry, channel, version, OS, rollout, HMAC, signature)
3. AutoUpdater downloads MSI to %LOCALAPPDATA%\IntelliAttendSmartBoard\Updates\
4. SHA-256 hash verification (streaming)
5. App writes update_state.json with PID, version, agent path
6. App launches update_agent.exe (detached)
7. App exits
8. Agent: waits for app PID to die (30s timeout)
9. Agent: backs up current install → Updates\backup\
10. Agent: runs msiexec /i with REINSTALL=v files REINSTALLMODE=vomus
11. Agent: waits for MSI exit code (3 retries on failure)
12. Agent: launches new app version
13. Agent: exits
```

**Expected Duration:** 30-180 seconds  
**Rollback:** Automatic via UpdateHealthMonitor crash loop detection (3 failed starts → restore backup)

### 3.4 Emergency Rollback (Manual)

**When:** Automated rollback failed, or manual intervention required  
**Prerequisites:** Backup exists at `%LOCALAPPDATA%\IntelliAttendSmartBoard\Updates\backup\`

**Steps:**
```
1. Kill running app: taskkill /F /IM intelliattend_smartboard.exe
2. Kill update agent if running: taskkill /F /IM update_agent.exe
3. Navigate to: %LOCALAPPDATA%\IntelliAttendSmartBoard\Updates\backup\
4. Copy App\ contents to %LOCALAPPDATA%\IntelliAttendSmartBoard\App\
5. Launch: %LOCALAPPDATA%\IntelliAttendSmartBoard\App\intelliattend_smartboard.exe
6. Verify version in Settings → About
7. Report incident with diagnostic bundle
```

**Expected Duration:** 5-15 minutes  
**Data Loss:** None (Data\ directory is preserved across upgrades)

### 3.5 Uninstall (Clean)

**Steps:**
```
1. Kill running app: taskkill /F /IM intelliattend_smartboard.exe
2. Kill update agent if running: taskkill /F /IM update_agent.exe
3. Run: msiexec /x {ProductCode} /qn
4. Verify removal: %LOCALAPPDATA%\IntelliAttendSmartBoard\ should not exist
5. Clean up registry: HKCU\Software\IntelliAttend\ (if residual)
```

**Note:** Data directory (`%LOCALAPPDATA%\IntelliAttendSmartBoard\Data\`) is preserved on uninstall by design. To fully remove: `rmdir /s /q %LOCALAPPDATA%\IntelliAttendSmartBoard`

---

## 4. Monitoring Dashboard

### 4.1 Sentry Dashboard

**Project:** `intelliattend-smartboard`  
**URL:** `https://sentry.io/organizations/intelliattend/projects/`

**Key Views:**

| View | Filter | Alert Threshold |
|------|--------|-----------------|
| Crash Rate | `environment:production` | > 1% daily crash rate |
| Release Adoption | `release:intelliattend@{version}` | Track adoption curve |
| Error Volume by Type | Grouped by `error.type` | Spike > 2x baseline |
| Performance: Lifecycle | `transaction:lifecycle_boot` | p95 > 5s |
| Performance: Update | `transaction:update_download` | p95 > 120s |

**Tags to Monitor:**
- `board.id` — per-device health
- `app.version` — version-specific issues
- `release.channel` — stable vs beta vs dev
- `lifecycle.phase` — which phase fails most

### 4.2 Server-Side Metrics

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| Active boards | Registration API | < expected count |
| Heartbeat frequency | Heartbeat API | Missing > 2x interval |
| Update adoption rate | Update manifest endpoint | < 50% after 7 days |
| API error rate | API gateway logs | > 5% 5xx rate |
| WebSocket connections | WebSocket server | < expected count |

### 4.3 Local Health Indicators

| Indicator | Location | Check |
|-----------|----------|-------|
| Crash loop detection | Windows Registry `HKCU\Software\IntelliAttend` | `LaunchCount > 3 in 5 min` |
| Update state | `%LOCALAPPDATA%\IntelliAttendSmartBoard\Updates\update_state.json` | File exists = update in progress |
| Recovery state | `RecoveryManager.state` | `type != none` |
| Health snapshot | `HealthSnapshot.capture()` | Available via diagnostic bundle |
| Sentry breadcrumbs | Sentry dashboard | Last 100 events before error |

---

## 5. Incident Response Playbooks

### 5.1 Playbook: Crash Loop (Multiple Boards Affected)

**Symptoms:** Sentry shows > 5% crash rate for a specific version  
**Severity:** P1 — Users cannot use the application

**Response:**
```
1. IDENTIFY: Check Sentry for the crashing version and error type
2. TRIAGE: Is it a regression in the new version, or a server-side issue?
3. CONTAIN: If regression → disable auto-update manifest (set rolloutPercentage: 0)
4. REMEDIATE:
   a. Server-side fix → deploy and re-enable manifest
   b. Code fix → release hotfix version
   c. Config fix → push new deploy_config.json
5. RECOVER: Users on broken version will auto-recover via crash loop detection
   (3 failed starts → restore backup → launch previous version)
6. VERIFY: Monitor Sentry for 24 hours; confirm crash rate returns to baseline
```

### 5.2 Playbook: Failed Update (Multiple Boards)

**Symptoms:** Multiple boards report update failure in Sentry  
**Severity:** P1 — Boards stuck on old version

**Response:**
```
1. IDENTIFY: Check UpdateHealthMonitor reports in Sentry
2. TRIAGE: Download failure? MSI corruption? Agent crash?
3. CONTAIN: Disable manifest (rolloutPercentage: 0) to prevent more boards from attempting
4. REMEDIATE:
   a. Download failure → check CDN/API availability
   b. MSI corruption → regenerate and re-sign MSI
   c. Agent crash → check Event Log for agent errors
5. RECOVER: Boards with backup will auto-rollback. Others need manual rollback (Section 3.4)
6. VERIFY: Monitor update success rate for 48 hours
```

### 5.3 Playbook: SSL Certificate Pin Failure

**Symptoms:** Multiple boards report `SslPinningService` errors in Sentry  
**Severity:** P0 — All API communication blocked

**Response:**
```
1. IDENTIFY: Check if server certificate was renewed/rotated
2. CONTAIN: If certificate rotation → push new deploy_config.json with updated pin
3. REMEDIATE: Update SSL pin fingerprint in deploy_config.json
   - Generate new pin: openssl x509 -in cert.pem -noout -fingerprint -sha256
   - Update deploy_config.json → ssl_pin_fingerprint
   - Push via server-side config endpoint
4. RECOVER: Boards will pick up new config on next heartbeat (1-5 minutes)
5. VERIFY: Confirm SSL errors stop appearing in Sentry
```

### 5.4 Playbook: Data Loss Concern

**Symptoms:** Board reports corrupted data, missing sessions, or database errors  
**Severity:** P0 — Potential attendance data loss

**Response:**
```
1. IDENTIFY: Check Isar error logs in %LOCALAPPDATA%\IntelliAttendSmartBoard\Logs\
2. TRIAGE: Is it a single board or multiple? Local corruption or server-side?
3. CONTAIN:
   a. If Isar corruption → app auto-recovers via lifecycle RECOVERY phase
   b. If data mismatch → check server-side Firestore for data integrity
4. REMEDIATE:
   a. Single board → export diagnostic bundle, investigate locally
   b. Multiple boards → check server API for data consistency
5. RECOVER: Data is backed up in Firestore; local Isar can be rebuilt from server state
6. VERIFY: Cross-check attendance records with server database
```

---

## 6. Go/No-Go Criteria

### 6.1 RC1 → Internal Testing

| # | Criterion | Status |
|---|-----------|--------|
| 1 | All 31 P0 certification scenarios pass | ⬜ Pending execution |
| 2 | Zero high-severity security findings unresolved | ⬜ S-01, S-02, S-03 |
| 3 | Startup time < 3 seconds (p95) | ⬜ Pending measurement |
| 4 | Memory usage < 100 MB steady-state | ⬜ Pending measurement |
| 5 | Sentry integration verified (test error appears in dashboard) | ⬜ Pending |
| 6 | Diagnostic bundle export verified | ⬜ Pending |

### 6.2 RC2 → Pilot Schools

| # | Criterion | Status |
|---|-----------|--------|
| 1 | 3-5 pilot schools for 7 days | ⬜ Pending |
| 2 | Uptime > 99% across pilot fleet | ⬜ Pending |
| 3 | Zero data loss incidents | ⬜ Pending |
| 4 | Update success rate > 95% | ⬜ Pending |
| 5 | No SSL pin failures | ⬜ Pending |
| 6 | Feedback from IT admins collected | ⬜ Pending |

### 6.3 RC3 → Production Rollout

| # | Criterion | Status |
|---|-----------|--------|
| 1 | 14-day uptime > 99.5% | ⬜ Pending |
| 2 | Crash rate < 0.5% daily | ⬜ Pending |
| 3 | Update adoption > 90% within 7 days | ⬜ Pending |
| 4 | No P0/P1 incidents in pilot | ⬜ Pending |
| 5 | Rollback rate < 2% | ⬜ Pending |
| 6 | All P1 security findings remediated | ⬜ Pending |

---

## 7. Rollback Strategy

### 7.1 Automated Rollback (UpdateHealthMonitor)

**Trigger:** 3 consecutive failed starts on a new version  
**Action:** PowerShell script restores backup from `Updates\backup\`  
**User Impact:** Brief restart; app relaunches on previous version  
**Data Impact:** None (Data\ directory preserved)

### 7.2 Server-Side Rollback (Manifest)

**Trigger:** Manual decision by operations team  
**Action:** Set `rolloutPercentage: 0` on manifest, or set `maximumVersion` to current version  
**User Impact:** Boards stop receiving update; already-updated boards unaffected  
**Data Impact:** None

### 7.3 Manual Rollback (IT Admin)

**Trigger:** Automated rollback failed  
**Action:** Follow Section 3.4 (Emergency Rollback)  
**User Impact:** 5-15 minute downtime  
**Data Impact:** None (Data\ directory preserved)

---

## 8. Diagnostic Bundle Usage

### For IT Admins:
```
1. App launches → Recovery screen (if issues detected)
2. Click "Export Diagnostics" → ZIP saved to Desktop
3. Submit ZIP to: support@intelliattend.app
```

### For Support Team:
```
1. Receive diagnostic ZIP
2. Open health.json → check board ID, version, lifecycle state
3. Open lifecycle.json → check phase timings and errors
4. Open recovery_state.json → check recovery type and history
5. Check logs/ → look for errors, warnings
6. Cross-reference with Sentry dashboard using board ID
```

---

## 9. Acceptance Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | 5 deployment runbooks written (fresh, silent, upgrade, rollback, uninstall) | ✅ |
| 2 | Monitoring dashboard defined (Sentry + server + local) | ✅ |
| 3 | 4 incident response playbooks written | ✅ |
| 4 | Go/no-go criteria defined for RC1, RC2, RC3 | ✅ |
| 5 | Rollback strategy defined (automated, server-side, manual) | ✅ |
| 6 | Diagnostic bundle usage documented | ✅ |
| 7 | Architecture freeze maintained — no code changes | ✅ |
