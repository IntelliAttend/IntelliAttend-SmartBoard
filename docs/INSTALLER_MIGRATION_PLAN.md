# Installer Migration Plan: MSI → Inno Setup

## Problem Statement

The current installer architecture uses WiX Toolset to build an MSI, then a custom C++ bootstrapper
to download and install it. This approach has caused:

1. **Zombie msiexec processes** — `CreateProcess` + `msiexec` creates orphaned SYSTEM processes
2. **Windows Installer service locks** — `MsiInstallProductW` API fails with error 2 when the
   service is blocked by zombie processes
3. **Mark-of-the-Web (Zone.Identifier)** — Downloaded MSI files get blocked by Explorer
4. **Folder-specific failures** — `msiexec` cannot open MSI files from certain directories
   (e.g., Downloads) due to Windows security policies
5. **Complexity** — Two binaries (bootstrapper + MSI) for a single installation

Industry-standard apps (WhatsApp, VS Code, Git, Node.js) use **Inno Setup** or **NSIS** to produce
a single self-contained `.exe` installer. No Windows Installer service needed.

## Decision: Switch to Inno Setup

**Why Inno Setup over NSIS:**
- Used by VS Code, GOG.com, and thousands of production apps
- Simpler scripting (Pascal-based) vs NSIS assembly-like language
- Better documentation and community support
- Produces slightly larger but more reliable installers
- Built-in support for silent installs, shortcuts, registry, uninstaller
- Single `.exe` output — no separate bootstrapper needed

**What this eliminates:**
- The entire `windows/bootstrapper/` directory (13 C++ files)
- WiX Toolset dependency
- Windows Installer service dependency
- msiexec zombie process issues
- Zone.Identifier / Mark-of-the-Web issues
- The download-at-install-time pattern (setup.exe IS the installer)

## Architecture After Migration

```
Push to school-main
  → GitHub Actions CI
    → Flutter build windows --release
    → Inno Setup compiles setup.exe (wraps Flutter build output)
    → GitHub Release created with setup.exe
    → Upload to server (for auto-update polling)
```

User experience:
```
User clicks Download button on website
  → Downloads setup.exe (~20MB)
  → Double-clicks setup.exe
  → UAC prompt → "Yes"
  → Installation happens (10-30 seconds)
  → App launches automatically
  → Desktop + Start Menu shortcuts created
  → Uninstaller registered in Add/Remove Programs
```

## Files to Create/Modify

### New Files
1. `windows/inno_setup/setup.iss` — Inno Setup script (main configuration)
2. `docs/INSTALLER_MIGRATION_PLAN.md` — This document

### Modified Files
3. `.github/workflows/auto-deploy.yml` — Replace WiX + bootstrapper steps with Inno Setup

### Files to Archive (keep but mark deprecated)
4. `windows/bootstrapper/` — Entire directory (keep for reference, remove from CI)
5. `windows/installer/product.wxs` — WiX source (keep for reference)

## Implementation Steps

### Step 1: Create Inno Setup Script (`windows/inno_setup/setup.iss`)
- Configure app metadata (name, version, publisher, URLs)
- Set installation directory to `%LOCALAPPDATA%\IntelliAttendSmartBoard`
- Include all files from Flutter build output
- Create desktop and Start Menu shortcuts
- Configure silent install support (`/SILENT`, `/VERYSILENT`)
- Auto-launch app after install
- Register uninstaller
- Set version info for the EXE

### Step 2: Update CI Pipeline (`auto-deploy.yml`)
- Remove WiX Toolset setup step
- Remove bootstrapper build step
- Add Inno Setup installation step (`choco install innosetup`)
- Add Inno Setup compilation step
- Update release files to include `setup.exe` instead of MSI + bootstrapper
- Keep server upload (change file reference from MSI to setup.exe)

### Step 3: Update Version Manifest
- `latest.json` now points to `setup.exe` instead of MSI
- SHA256 computed from `setup.exe`
- Download URL updated

### Step 4: Test
- Push to `school-main`
- Verify CI builds setup.exe
- Download from GitHub release
- Test silent install: `setup.exe /SILENT`
- Test normal install: double-click
- Verify app launches after install
- Verify uninstaller works
- Verify auto-update still works

## Inno Setup Script Design

```iss
[Setup]
AppName=IntelliAttend SmartBoard
AppVersion=5.5.0.12
DefaultDirName={localappdata}\IntelliAttendSmartBoard
DefaultGroupName=IntelliAttend SmartBoard
OutputDir=..\..\build\windows\x64\runner\Release
OutputBaseFilename=IntelliAttendSmartBoard-Setup
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\intelliattend_smartboard.exe
VersionInfoVersion=5.5.0.12
SetupIconFile=..\..\windows\runner\resources\app_icon.ico

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\IntelliAttend SmartBoard"; Filename: "{app}\intelliattend_smartboard.exe"
Name: "{group}\Uninstall IntelliAttend SmartBoard"; Filename: "{uninstallexe}"
Name: "{autodesktop}\IntelliAttend SmartBoard"; Filename: "{app}\intelliattend_smartboard.exe"

[Run]
Filename: "{app}\intelliattend_smartboard.exe"; Description: "Launch IntelliAttend SmartBoard"; Flags: nowait postinstall skipifsilent
```

## Rollback Plan

If Inno Setup causes issues:
1. Revert `.github/workflows/auto-deploy.yml` to previous version
2. Bootstrapper + MSI pipeline still works
3. Archive Inno Setup files in `windows/inno_setup/`

## Timeline

- [ ] Step 1: Create Inno Setup script (10 min)
- [ ] Step 2: Update CI pipeline (15 min)
- [ ] Step 3: Local build test (10 min)
- [ ] Step 4: Push and verify CI (15 min)
- [ ] Step 5: End-to-end test on clean machine (15 min)
