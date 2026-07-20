# IntelliAttend SmartBoard — Deployment Plan

## Vision

A production-ready, self-contained classroom attendance kiosk that runs on any Windows SmartBoard.
Zero-touch installation — faculty enter their SmartBoard ID and password, the system handles everything else.

**Core principles:**
- Offline-resilient (works without internet for extended periods)
- Secure by default (certificate pinning, encrypted storage, Firebase auth)
- Self-updating (OTA via WebSocket, MSI via CI/CD)
- Institution-controlled (admin dashboard manages rooms, schedules, users)

---

## What We've Built

### Application Features (v5.5.0+11)
- [x] Firebase REST authentication (no Flutter plugin — avoids Windows crash)
- [x] Boot → Registration → OTP → Attendance → Summary flow
- [x] Idle screen with WiFi status, network speed, hotspot info
- [x] Session management overlay (Workspace, Attendance, Analytics, Timetable)
- [x] Settings screen with WiFi, Hotspot toggle, Power Off, Restart buttons
- [x] Hold-to-confirm power actions (safety for kiosk deployment)
- [x] Native crash recovery with automatic GPU fallback
- [x] Real-time WebSocket communication with backend
- [x] Auto-update system (check → download → install → relaunch)
- [x] Notification system with persistent vault
- [x] Document viewer (PDF, Office, HTML)
- [x] Compact roll display with lateral entry detection

### Installer (EULA + Clean Install)
- [x] WiX MSI installer with EULA acceptance dialog
- [x] End User License Agreement (LICENSE.txt + License.rtf)
- [x] Privacy Policy (PRIVACY.txt)
- [x] App icon in Windows Programs & Features
- [x] ARP metadata (help link, about link, description)
- [x] Start Menu shortcut with icon
- [x] Auto-start on Windows login (--intelliattend-autostart flag)
- [x] Clean uninstall (removes startup trace, crash flag, app folder)
- [x] Major upgrade support (uninstall old → install new)
- [x] Per-user install (no admin elevation required)
- [x] 64-bit Windows requirement check

### Infrastructure
- [x] CI/CD pipeline (auto-deploy.yml on push to school-main)
- [x] Release workflow (release.yml on v* tag push)
- [x] WiX MSI packaging in CI
- [x] SHA-256 hash generation for integrity verification
- [x] GitHub Release with version manifest (latest.json)
- [x] Server upload endpoint for OTA update distribution
- [x] .env sanitized with placeholders (real keys in GitHub Secrets only)

---

## Current Blocker: GitHub Actions Billing

**Problem:** CI/CD cannot run — GitHub Actions spending limit reached (90%+ consumed on private repo minutes).

**Error from CI:**
> "The job was not started because recent account payments have failed or your spending limit needs to be increased."

**Solution:** Temporarily make the repository public to get unlimited free Actions minutes, build and deploy, then make it private again.

---

## Deployment Execution Plan

### Phase 1 — Clean Sensitive Data from Git History

**Why:** Before making the repo public, we must purge real Firebase API keys and credentials that were committed in earlier commits.

| Task | Details |
|------|---------|
| 1.1 Delete `IntelliAttend-SmartBoard-master/` | Contains `.env` with real `FIREBASE_API_KEY=AIzaSyBazEmYqABDjU9627m5AaVH47piSsB78G8` |
| 1.2 Purge from git history | Use `git filter-repo` or BFG Repo-Cleaner to rewrite all commits |
| 1.3 Sanitize `macos/Runner/GoogleService-Info.plist` | Replace real Firebase API key with placeholder |
| 1.4 Commit + force push | Pushes cleaned history to origin |

**Commands:**
```bash
# Remove the directory
git rm -r IntelliAttend-SmartBoard-master/

# Sanitize GoogleService-Info.plist
# Replace real API key with placeholder

# Commit
git add -A
git commit -m "chore: remove sensitive credentials before making repo public"

# Force push cleaned history
git push origin school-main --force
```

### Phase 2 — Make Repo Public and Build

| Task | Details |
|------|---------|
| 2.1 Make repo public | GitHub → Settings → Danger Zone → Change visibility → Public |
| 2.2 Re-run failed workflow | `gh run rerun 29762655186` or trigger new push |
| 2.3 Wait for CI build | ~12 minutes for Flutter build + WiX packaging |
| 2.4 Verify MSI produced | Check GitHub Release for new MSI artifact |

**Expected CI steps that will run:**
1. `flutter pub get`
2. `dart analyze lib/`
3. `flutter test`
4. Create `.env` from GitHub Secrets
5. `flutter build windows --release` with `--dart-define` flags
6. `candle.exe` → compile `product.wxs` (our fixed WiX with EULA dialog)
7. `light.exe` → produce MSI
8. SHA-256 hash + version manifest
9. Create GitHub Release
10. Upload to server (`/api/v1/board/ci-upload`)

### Phase 3 — Make Repo Private Again

| Task | Details |
|------|---------|
| 3.1 Make repo private | GitHub → Settings → Danger Zone → Change visibility → Private |
| 3.2 Verify download endpoint | `https://api.intelliattend.app/api/v1/board/download/latest` serves new MSI |
| 3.3 Test MSI installation | Download → Run → Verify EULA dialog → Accept → Install → Launch |
| 3.4 Test auth flow | Enter SmartBoard ID + password → Verify server communication |

---

## Post-Deployment: Future CI/CD on Private Repo

Once the repo is private again, you get **2,000 free Actions minutes/month**.
One build takes ~12 minutes, so you can do **~160 builds/month** for free.

**Workflow triggers:**
- Push to `school-main` → Auto-Deploy (builds MSI, creates Release, uploads to server)
- Push `v*` tag → Release (manual versioned release)

**To trigger a build:**
```bash
# Auto-deploy (just push to school-main)
git push origin school-main

# Manual release (tag + push)
git tag v5.5.0.12
git push origin v5.5.0.12
```

---

## Installer UX Flow (What the User Sees)

```
1. Double-click MSI
   ↓
2. Welcome Dialog — "IntelliAttend SmartBoard Setup"
   ↓
3. License Agreement Dialog — EULA text + "I accept" radio button
   [Back]  [I Agree]  [Cancel]
   ↓
4. Ready to Install — Confirmation screen
   [Back]  [Install]
   ↓
5. Progress Bar — Installing files
   ↓
6. Finish Dialog — "Launch IntelliAttend SmartBoard" checkbox
   [Finish]
   ↓
7. App launches → Boot Screen → Registration/Login
```

**On uninstall (via Programs & Features):**
- Removes all application files from `%LocalAppData%\IntelliAttendSmartBoard`
- Removes Start Menu shortcut
- Removes auto-start registry entry
- Cleans up temp files (startup trace, crash flag)
- Removes empty folder

---

## GitHub Secrets and Variables Required

**Secrets** (Settings → Secrets → Actions):
| Secret | Description |
|--------|-------------|
| `FIREBASE_API_KEY` | Firebase Web API key |
| `FIREBASE_APP_ID` | Firebase App ID |
| `FIREBASE_MESSAGING_SENDER_ID` | FCM sender ID |
| `SSL_PIN_FINGERPRINT` | SHA-256 of production TLS cert |
| `DEPLOY_KEY` | Server upload auth key |

**Variables** (Settings → Variables → Actions):
| Variable | Description |
|----------|-------------|
| `API_BASE_URL` | `https://api.intelliattend.app` |
| `FIREBASE_PROJECT_ID` | `intelliattend-a2564` |
| `SERVER_URL` | Backend URL for CI upload |

---

## Open Items

- [ ] Clean `IntelliAttend-SmartBoard-master/` from git history
- [ ] Sanitize `macos/Runner/GoogleService-Info.plist`
- [ ] Make repo public temporarily
- [ ] Re-run failed CI workflow
- [ ] Verify MSI with EULA dialog builds successfully
- [ ] Test production MSI end-to-end
- [ ] Make repo private again
- [ ] Consider adding `-sval` to `release.yml` light.exe call (parity with auto-deploy)
- [ ] Consider pinning Flutter version in `release.yml` (currently uses latest stable)
- [ ] Add `product.wxs` validation step to CI (catch XML errors before WiX build)
