# Phase 2 — Stateless MSI Installer Specification

**Document version:** 1.0
**Date:** July 22, 2026
**Status:** Implementation in progress

---

## 1. Installer Contract

The MSI guarantees the following. Every design decision satisfies these constraints.

### Guarantees

| # | Guarantee | Meaning |
|---|-----------|---------|
| G-1 | **Atomic file operations** | Files are installed in a single transaction. If MSI fails midway, the machine reverts to its previous state. |
| G-2 | **No user data modification** | The installer never reads, writes, or deletes files in `Data\` or `Config\`. These directories are created only if absent. |
| G-3 | **No network access** | The MSI contains zero custom actions that contact any network endpoint. |
| G-4 | **Upgrade any supported version** | Any v5.5.0+ installation can be upgraded in-place by running the new MSI. |
| G-5 | **Clean uninstall** | Uninstall removes binaries and shortcuts. Preserves `Data\`, `Config\`, `Backup\`, `Logs\`. |
| G-6 | **Interactive and silent** | Works with `/passive`, `/qn`, and `/qr`. No dialogs block silent installs. |
| G-7 | **Interruption safe** | Power loss, reboot, or process kill during install leaves machine bootable. MSI rolls back automatically. |

### Explicit Anti-Guarantees

The installer explicitly does **not**:

- Make network calls
- Perform registration or activation
- Download configuration files
- Launch the application (except as a convenience in interactive mode)
- Modify user data
- Install runtime dependencies (Visual C++ Redistributable, etc.)
- Set environment variables
- Require administrator privileges

---

## 2. Current Problems in `product.wxs`

| # | Problem | Impact |
|---|---------|--------|
| 1 | `TargetName` not set | WiX defaults to `Product.Id` which is `*` — builds produce randomly-named MSIs |
| 2 | No `Platform` variable | Build must manually pass `-arch x64` to candle; no self-documentation |
| 3 | No `Languages` for per-user install | WiX 3.x per-user MSI with `Language="1033"` is correct but no `Languages` attribute for future i18n |
| 4 | `Version` variable not bounded | Build can pass any version string; no validation |
| 5 | EULA dialog uses custom `RadioButtonGroup` | Non-standard; breaks `WixUI_Minimal` contract |
| 6 | `C_RemoveFolder` uses registry key for component detection | Fragile; WiX file-keypath components are more reliable |
| 7 | No `Publish` element for `ReinstallMode` | MajorUpgrade defaults are fine but explicit is better |
| 8 | `CustomAction` launches app unconditionally | Should respect a property for silent installs |
| 9 | No `ARPNOREPAIR` or `ARPNOMODIFY` | Users see Repair/Modify buttons that do nothing useful |
| 10 | `InstallPrivileges="limited"` + `perUser` | Correct but no comment explaining why |

---

## 3. Design Decisions

### 3.1 Install Directory

```
%LOCALAPPDATA%\IntelliAttendSmartBoard\
├── App\                    ← MSI-managed (replaced on upgrade, removed on uninstall)
│   ├── intelliattend_smartboard.exe
│   ├── update_agent.exe
│   ├── flutter_windows.dll
│   └── ... (all binaries)
├── Data\                   ← App-managed (never touched by MSI)
├── Config\                 ← App-managed (never touched by MSI)
├── Cache\                  ← App-managed (never touched by MSI)
├── Updates\                ← App-managed (never touched by MSI)
├── Logs\                   ← App-managed (never touched by MSI)
└── Backup\                 ← App-managed (never touched by MSI)
```

**Key insight:** MSI only owns `App\`. Everything else is the app's responsibility.

### 3.2 Component Strategy

Each DLL gets its own component with a stable GUID. This allows:
- Individual file replacement on upgrade
- Clean rollback on failure
- Proper ref counting

### 3.3 MajorUpgrade Strategy

```xml
<MajorUpgrade
    Schedule="afterInstallInitialize"
    AllowSameVersionUpgrades="yes"
    DowngradeErrorMessage="A newer version is already installed."
    AllowDowngrades="no"
    IgnoreRemoveFailure="yes" />
```

- `Schedule="afterInstallInitialize"`: Old version removed first, then new version installed. No file conflicts.
- `AllowSameVersionUpgrades="yes"`: Allows repair/reinstall of same version.
- `IgnoreRemoveFailure="yes"`: If uninstall of old version fails, continue anyway.

### 3.4 ARP (Add/Remove Programs) Metadata

```xml
<Property Id="ARPNOREPAIR" Value="yes" Secure="yes" />
<Property Id="ARPNOMODIFY" Value="yes" Secure="yes" />
<Property Id="ARPHELPLINK" Value="https://intelliattend.app/support" />
<Property Id="ARPURLINFOABOUT" Value="https://intelliattend.app" />
<Property Id="ARPINSTALLLOCATION" Value="[APPLICATIONFOLDER]" />
```

### 3.5 Custom EULA Dialog

Keep the existing custom dialog but simplify:
- Remove `RadioButtonGroup` workaround
- Use standard `LicenseAcceptedCheckBox` control
- Wire to `WixUI_Minimal` properly

### 3.6 Post-Install Launch

Only in interactive mode. Controlled by `WIXUI_EXITDIALOGOPTIONALCHECKBOX`:

```xml
<Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT" Value="Launch IntelliAttend SmartBoard" />
<Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOX" Value="1" Secure="yes" />
```

### 3.7 Uninstall Cleanup

```xml
<RemoveFolder Id="RemoveAppFolder" On="uninstall" />
<RemoveFolder Id="RemoveIntelliAttendFolder" On="uninstall" Directory="IntelliAttendFolder" />
```

Remove `App\` on uninstall. Preserve `Data\`, `Config\`, etc.

---

## 4. WiX Variables

The build must pass these variables to `candle.exe`:

```
candle.exe -dSourceDir=<build_output> -dAppName=IntelliAttendSmartBoard -dVersion=<version> -dPlatform=x64 -arch x64 product.wxs
```

| Variable | Example | Source |
|----------|---------|--------|
| `SourceDir` | `build\windows\x64\runner\Release` | Flutter build output |
| `AppName` | `IntelliAttendSmartBoard` | Fixed |
| `Version` | `5.6.0` | From `pubspec.yaml` |
| `Platform` | `x64` | Fixed (arm64 future) |

---

## 5. Custom Actions

### 5.1 LaunchApplication (Interactive Only)

```xml
<CustomAction Id="LaunchApplication"
              FileKey="F_exe"
              ExeCommand=""
              Return="asyncNoWait"
              Impersonate="yes" />
```

Only fires when `WIXUI_EXITDIALOGOPTIONALCHECKBOX` is checked. In silent installs, no checkbox is shown.

### 5.2 CreateAppSubdirectories

```xml
<CustomAction Id="CreateAppSubdirectories"
              Directory="DataDir"
              ExeCommand="mkdir &quot;[DataDir]Data&quot; &amp; mkdir &quot;[DataDir]Config&quot; &amp; mkdir &quot;[DataDir]Cache&quot; &amp; mkdir &quot;[DataDir]Updates&quot; &amp; mkdir &quot;[DataDir]Logs&quot; &amp; mkdir &quot;[DataDir]Backup&quot;"
              Return="check"
              Impersonate="yes" />
```

This is acceptable because it only creates empty directories. No network, no logic.

---

## 6. Testing Matrix

| Scenario | Method |
|----------|--------|
| Clean install | Fresh Windows VM, run MSI |
| Upgrade | Install v1, then v2 over it |
| Downgrade | Install v2, then v1 — should fail |
| Silent install | `msiexec /i IASB.msi /qn /norestart` |
| Silent uninstall | `msiexec /x IASB.msi /qn` |
| Repair | `msiexec /f IASB.msi` |
| Interrupted install | Kill msiexec mid-install, verify rollback |
| Uninstall preserves data | Uninstall, check Data\ and Config\ exist |
| Upgrade preserves data | Upgrade, check Data\ and Config\ exist |

---

## 7. Files Modified

| File | Action |
|------|--------|
| `windows/installer/product.wxs` | Rewrite — clean structure, proper ARP, stable GUIDs |
| `windows/installer/build.bat` | New — standard candle+light build script |
| `scripts/install_production_msi.ps1` | Update — no longer needs to create App\ subdirectory (MSI does it) |
| `docs/phase2_installer_spec.md` | This spec |
