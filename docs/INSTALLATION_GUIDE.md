# IntelliAttend SmartBoard — Installation Guide

> **Locked reference:** This document describes the canonical installer, distribution
> pipeline, and installation/uninstall lifecycle as of the Inno Setup migration
> (v5.5.0.12+, July 2026).
>
> **Supersedes:** `installation_experience_report_v5.5.0.12.md` (MSI-era audit)

---

## Table of Contents

1. [Installer Overview](#1-installer-overview)
2. [Installer Properties](#2-installer-properties)
3. [Installation Lifecycle](#3-installation-lifecycle)
4. [Install Modes](#4-install-modes)
5. [Uninstall](#5-uninstall)
6. [Versioning & File Naming](#6-versioning--file-naming)
7. [Distribution Pipeline](#7-distribution-pipeline)
8. [Download Channels](#8-download-channels)
9. [Verification](#9-verification)
10. [Auto-Update Flow](#10-auto-update-flow)
11. [Troubleshooting](#11-troubleshooting)
12. [Appendices](#12-appendices)

---

## 1. Installer Overview

The SmartBoard application is packaged as a **single Windows installer** built with
[Inno Setup 6](https://jrsoftware.org/isinfo.php) (the _de facto_ standard Windows
installer engine). The installer:

- Produces a single `IntelliAttendSmartBoard-<version>-Setup.exe` file.
- Compresses all application files with **LZMA2/ultra64** — the highest
  compression ratio, resulting in a ~20 MB download for a ~55 MB installed app.
- Displays a **modern wizard-style UI** with license agreement page.
- Installs **per-user** into `%LOCALAPPDATA%\IntelliAttendSmartBoard\` —
  **no administrative privileges are required**.
- **Gracefully closes** any running SmartBoard instance before installation
  (app handles `--exit` flag).
- **Auto-launches** the app after a successful install (skipped in silent mode).

### Source Script

The Inno Setup script lives at:

```
windows/inno_setup/setup.iss
```

---

## 2. Installer Properties

| Property | Value |
|---|---|
| **Application ID** | `{{865FA9F9-CBE0-4650-8444-D3B4168B49C1}` |
| **Application Name** | IntelliAttend SmartBoard |
| **Publisher** | IntelliAttend |
| **Default Install Directory** | `%LOCALAPPDATA%\IntelliAttendSmartBoard\` |
| **Privilege Level** | `lowest` (per-user, no admin required) |
| **Architecture** | x64 only |
| **Minimum OS** | Windows 10 1809 (10.0.17763) |
| **Compression** | LZMA2 / ultra64 |
| **Solid Compression** | Yes |
| **Wizard Style** | Modern |
| **License File** | `LICENSE` (root of repo) |
| **Setup Icon** | `windows/runner/resources/app_icon.ico` |
| **App Executable** | `intelliattend_smartboard.exe` |
| **Authenticode Signing** | Optional (via `SIGN_CERT_BASE64` / `SIGN_PASSWORD` secrets) |



### What Gets Installed

- The entire `flutter build windows --release` output (compiled Flutter app +
  native DLLs) → `{app}\`
- A `data\` subfolder (marked for full removal on uninstall)
- Start Menu group **IntelliAttend SmartBoard** containing:
  - Application shortcut
  - Uninstall shortcut
- **Optional** desktop shortcut (checked by default in wizard; user can opt out)

### What Gets Run

```inno
[Run]
Filename: "{app}\intelliattend_smartboard.exe"; Flags: nowait postinstall skipifsilent
```

The app launches automatically after install completes. In silent/enterprise
mode (`/SILENT` or `/VERYSILENT`), this step is skipped.

---

## 3. Installation Lifecycle

### 3.1 Before Install: Graceful Shutdown

The installer first checks if a running instance exists and tells it to exit:

```pascal
// setup.iss — InitializeSetup()
ExePath := ExpandConstant('{localappdata}\IntelliAttendSmartBoard\intelliattend_smartboard.exe');
Exec(ExePath, '--exit', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
```

This ensures file locks are released before overwriting.

### 3.2 During Install

1. Files are decompressed and written to `{app}` (recursive).
2. `data\` directory is created.
3. Start Menu shortcuts are registered.
4. Desktop shortcut is created if the user opted in (wizard) or default (silent).
5. License terms are displayed (interactive mode only).

### 3.3 After Install

- The app auto-launches (interactive mode only; configures itself on first run).
- On first launch, the app prompts the user to enter their **SmartBoard ID**
  (e.g. `IASB-4208`).
- The app registers itself with the server, downloads its configuration,

---

## 6. Versioning & File Naming

### 6.1 Version Formats

| Context | Format | Example |
|---|---|---|
| **Git tag** | `v<major>.<minor>.<patch>[.<build>]` | `v5.5.0.12` |
| **Setup filename** | `IntelliAttendSmartBoard-<major.minor.patch.build>-Setup.exe` | `IntelliAttendSmartBoard-5.5.0.12-Setup.exe` |
| **Flutter pubspec** | `<major>.<minor>.<patch>+<build>` | `5.5.0+12` |
| **Server manifest** | Flutter format | `5.5.0+12` |

### 6.2 File Naming Convention

```
IntelliAttendSmartBoard-{version}-Setup.exe
IntelliAttendSmartBoard-{version}.sha256          (SHA-256 hash file on GitHub)
```

The server stores the installer using the **Flutter pubspec version**
(`IntelliAttendSmartBoard-5.5.0+12-Setup.exe`) so that the board's auto-update

### 7.1 Step 9: CI Upload (Server Sync)

After creating the GitHub Release, the workflow auto-uploads the installer to the
IntelliAttend Server via `POST /api/v1/board/ci-upload`:

```bash
curl -X POST https://api.intelliattend.app/api/v1/board/ci-upload \
  -H "X-Deploy-Key: ${{ secrets.DEPLOY_KEY }}" \
  -F "version=5.5.0+12" \
  -F "release_notes=Auto-deploy from commit abc123" \
  -F "commit_hash=abc123" \
  -F "force=true" \
  -F "rollout_percentage=100" \
  -F "file=@IntelliAttendSmartBoard-5.5.0.12-Setup.exe"
```

The server:
1. Stores the file at `updates/IntelliAttendSmartBoard-5.5.0+12-Setup.exe`
2. **Copies** it to `static/smartboard/IntelliAttendSmartBoard-5.5.0+12-Setup.exe`
   (served by `/download/latest`)
3. Updates the DB `force_update` manifest (canonical source for boards)
4. Writes `updates/latest.json` (filesystem fallback)
5. Busts the Redis board-config cache

**This keeps GitHub Releases and the server in sync.** Every release that goes to
GitHub also lands on the server, eliminating the "No installer found" class of
errors.

> **Fallback:** If the server upload fails after 10 retries (30s apart), the
> workflow exits with an error. The GitHub Release is already created, so the
> installer is still available via the direct GitHub link and the server's
> GitHub redirect fallback (see §8.3). The error alerts the team to investigate.

---

## 8. Download Channels

### 8.1 Admin Panel (Primary)

```
Admin Panel → SmartBoard Software page
  → GET {API_BASE_URL}/api/v1/board/release/latest   (release info)
  → GET {API_BASE_URL}/api/v1/board/download/latest   (file download)
```

The Admin Panel fetches release metadata from `/release/latest` and the
download button points to `/download/latest`.

### 8.2 GitHub Releases (Canonical)

```
https://github.com/IntelliAttend/IntelliAttend-SmartBoard/releases
```

All releases are published as GitHub Release assets. The server polls the
GitHub API to enrich the `/release/latest` metadata (tag name, release date,
release notes).

### 8.3 GitHub Redirect Fallback (Worst-Case Safety Net)

If the server has no local installer (`/download/latest` returns 404), the
endpoint automatically falls back to a **307 redirect** to the latest
`-Setup.exe` asset on GitHub. This ensures the Admin Panel download button
**never dead-ends** while a release exists on GitHub.

This is the **last resort** — the canonical path is to serve the installer from

---

## 9. Verification

### 9.1 SHA-256

Every release publishes a `.sha256` file alongside the installer:

```bat
curl -O https://github.com/IntelliAttend/IntelliAttend-SmartBoard/releases/download/v5.5.0.12/IntelliAttendSmartBoard-5.5.0.12.sha256
certutil -hashfile IntelliAttendSmartBoard-5.5.0.12-Setup.exe SHA256
type IntelliAttendSmartBoard-5.5.0.12.sha256
```

### 9.2 Server vs GitHub Comparison

The `/release/latest` endpoint performs a three-way consistency check implicitly:
the server filename, size, and the GitHub API asset name and size should match.

### 9.3 Authenticode Signature (When Present)

If the build is configured with signing secrets, the installer is
Authenticode-signed with a timestamp from DigiCert. To verify:

```powershell
Get-AuthenticodeSignature -FilePath IntelliAttendSmartBoard-5.5.0.12-Setup.exe | Format-List
```

---

## 10. Auto-Update Flow

The SmartBoard app updates itself **silently in the background** without user
intervention. This is the primary update path for deployed boards.

### 10.1 Sequence

```
  SmartBoard App          IntelliAttend Server        Update Agent
       │                         │                        │
       │  Poll manifest          │                        │
       ├────────────────────────→│                        │
       │  { minimum_version,     │                        │
       │    download_url,         │                        │
       │    sha256, ... }        │                        │
       │←────────────────────────┤                        │
       │                         │                        │
       │  Download installer     │                        │
       ├────────────────────────→│                        │
       │←────────────────────────┤                        │
       │  Installer.exe          │                        │
       │                         │                        │
       │  Launch update agent    │                        │
       ├─────────────────────────────────────────────────→│
       │                         │                        │
       │                         │                 /VERYSILENT
       │                         │                 install
       │                         │                        │
       │←─────────────────────────────────────────────────┤

---

## 11. Troubleshooting

### 11.1 "No installer found" (Admin Panel Download)

**Cause:** The server has no `IntelliAttendSmartBoard-*.exe` file in its
`static/smartboard/` or `updates/` directories. This happens when a new
version was released to GitHub but the CI upload step (§7.1) failed or the
release was published before the pipeline was updated.

**Fix (one-time):** Upload the latest installer via the Admin Panel's
**Update Management** page, or via curl:

```bash
curl -X POST https://api.intelliattend.app/api/v1/board/upload-update \
  -H "Authorization: Bearer <admin-token>" \
  -F "version=5.5.0+12" \
  -F "file=@IntelliAttendSmartBoard-5.5.0.12-Setup.exe"
```

**Permanent fix:** Ensure `release.yml` has the CI upload step configured
with `SERVER_URL` variable and `DEPLOY_KEY` secret in the repository.

### 11.2 SmartBoard ID Not Accepted

After installation and first launch, the app prompts for a SmartBoard ID.
Ensure the ID follows the pattern `IASB-XXXX` and has been pre-registered in
the Admin Panel under **SmartBoards**.

### 11.3 App Fails to Launch

1. Check Windows Event Viewer for .NET / Flutter engine crashes.
2. Verify the GPU driver is up to date (known issue with Intel Iris Xe
   driver 27.20.100.8935).
3. Run `intelliattend_smartboard.exe --verbose` from a command prompt.
4. Check the logs at `%LOCALAPPDATA%\IntelliAttendSmartBoard\data\logs\`.

### 11.4 Auto-Update Not Working

- Verify the board is connected to the internet and can reach
  `https://api.intelliattend.app`.
- Check the server's `/check-update` manifest has a `minimum_version` greater
  than the board's current version.
- Check the update agent logs (same directory as app logs).
- If `DEPLOY_KEY` was rotated, update the repository secret and re-run the
  release workflow.

### 11.5 Uninstall Leaves Files

The per-user uninstaller cleans `{app}` including `data\`. If files remain,
the user may have installed under a different account (per-machine install)
or manually placed files. Run `unins000.exe` as the same user who installed.

---

## 12. Appendices

### A. File Map

| Path | Purpose |
|---|---|
| `windows/inno_setup/setup.iss` | Inno Setup script — the authoritative installer definition |
| `build/windows/x64/runner/Release/` | Build output (Flutter) |
| `updates/latest.json` | Server filesystem manifest (fallback) |
| `static/smartboard/` | Server static dir for Admin Panel downloads |
| `backend/app/api/v1/board.py` | `/download/latest`, `/release/latest` endpoints |
| `backend/app/api/v1/board_update.py` | `/check-update`, `/upload-update`, `/ci-upload` endpoints |
| `backend/app/services/board/board_update_service.py` | Upload logic, file storage, manifest generation |
| `.github/workflows/release.yml` | Tag-triggered release workflow (publishes to GitHub + server) |
| `.github/workflows/auto-deploy.yml` | Push-triggered deploy workflow (includes server upload) |
| `src/features/smartboards/pages/SmartBoardDownload.tsx` | Admin Panel download page (AdminPanel repo) |
| `src/features/updates/pages/UpdateManagement.tsx` | Admin Panel update upload page (AdminPanel repo) |

### B. Related Documents

| Document | Content |
|---|---|
| [`docs/SERVER_MIGRATION_GUIDE_INNO_SETUP.md`](./SERVER_MIGRATION_GUIDE_INNO_SETUP.md) | Server-side changes for MSI→EXE migration |
| [`docs/OTA_UPDATE_SYSTEM.md`](./OTA_UPDATE_SYSTEM.md) | Auto-update manifest format and agent design |
| [`docs/DEPLOYMENT_WINDOWS.md`](./DEPLOYMENT_WINDOWS.md) | Windows deployment notes |
| [`docs/MSI_TO_EXE_MIGRATION_PLAN.md`](./MSI_TO_EXE_MIGRATION_PLAN.md) | Migration plan document |
| [`docs/production_installation_audit_v5.5.0.12.md`](./production_installation_audit_v5.5.0.12.md) | Production installation audit |
| [`docs/release_acceptance_checklist.md`](./release_acceptance_checklist.md) | Release acceptance checklist |
| [`windows/update_agent/`](../windows/update_agent/) | Auto-update agent source code (C++) |

       │  Install complete       │                        │
       │                         │                        │
       │  Restart app            │                        │
```

### 10.2 API Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/board/check-update` | GET | Board polls for latest manifest (DB canonical, filesystem fallback) |
| `/api/v1/board/download-update/{filename}` | GET | Board downloads installer file from `updates/` |
| `/api/v1/board/upload-update` | POST | Admin uploads installer (admin/super_admin role) |
| `/api/v1/board/ci-upload` | POST | CI upload (authenticated via `X-Deploy-Key`) |

### 10.3 Update Agent

The update agent (C++) at `windows/update_agent/`:
- Downloads installer from manifest URL
- Verifies SHA-256 integrity
- Runs installer with `/VERYSILENT /SUPPRESSMSGBOXES`
- Monitors process and reports back
- Restarts main app after success

For full details see:
- [`docs/OTA_UPDATE_SYSTEM.md`](./OTA_UPDATE_SYSTEM.md)
- [`docs/SERVER_MIGRATION_GUIDE_INNO_SETUP.md`](./SERVER_MIGRATION_GUIDE_INNO_SETUP.md)

the server's own storage, synced via the CI upload step (§7.1).

comparison logic works correctly. The download endpoint finds and serves any
file matching `IntelliAttendSmartBoard-*.exe`, regardless of which separator
is used.

---

## 7. Distribution Pipeline

```
  Git tag v5.5.0.12 (push)
       │
       ▼
  release.yml (GitHub Actions)
       │
       ├─ 1. Verify SSL pin
       ├─ 2. Build Flutter Windows release
       ├─ 3. Package with Inno Setup
       ├─ 4. Authenticode-sign (if cert present)
       ├─ 5. Compute SHA-256
       ├─ 6. Create version manifest (latest.json)
       ├─ 7. Upload artifacts to GitHub Actions
       ├─ 8. Create GitHub Release ────────────────► assets on GitHub Releases
       └─ 9. CI upload to server ──────────────────► updates/ + static/smartboard/

  and displays the Idle Screen.

---

## 4. Install Modes

### 4.1 Interactive (Default)

Double-click `IntelliAttendSmartBoard-5.5.0.12-Setup.exe` and follow the wizard.

**On Windows, you may need to "Unblock" the file first:**
1. Right-click the `.exe` → **Properties**
2. Check **Unblock** → **OK**
3. Then run the installer

### 4.2 Silent Install

```bat
IntelliAttendSmartBoard-5.5.0.12-Setup.exe /SILENT
```

Shows only a progress bar (no wizard).

### 4.3 Very Silent Install (Enterprise)

```bat
IntelliAttendSmartBoard-5.5.0.12-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES
```

Completely silent — no UI, no prompts, no reboot requests. Suitable for
automated/remote deployment via MDM or group policy.

> **Note:** In silent modes the app does **not** auto-launch and the desktop
> shortcut is **not** created by default. To auto-launch after silent install,
> use the auto-update agent (see §10).

---

## 5. Uninstall

### 5.1 Via UI

| Method | Steps |
|---|---|
| **Start Menu** | Start → IntelliAttend SmartBoard → Uninstall IntelliAttend SmartBoard |
| **Settings** | Settings → Apps → IntelliAttend SmartBoard → Uninstall |
| **Control Panel** | Programs and Features → IntelliAttend SmartBoard → Uninstall |

### 5.2 Via Command Line

```bat
"%LOCALAPPDATA%\IntelliAttendSmartBoard\unins000.exe" /VERYSILENT
```

### 5.3 What Gets Removed

```
{app}\*              — All application files
{app}\data\*         — App data (config, logs, cache)
{app}\               — The install directory itself
Start Menu shortcuts — Application and uninstall
Desktop shortcut     — If it was created
```

The uninstaller is **clean** — no registry keys, no orphan files (the app does
not write to `ProgramData` or `AppData\Roaming` on a per-user install).
