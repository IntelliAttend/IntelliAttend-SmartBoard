# Production Self-Update System — Requirements & Targets

**Branch:** `feat/production-self-update`  
**Base:** `school-dev` (v5.5.0+11)  
**Date:** July 21, 2026  

---

## 1. Objective

Build a complete, production-grade self-updating pipeline so that when code is pushed to `school-main`, every deployed SmartBoard in the field receives the update with a single click from the admin panel — zero manual intervention, zero downtime risk.

---

## 2. Current State (What Exists)

| Component | Status | Notes |
|-----------|--------|-------|
| AutoUpdater (download → install → restart) | ✅ Complete | Stream download, SHA-256 verify, MSI install with retry |
| UpdateOverlay (full-screen UI) | ✅ Complete | Blur backdrop, progress bar, error handling |
| UpdateHealthMonitor (rollback) | ✅ Complete | Crash-loop detection, PowerShell rollback script |
| Rollout cohort (canary deployment) | ✅ Complete | Deterministic hash-based percentage rollout |
| WebSocket push (admin → board) | ✅ Complete | Instant `update_available` message |
| Heartbeat config delivery | ✅ Complete | Periodic `force_update` block in heartbeat response |
| WiX MSI installer (EULA, auto-start) | ✅ Complete | Per-user install, major upgrade support |
| CI/CD pipeline (GitHub Actions) | ⚠️ Blocked | GitHub Actions billing limit reached |
| Server upload endpoint (`/api/v1/board/ci-upload`) | ✅ Exists | Receives MSI + manifest from CI |
| Admin panel UI (trigger updates) | ❌ Not in this repo | Server-side dashboard (external) |
| Disk space check before download | ❌ Stubbed | `_hasEnoughDiskSpace()` always returns `true` |
| Authenticode signature verification | ❌ Not implemented | Comments mention WinTrust API, no code |
| Production `.env` on target PCs | ⚠️ Manual | `install_production_msi.ps1` handles this, but not automated |

---

## 3. Requirements

### 3.1 CI/CD Pipeline (Push → MSI → Server)

| ID | Requirement | Priority | Target |
|----|-------------|----------|--------|
| C1 | Push to `school-main` triggers automated Flutter build + WiX MSI packaging | P0 | Week 1 |
| C2 | MSI uploaded to server via `/api/v1/board/ci-upload` with SHA-256 hash | P0 | Week 1 |
| C3 | Version manifest (`latest.json`) generated and uploaded | P0 | Week 1 |
| C4 | GitHub Release created with MSI artifact | P1 | Week 1 |
| C5 | Build uses `--dart-define` flags from GitHub Secrets (no `.env` in repo) | P0 | Week 1 |
| C6 | Build succeeds on private repo Actions (2,000 min/month budget) | P0 | Week 1 |
| C7 | `dart analyze` + `flutter test` gate before build (fail-fast) | P1 | Week 1 |

### 3.2 Admin Panel → Board Update Trigger

| ID | Requirement | Priority | Target |
|----|-------------|----------|--------|
| A1 | Admin panel displays current version of every registered board | P0 | Week 2 |
| A2 | Admin panel shows board update status (stable/pending/failed/rolled_back) | P0 | Week 2 |
| A3 | Admin clicks "Update" → server pushes `update_available` WebSocket to target boards | P0 | Week 2 |
| A4 | Admin can select target boards (single, group, all) for update rollout | P1 | Week 2 |
| A5 | Admin can set rollout percentage (canary → full) | P1 | Week 2 |
| A6 | Admin can force-update (bypass cohort check) for critical patches | P1 | Week 2 |
| A7 | Admin panel shows real-time update progress per board | P2 | Week 3 |
| A8 | Admin panel logs all update events (triggered, completed, failed, rolled back) | P2 | Week 3 |

### 3.3 Client-Side Update Hardening

| ID | Requirement | Priority | Target |
|----|-------------|----------|--------|
| L1 | Disk space check before download (implement `GetDiskFreeSpaceExW` via FFI) | P1 | Week 1 |
| L2 | Authenticode signature verification of downloaded MSI before install | P2 | Week 2 |
| L3 | Update progress persisted to disk — survives crash mid-download, resumes on restart | P1 | Week 1 |
| L4 | Download resume (HTTP Range header) for large MSI files on slow connections | P2 | Week 2 |
| L5 | Board reports update outcome to server on every attempt (success/fail/rollback) | P0 | Already exists |
| L6 | Maximum 3 consecutive update failures before disabling auto-update for that version | P1 | Week 1 |
| L7 | Graceful handling of network loss during download (retry with exponential backoff) | P1 | Week 1 |

### 3.4 Installer & Deployment

| ID | Requirement | Priority | Target |
|----|-------------|----------|--------|
| I1 | MSI installs cleanly on Windows 10/11 x64 with no admin elevation | P0 | Already exists |
| I2 | `install_production_msi.ps1` writes production `.env` to target PC | P0 | Already exists |
| I3 | Post-install auto-launch with `--intelliattend-autostart` flag | P0 | Already exists |
| I4 | Major upgrade (uninstall old → install new) preserves user registration | P0 | Already exists |
| I5 | Uninstall cleans up all artifacts (startup trace, crash flag, app folder) | P0 | Already exists |

### 3.5 Safety & Rollback

| ID | Requirement | Priority | Target |
|----|-------------|----------|--------|
| S1 | Crash-loop detection triggers automatic rollback to previous version | P0 | Already exists |
| S2 | Pre-update backup of entire install directory | P0 | Already exists |
| S3 | 3-startup stabilization window before marking version as stable | P0 | Already exists |
| S4 | Server notified of every update outcome (completed/failed/rolled_back) | P0 | Already exists |
| S5 | Rollback restores app to exact previous state (config, data, binaries) | P0 | Already exists |

---

## 4. Implementation Phases

### Phase 1 — CI/CD Pipeline (Week 1)
- [ ] Fix GitHub Actions billing or make repo public temporarily
- [ ] Create/update `.github/workflows/auto-deploy.yml` for `school-main` push
- [ ] Add Flutter build + WiX packaging steps
- [ ] Add SHA-256 hash generation + version manifest
- [ ] Add server upload step (`/api/v1/board/ci-upload`)
- [ ] Add `dart analyze` + `flutter test` gates
- [ ] Verify end-to-end: push → build → MSI → server

### Phase 2 — Client Hardening (Week 1-2)
- [ ] Implement `_hasEnoughDiskSpace()` with `GetDiskFreeSpaceExW` FFI
- [ ] Add download resume support (HTTP Range headers)
- [ ] Persist download progress to disk for crash recovery
- [ ] Add exponential backoff retry on network loss
- [ ] Add max consecutive failure counter (3 strikes → disable)

### Phase 3 — Admin Panel Integration (Week 2-3)
- [ ] Server API: `GET /api/v1/board/{id}/update-status` → current version + health
- [ ] Server API: `POST /api/v1/board/trigger-update` → push WebSocket to targets
- [ ] Server API: `GET /api/v1/board/update-history` → audit log
- [ ] Admin panel: Board list with version + update status columns
- [ ] Admin panel: "Update" button per board / group / all
- [ ] Admin panel: Rollout percentage slider
- [ ] Admin panel: Real-time progress display

### Phase 4 — Testing & Validation (Week 3)
- [ ] Test full pipeline: push → CI → MSI → server → board updates
- [ ] Test rollback: install bad version → crash loop → auto-rollback
- [ ] Test canary: 10% rollout → verify → 100% rollout
- [ ] Test force update: bypass cohort, all boards update
- [ ] Test network loss during download → resume on reconnect
- [ ] Test disk space check → reject update if insufficient
- [ ] Test concurrent updates (multiple boards updating simultaneously)

---

## 5. Success Criteria

| Metric | Target |
|--------|--------|
| Push-to-update latency | < 15 minutes (push → all boards updated) |
| Update success rate | > 99% (excluding intentional rollbacks) |
| Rollback recovery time | < 30 seconds (crash → rollback → running) |
| Zero manual intervention | Admin clicks once, all target boards update |
| No data loss | Registration + config preserved across updates |

---

## 6. Out of Scope (This Branch)

- macOS / Linux update support (Windows only for now)
- Delta updates (full MSI replacement)
- Auto-update from non-admin channels (e.g., user-initiated)
- Mobile app updates (separate codebase)
