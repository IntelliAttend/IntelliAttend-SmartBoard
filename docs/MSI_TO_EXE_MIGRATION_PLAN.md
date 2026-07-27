# MSI → Inno Setup (.exe) Migration Plan

**Date:** 2026-07-27
**Status:** Complete
**Priority:** CRITICAL — boards will fail to update without these changes

---

## Context

The CI/CD pipeline now produces a single Inno Setup `.exe` instead of an MSI + bootstrapper.
The server code is already updated. This plan covers the SmartBoard (Dart + C++) and Admin Panel (React/TypeScript) changes.

---

## TODO List

### Admin Panel

- [x] Fix `SmartBoardDownload.tsx` — change `.msi` asset finder to `.exe`, update labels/instructions
- [x] Fix `UpdateManagement.tsx` — change `.msi` accept to `.exe`, update version parsing and labels

### SmartBoard — Dart

- [x] Fix `auto_updater.dart` — rename `msiPath` → `installerPath`, `.msi` → `-Setup.exe`
- [x] Fix `update_agent_launcher.dart` — rename parameter `msiPath` → `installerPath`
- [x] Fix `installation_state.dart` — rename field `msiPath` → `installerPath`, JSON key with backward compat

### SmartBoard — C++ Update Agent

- [x] Fix `common.h` — rename `msiPath` → `installerPath`, update constants
- [x] Fix `installer.cpp` — replace `RunMsiExec` with `RunSetupExe` (`setup.exe /SILENT`)
- [x] Fix `installer.h` — update function signatures
- [x] Fix `main.cpp` — update ~20 MSI references
- [x] Fix `json_reader.cpp` — read `installer_path` with fallback to `msi_path`

### Verification

- [x] Run `npm run lint` on Admin Panel — 0 errors (29 pre-existing warnings)
- [x] Run `dart analyze` on SmartBoard — 15 pre-existing errors (missing Flutter SDK 3.44.0), no new errors introduced

---

## File-by-File Changes

### 1. Admin Panel: `SmartBoardDownload.tsx`

| Line | Current | New |
|------|---------|-----|
| 79 | `a.name.endsWith('.msi')` | `a.name.endsWith('.exe')` |
| 79 | `msiAsset` | `installerAsset` |
| 162, 176, 181, 185 | `msiAsset` | `installerAsset` |
| 189 | `"Windows Installer (.msi)"` | `"Windows Installer (.exe)"` |
| 218, 227 | `.msi` filter | `.exe` filter |
| 274 | `.msi` in instructions | `.exe` |
| 280 | `.msi` in instructions | `.exe` |

### 2. Admin Panel: `UpdateManagement.tsx`

| Line | Current | New |
|------|---------|-----|
| 66 | `.replace('.msi', '')` | `.replace('.exe', '').replace('-Setup', '')` |
| 137 | `"MSI file"` | `"installer file (.exe)"` |
| 146 | `"Select MSI File"` | `"Select Installer"` |
| 147 | `accept=".msi"` | `accept=".exe"` |

### 3. SmartBoard: `auto_updater.dart`

| Line | Current | New |
|------|---------|-----|
| 286 | `final msiPath = '...\\IASB-$targetVersion.msi'` | `final installerPath = '...\\IASB-$targetVersion-Setup.exe'` |
| 287 | `final msiFile = File(msiPath)` | `final installerFile = File(installerPath)` |
| 290-291, 313-314, 344, 356, 381, 393 | `msiFile` | `installerFile` |
| 301, 330, 338, 367 | `msiPath` | `installerPath` |
| 410 | `msiPath: msiPath` | `installerPath: installerPath` |
| 447 | `"Stream the MSI"` | `"Stream the installer"` |

### 4. SmartBoard: `update_agent_launcher.dart`

| Line | Current | New |
|------|---------|-----|
| 12 | `"handles MSI installation"` | `"handles installation"` |
| 19 | `"run msiexec, verify"` | `"run the installer, verify"` |
| 24 | `required String msiPath` | `required String installerPath` |
| 35 | `msiPath: msiPath` | `installerPath: installerPath` |

### 5. SmartBoard: `installation_state.dart`

| Line | Current | New |
|------|---------|-----|
| 125 | `"Absolute path to the downloaded MSI"` | `"Absolute path to the downloaded installer"` |
| 126 | `final String msiPath` | `final String installerPath` |
| 131 | `"SHA-256 hex digest of the MSI"` | `"SHA-256 hex digest of the installer"` |
| 159 | `required this.msiPath` | `required this.installerPath` |
| 179 | `msiPath: msiPath` | `installerPath: msiPath` |
| 198 | `'msi_path': msiPath` | `'installer_path': installerPath` |
| 224 | `msiPath: json['msi_path'] as String? ?? ''` | `installerPath: json['installer_path'] as String? ?? json['msi_path'] as String? ?? ''` |

### 6. SmartBoard C++: `common.h`

| Line | Current | New |
|------|---------|-----|
| 14 | `kMsiExecTimeoutMs = 300000` | `kSetupExecTimeoutMs = 600000` |
| 21 | `kMsiMaxRetries = 3` | `kInstallMaxRetries = 3` |
| 22 | `kMsiRetryDelays` | `kInstallRetryDelays` |
| 24-26 | `kMsiSuccess`, `kMsiRebootRequired` | `kInstallSuccess = 0` |
| 32 | `MsiInstallFail = 2` | `InstallFail = 2` |
| 54 | `std::wstring msiPath` | `std::wstring installerPath` |

### 7. SmartBoard C++: `installer.cpp`

Replace `RunMsiExec` with `RunSetupExe`:
- Command: `setup.exe /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="<log>"`
- Timeout: 600s (10 min)
- `IsInstallSuccess`: exit code 0
- `IsInstallRetryable`: non-retryable = 1, 2, 5

### 8. SmartBoard C++: `installer.h`

Update signatures:
- `RunSetupExe(setupPath, logPath)` 
- `IsInstallSuccess(exitCode)`
- `IsInstallRetryable(exitCode)`

### 9. SmartBoard C++: `main.cpp`

Update all `msiPath` → `installerPath`, `RunMsiExec` → `RunSetupExe`, `IsMsiSuccess` → `IsInstallSuccess`, `IsMsiRetryable` → `IsInstallRetryable`, and all MSI log messages.

### 10. SmartBoard C++: `json_reader.cpp`

- Required field: `L"msi_path"` → `L"installer_path"`
- Parse: read `installer_path` with fallback to `msi_path`
- Write: output `installer_path`

---

## Deployment Order

1. Server (already done)
2. Admin Panel (Cloudflare Pages)
3. SmartBoard (ships with next Flutter Windows build)
