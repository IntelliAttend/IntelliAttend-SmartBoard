# Server Migration Guide: MSI → Inno Setup Installer

**Date:** 2026-07-26
**Priority:** CRITICAL — boards will fail to update without these changes
**Estimated effort:** 2-3 hours

---

## Background

The CI/CD pipeline now produces a **single Inno Setup `.exe`** instead of an MSI + bootstrapper:

| Before | After |
|--------|-------|
| `IntelliAttendSmartBoard-5.5.0.12.msi` | `IntelliAttendSmartBoard-5.5.0.12-Setup.exe` |
| Installed via `msiexec /i` | Installed via `setup.exe /SILENT` |
| Required Windows Installer service | Self-contained, no dependencies |

The GitHub Release at `v5.5.0.12` already contains the new `.exe` format. **The server currently constructs a download URL pointing to the old `.msi` filename that no longer exists.** This must be fixed immediately.

---

## Change 1 (CRITICAL): Fix download URL construction

**File:** `backend/python/main.py`
**Line:** 1401

### Current code (broken)

```python
download_url = f"https://github.com/{repo}/releases/download/v{version}/IntelliAttendSmartBoard-{version}.msi"
```

### Required change

```python
download_url = f"https://github.com/{repo}/releases/download/v{version}/IntelliAttendSmartBoard-{version}-Setup.exe"
```

### Why

When CI uploads a new release, the server stores this `download_url` in the `release_manifests` table. The heartbeat endpoint (`_build_board_config()` at line 499) sends this URL to every board. Boards then download the file from this URL.

Currently the URL points to `IntelliAttendSmartBoard-5.5.0.12.msi` — a file that does not exist in the GitHub Release. Every board trying to update will get a 404.

### Also update the docstring

**Line 1388-1389** — change:
```python
"""Accept a release manifest from CI/CD and store it in the database.

The actual MSI file is hosted on GitHub Releases; this endpoint only
records the manifest metadata so boards receive it via heartbeat.
"""
```
To:
```python
"""Accept a release manifest from CI/CD and store it in the database.

The actual installer (.exe) is hosted on GitHub Releases; this endpoint only
records the manifest metadata so boards receive it via heartbeat.
"""
```

### Verification

After deploying, trigger a CI build and check the `release_manifests` table:
```sql
SELECT version, download_url, created_at FROM release_manifests ORDER BY created_at DESC LIMIT 1;
```

The `download_url` should end with `-Setup.exe`, not `.msi`.

---

## Change 2 (IMPORTANT): Update the Flutter auto-updater download path

**File:** `lib/services/auto_updater.dart`
**Line:** 323

### Current code

```dart
final msiPath = '${InstallPaths.updateDir}\\IASB-$targetVersion.msi';
```

### Required change

```dart
final installerPath = '${InstallPaths.updateDir}\\IASB-$targetVersion-Setup.exe';
```

### Also update all references to `msiPath` in this file

The variable `msiPath` is used throughout the file. Rename it to `installerPath` and update the extension. Specifically:

- **Line 323:** `msiPath` → `installerPath`, change `.msi` to `-Setup.exe`
- **Line 324:** `final msiFile = File(msiPath);` → `final installerFile = File(installerPath);`
- **Line 327:** `if (await msiFile.exists())` → `if (await installerFile.exists())`
- **Line 328:** `await msiFile.delete();` → `await installerFile.delete();`
- **Line 338:** `_downloadWithProgress(url, msiPath, manifest.force)` → `_downloadWithProgress(url, installerPath, manifest.force)`
- **Line 350:** `if (await msiFile.exists())` → `if (await installerFile.exists())`
- **Line 351:** `await msiFile.delete();` → `await installerFile.delete();`
- **Line 367:** `await _verifyHash(msiPath, manifest.sha256!)` → `await _verifyHash(installerPath, manifest.sha256!)`
- **Line 381:** `await msiFile.delete();` → `await installerFile.delete();`
- **Line 393:** `await msiFile.delete();` → `await installerFile.delete();`
- **Line 410:** `msiPath: msiPath` → `installerPath: installerPath`

### Also update the docstring

**Line 447:** Change `/// Stream the MSI from [url]` → `/// Stream the installer from [url]`

---

## Change 3 (IMPORTANT): Update the update agent launcher

**File:** `lib/services/update_agent_launcher.dart`
**Line:** 24

### Current code

```dart
static Future<bool> launch({
  required String msiPath,
  ...
}) async {
```

### Required change

```dart
static Future<bool> launch({
  required String installerPath,
  ...
}) async {
```

### Also update the state file creation

**Line 35:** `msiPath: msiPath` → `installerPath: installerPath`

### Also update the docstrings

- **Line 12:** `handles MSI installation` → `handles installation`
- **Line 19:** `run msiexec, verify` → `run the installer, verify`

---

## Change 4 (IMPORTANT): Update the state file schema

**File:** `lib/core/state/installation_state.dart`

### Current code

- **Line 126:** `final String msiPath;`
- **Line 159:** `required this.msiPath,`
- **Line 179:** `msiPath: msiPath,`
- **Line 198:** `'msi_path': msiPath,`
- **Line 224:** `msiPath: json['msi_path'] as String? ?? '',`

### Required changes

Rename `msiPath` to `installerPath` throughout. Update the JSON key from `msi_path` to `installer_path`:

- **Line 126:** `final String installerPath;`
- **Line 159:** `required this.installerPath,`
- **Line 179:** `installerPath: installerPath,`
- **Line 198:** `'installer_path': installerPath,`
- **Line 224:** `installerPath: json['installer_path'] as String? ?? json['msi_path'] as String? ?? '',`

The fallback to `msi_path` on line 224 provides backward compatibility for any in-flight state files that still use the old key.

---

## Change 5 (REQUIRED): Update the C++ update agent

This is the most complex change. The update agent (`windows/update_agent/`) currently runs `msiexec /i` to install. It must be changed to run `setup.exe /SILENT` instead.

### 5a. Rename struct field

**File:** `windows/update_agent/common.h`
**Line:** 54

```cpp
// Current
std::wstring msiPath;

// Change to
std::wstring installerPath;
```

### 5b. Update JSON reader

**File:** `windows/update_agent/json_reader.cpp`

- **Line 133:** `s.msiPath = json.at(L"msi_path");` → `s.installerPath = json.count(L"installer_path") ? json.at(L"installer_path") : json.at(L"msi_path");`
- **Line 154:** `L"\"msi_path\":\"" + state.msiPath + L"\","` → `L"\"installer_path\":\"" + state.installerPath + L"\","`

The reader uses backward-compatible logic: it reads `installer_path` if present, falls back to `msi_path` for old state files.

### 5c. Replace RunMsiExec with RunSetupExe

**File:** `windows/update_agent/installer.cpp`

Replace the entire `RunMsiExec` function. The new function runs the Inno Setup installer with `/SILENT` flag:

```cpp
DWORD RunSetupExe(const std::wstring& setupPath, const std::wstring& logPath) {
  // Build command line:
  // setup.exe /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="<log>"
  std::wstring cmdLine = L"\"" + setupPath +
                         L"\" /SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG=\"" +
                         logPath + L"\"";

  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi = {};

  std::vector<wchar_t> cmdBuf(cmdLine.begin(), cmdLine.end());
  cmdBuf.push_back(L'\0');

  BOOL created = CreateProcessW(
    nullptr,
    cmdBuf.data(),
    nullptr, nullptr,
    FALSE,
    CREATE_NO_WINDOW,
    nullptr, nullptr,
    &si, &pi
  );

  if (!created) {
    return (DWORD)-1;
  }

  UA_LOG_INFO(L"INSTALLING", L"setup.exe started, waiting for completion...");

  // Wait for setup to finish (10 min timeout — Inno Setup can be slow on HDD).
  DWORD waitResult = WaitForSingleObject(pi.hProcess, 600000);

  DWORD exitCode = 0;
  if (waitResult == WAIT_OBJECT_0) {
    GetExitCodeProcess(pi.hProcess, &exitCode);
  } else {
    UA_LOG_ERROR(L"INSTALLING", L"setup.exe timed out after 600s, terminating...");
    TerminateProcess(pi.hProcess, 1);
    WaitForSingleObject(pi.hProcess, 5000);
    GetExitCodeProcess(pi.hProcess, &exitCode);
  }

  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  return exitCode;
}

bool IsInstallSuccess(DWORD exitCode) {
  // Inno Setup returns 0 on success.
  return exitCode == 0;
}

bool IsInstallRetryable(DWORD exitCode) {
  // Non-retryable: user cancelled (exit code 1 or 2), access denied (5).
  if (exitCode == 1 || exitCode == 2 || exitCode == 5) return false;
  return !IsInstallSuccess(exitCode);
}
```

### 5d. Update installer.h

**File:** `windows/update_agent/installer.h`

```cpp
// Current
DWORD RunMsiExec(const std::wstring& msiPath, const std::wstring& logPath);
bool IsMsiSuccess(DWORD exitCode);
bool IsMsiRetryable(DWORD exitCode);

// Change to
DWORD RunSetupExe(const std::wstring& setupPath, const std::wstring& logPath);
bool IsInstallSuccess(DWORD exitCode);
bool IsInstallRetryable(DWORD exitCode);
```

### 5e. Update all call sites in main.cpp

**File:** `windows/update_agent/main.cpp`

- **Line 119:** `if (!FileExists(state.msiPath))` → `if (!FileExists(state.installerPath))`
- **Line 120:** `L"MSI file not found"` → `L"Installer file not found"`
- **Line 125:** `uint64_t msiSize = FileSize(state.msiPath);` → `uint64_t installerSize = FileSize(state.installerPath);`
- **Line 127:** `L"MSI file too small, likely corrupt"` → `L"Installer file too small, likely corrupt"`
- **Line 133:** `if (!VerifyAuthenticode(state.msiPath))` → `if (!VerifyAuthenticode(state.installerPath))`
- **Line 134:** `L"MSI Authenticode signature invalid or unsigned"` → `L"Installer Authenticode signature invalid or unsigned"`
- **Line 135:** `InstallJournal::Record(L"authenticode_fail", false, state.msiPath);` → `InstallJournal::Record(L"authenticode_fail", false, state.installerPath);`
- **Line 136:** `EventLog::Error(L"Update MSI failed Authenticode verification");` → `EventLog::Error(L"Update installer failed Authenticode verification");`
- **Line 147:** `L"Checksum valid, MSI verified"` → `L"Checksum valid, installer verified"`
- **Line 215:** `swprintf_s(buf, L"Attempt %d/%d, msiexec /i \"%s\" /qn /norestart /log \"%s\"",` → `swprintf_s(buf, L"Attempt %d/%d, setup.exe /SILENT \"%s\" /LOG \"%s\"",`
- **Line 216:** `attempt, kMsiMaxRetries, state.msiPath.c_str(), state.logPath.c_str());` → `attempt, kMsiMaxRetries, state.installerPath.c_str(), state.logPath.c_str());`
- **Line 219:** `DWORD exitCode = RunMsiExec(state.msiPath, state.logPath);` → `DWORD exitCode = RunSetupExe(state.installerPath, state.logPath);`
- **Line 223:** `swprintf_s(exitBuf, L"msiexec exited with code %lu", exitCode);` → `swprintf_s(exitBuf, L"setup.exe exited with code %lu", exitCode);`
- **Line 226:** `if (IsMsiSuccess(exitCode))` → `if (IsInstallSuccess(exitCode))`
- **Line 229:** `EventLog::Info(L"MSI installation completed successfully");` → `EventLog::Info(L"Installation completed successfully");`
- **Line 237:** `if (attempt < kMsiMaxRetries && IsMsiRetryable(exitCode))` → `if (attempt < kMsiMaxRetries && IsInstallRetryable(exitCode))`
- **Line 252:** `EventLog::Error(L"MSI installation failed after all retries");` → `EventLog::Error(L"Installation failed after all retries");`
- **Line 266:** `// Wait for exe to appear (MSI may still be flushing).` → `// Wait for exe to appear (installer may still be flushing).`
- **Line 274:** `L"New exe not found after MSI install"` → `L"New exe not found after install"`
- **Line 329:** `UA_LOG_INFO(StateName(State::Cleanup), L"Deleting MSI and updating state");` → `UA_LOG_INFO(StateName(State::Cleanup), L"Deleting installer and updating state");`
- **Line 331:** `if (!DeleteFileSafe(state.msiPath))` → `if (!DeleteFileSafe(state.installerPath))`
- **Line 332:** `L"Failed to delete MSI (non-fatal)"` → `L"Failed to delete installer (non-fatal)"`

---

## What NOT to change

- **`release_manifests` table schema** — no migration needed. The `download_url` column is already `Text` and accepts any URL.
- **Heartbeat endpoint** (`_build_board_config` at line 485-531) — this reads `download_url` from the database. Once Change 1 stores the correct URL, the heartbeat will send it correctly. No code changes needed here.
- **Admin push endpoint** (line 1594) — this takes an explicit `download_url` from the admin. No hardcoding.
- **CI workflows** — already migrated. No changes needed.

---

## Deployment order

1. **Deploy server first** (Change 1) — this is the critical fix. Until this is deployed, all boards will try to download a non-existent `.msi` file.
2. **Deploy Flutter app** (Changes 2, 3, 4) — these can be deployed with the next app release.
3. **Deploy update agent** (Change 5) — this ships with the Flutter app update.

Changes 2-5 can be deployed together in a single app release. Change 1 must be deployed independently and immediately.

---

## Testing

### After deploying Change 1 (server)

1. Trigger a CI build by pushing to `school-main`
2. Check the database:
   ```sql
   SELECT version, download_url FROM release_manifests ORDER BY created_at DESC LIMIT 1;
   ```
3. Verify `download_url` ends with `-Setup.exe`
4. On a board device, wait for the next heartbeat and check the logs for the `download_url`

### After deploying Changes 2-5 (app + agent)

1. Push a new version to `school-main`
2. On a test board, wait for the heartbeat to deliver the update manifest
3. Verify the board downloads the `.exe` (not `.msi`)
4. Verify the update agent installs via `/SILENT`
5. Verify the app relaunches after installation

---

## File summary

| File | Change | Priority |
|------|--------|----------|
| `backend/python/main.py:1401` | `.msi` → `-Setup.exe` in download URL | CRITICAL |
| `lib/services/auto_updater.dart:323` | `.msi` → `-Setup.exe` local path | IMPORTANT |
| `lib/services/update_agent_launcher.dart:24` | `msiPath` → `installerPath` param | IMPORTANT |
| `lib/core/state/installation_state.dart` | `msiPath` → `installerPath` field | IMPORTANT |
| `windows/update_agent/common.h:54` | `msiPath` → `installerPath` field | REQUIRED |
| `windows/update_agent/json_reader.cpp:133,154` | Read/write `installer_path` | REQUIRED |
| `windows/update_agent/installer.cpp` | `RunMsiExec` → `RunSetupExe` | REQUIRED |
| `windows/update_agent/installer.h` | Update function signatures | REQUIRED |
| `windows/update_agent/main.cpp` | ~20 references to update | REQUIRED |
