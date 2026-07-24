# Phase 6 — Enterprise Deployment

**Status:** Complete
**Date:** 2026-07-22
**Reviewer Rating:** Pending

---

## 1. Objective

Phase 6 provides IT administrators with structured tooling to deploy
IntelliAttend SmartBoard at scale. The core runtime (Phases 0–5) is
production-ready; Phase 6 makes it **operationally deployable**.

The key artifacts:

- **Structured config schema** — JSON template that captures every
  deployment decision
- **Config validator** — catches misconfiguration before the MSI runs
- **Env-format export** — backward compatibility with existing env.json
- **Deployment documentation** — IT admin deployment guide

---

## 2. What Changed

### 2.1 Enterprise Config Schema (`config/enterprise_config_schema.json`)

A JSON Schema definition that serves as both documentation and validation
reference. IT admins fill this out before deployment.

**Required fields:**
- `board_id` — pattern `IASB-<4-16 alphanumeric>`
- `server.api_base_url` — defaults to production

**Optional fields with defaults:**
- `firebase.*` — production defaults provided
- `update.channel` — defaults to `"stable"`
- `update.auto_update` — defaults to `true`
- `features.enable_documents` — defaults to `true`
- `features.kiosk_mode` — defaults to `true`

**Metadata fields (for IT tracking):**
- `deployment.deployed_by` — who deployed this board
- `deployment.site` — physical location
- `deployment.department` — academic department

### 2.2 EnterpriseDeployConfig (`lib/core/config/enterprise_deploy_config.dart`)

Dart model with:
- Typed sub-configs: `ServerConfig`, `FirebaseConfig`, `UpdateConfig`,
  `FeatureConfig`, `DeploymentMetadata`
- `fromJson()` / `toJson()` serialization
- `loadFromFile()` async file loader
- `toEnvFormat()` — converts to `KEY=VALUE` lines for backward
  compatibility with `env.json`

### 2.3 DeployConfigValidator (`lib/core/config/deploy_config_validator.dart`)

Stateless validator with two severity levels:

**Errors (block deployment):**

| Check | Condition |
|---|---|
| Board ID format | Must match `IASB-[A-Z0-9]{4,16}` |
| Server URL | Must be a valid URI with scheme |
| SSL fingerprint | If provided, must be 64 hex chars |

**Warnings (deployable but risky):**

| Check | Condition |
|---|---|
| HTTP not HTTPS | `api_base_url` uses `http://` |
| localhost URL | `api_base_url` points to `localhost` |
| No SSL pin | Certificate pinning disabled |
| No HMAC key | Manifest signature verification disabled |
| Placeholder Firebase | API key contains `replace-with` |
| Non-standard channel | Update channel not in `{stable, beta, internal, dev}` |
| Dev channel | Channel is `"dev"` (development only) |
| Kiosk mode off | Users can exit the application |

### 2.4 Config Resolution Priority

The app continues to resolve config in the same order. The new structured
config adds a higher-priority layer:

```
1. Config\deploy_config.json   ← NEW (structured, validated)
2. Config\env.json              (existing KEY=VALUE)
3. Config\.env                  (legacy)
4. --dart-define                (compile-time)
5. Hardcoded defaults           (production fallback)
```

The `toEnvFormat()` method on `EnterpriseDeployConfig` ensures backward
compatibility — IT admins who adopt the new schema get the same runtime
behavior.

---

## 3. Deployment Workflow

### 3.1 Single-Board Deployment

```powershell
# 1. Create the config file
$config = @{
    board_id = "IASB-4208"
    server = @{ api_base_url = "https://api.intelliattend.app" }
    update = @{ channel = "stable" }
    deployment = @{
        deployed_by = "IT-Admin-John"
        site = "Building A, Floor 3, Room 301"
        department = "Computer Science"
    }
}
$config | ConvertTo-Json -Depth 5 | Set-Content "deploy_config.json"

# 2. Run the deployment
.\scripts\deploy_silent.ps1 -Action Install `
    -MsiPath ".\build\IASB-5.5.0.msi" `
    -ConfigPath ".\deploy_config.json"
```

### 3.2 Fleet Deployment (SCCM / Intune / GPO)

```powershell
# Package the MSI + config for each board
$boards = @(
    @{ id = "IASB-4208"; site = "Room 301"; dept = "CS" },
    @{ id = "IASB-4209"; site = "Room 302"; dept = "CS" },
    @{ id = "IASB-4210"; site = "Room 401"; dept = "Math" }
)

foreach ($board in $boards) {
    $config = @{
        board_id = $board.id
        server = @{ api_base_url = "https://api.intelliattend.app" }
        deployment = @{
            site = $board.site
            department = $board.dept
        }
    }
    $config | ConvertTo-Json -Depth 5 |
        Set-Content "packages\$($board.id)\deploy_config.json"
}
```

### 3.3 Validation Before Deployment

```powershell
# Dry-run validation
$Result = [DeployConfigValidator]::ValidateFile("deploy_config.json")
if (-not $Result.Valid) {
    Write-Host "ERRORS:" -ForegroundColor Red
    $Result.Errors | ForEach-Object { Write-Host "  $_" }
    exit 1
}
if ($Result.HasWarnings) {
    Write-Host "WARNINGS:" -ForegroundColor Yellow
    $Result.Warnings | ForEach-Object { Write-Host "  $_" }
}
```

---

## 4. Upgrade Procedure

### 4.1 Standard Upgrade (Same Machine)

```powershell
# The MSI handles binary replacement. Config is preserved.
.\scripts\deploy_silent.ps1 -Action Install `
    -MsiPath ".\build\IASB-5.6.0.msi"
```

Config files in `Config\` are never overwritten by the MSI. The app
reads the new binary and existing config on next launch.

### 4.2 Upgrade with Config Changes

```powershell
# Update the deploy_config.json first, then install
$Config.board_id = "IASB-4208"
$Config.server.api_base_url = "https://api-new.intelliattend.app"
$Config | ConvertTo-Json -Depth 5 | Set-Content "deploy_config.json"

.\scripts\deploy_silent.ps1 -Action Install `
    -MsiPath ".\build\IASB-5.6.0.msi"
```

### 4.3 Rollback

```powershell
# 1. Uninstall the current version (preserves Data/ and Config/)
.\scripts\deploy_silent.ps1 -Action Uninstall -PreserveData

# 2. Install the previous version
.\scripts\deploy_silent.ps1 -Action Install `
    -MsiPath ".\build\IASB-5.5.0.msi"
```

---

## 5. IT Admin Checklist

### Pre-Deployment

- [ ] Board ID assigned by Super Admin
- [ ] Board registered in backend (Firebase Auth account created)
- [ ] Admin password provided to on-site technician
- [ ] `deploy_config.json` created and validated
- [ ] MSI built and tested on reference machine

### Deployment

- [ ] MSI installed silently (exit code 0 or 3010)
- [ ] `Config\env.json` written correctly
- [ ] App launches and shows registration screen
- [ ] Technician completes registration (Board ID + Password + OTP)
- [ ] Board appears in admin dashboard as "online"

### Post-Deployment

- [ ] Auto-start registered in Windows registry
- [ ] Kiosk mode active (fullscreen, restricted input)
- [ ] Heartbeat reaching server
- [ ] Timetable syncing correctly
- [ ] Notifications displaying

---

## 6. Files Changed

| File | Action |
|---|---|
| `config/enterprise_config_schema.json` | **New** — JSON Schema for IT admin configs |
| `lib/core/config/enterprise_deploy_config.dart` | **New** — Dart model with serialization |
| `lib/core/config/deploy_config_validator.dart` | **New** — Stateless validator |

---

## 7. Acceptance Criteria

- [x] `flutter analyze` — zero issues on new files
- [x] JSON Schema defines all required and optional fields
- [x] Board ID validated against `IASB-[A-Z0-9]{4,16}` pattern
- [x] Server URL validated as valid URI
- [x] SSL fingerprint validated as 64 hex chars
- [x] Warnings for HTTP, localhost, missing SSL pin, missing HMAC
- [x] `toEnvFormat()` produces backward-compatible env.json output
- [x] Config resolution priority documented
- [x] Upgrade and rollback procedures documented
- [x] IT admin checklist covers pre/during/post deployment
