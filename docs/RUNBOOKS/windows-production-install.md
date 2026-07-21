# Windows Production Install Runbook

Use this flow for SmartBoard PCs in classrooms. It keeps configuration outside
the MSI install directory, logs installer output, and handles machines with
virtual display adapters such as "Sharing Monitor".

## 1. Pre-checks

- Windows must be 64-bit.
- Update the Intel graphics driver before deployment when it is older than one
  year.
- If Windows SmartScreen appears, choose **More info** and **Run anyway** only
  after confirming the MSI came from the IntelliAttend release channel.
- If a zero-VRAM adapter such as **Sharing Monitor** appears, keep it enabled
  only if the board hardware requires it. The app now launches with GPU
  compatibility mode on these machines.

## 2. Install

Run PowerShell as the target kiosk user and execute:

```powershell
.\scripts\install_production_msi.ps1 `
  -MsiPath "$env:USERPROFILE\Downloads\intelliattend_smartboard.msi" `
  -ApiBaseUrl "https://api.intelliattend.app" `
  -FirebaseApiKey "<restricted Firebase API key>" `
  -FirebaseProjectId "intelliattend-a2564" `
  -FirebaseAppId "<Firebase app id>" `
  -FirebaseMessagingSenderId "<sender id>" `
  -SslPinFingerprint "<production TLS SHA-256 fingerprint>"
```

The script writes machine config to:

```text
%LOCALAPPDATA%\IntelliAttendSmartBoard\.env
```

The MSI installs the app to:

```text
%LOCALAPPDATA%\intelliattend_smartboard
```

## 3. Success Criteria

- MSI exit code is `0` or `3010`.
- `intelliattend_smartboard.exe` exists in the install directory.
- The app remains running for at least 60 seconds.
- `startup_trace.log` appears in the install directory.
- No `intelliattend_smartboard_native_engine_crash.flag` remains in `%TEMP%`
  after a successful launch.

## 4. Known User-Actionable Blocks

- **SmartScreen blocks launch:** user must approve **Run anyway** or IT must
  deploy signing/trust policy.
- **GPU context lost:** update Intel graphics driver, then relaunch. The app
  automatically tries high-performance GPU selection when a zero-VRAM virtual
  adapter is detected.
- **Empty SSL pin:** install is rejected. Provide the production certificate
  fingerprint.
- **MSI exit code other than `0`/`3010`:** check the log printed by the install
  script under `%TEMP%\IntelliAttendInstall`.
