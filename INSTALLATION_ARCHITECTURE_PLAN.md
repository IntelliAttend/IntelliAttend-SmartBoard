# Production-Grade Installation Architecture — Implementation Plan

**Date:** July 22, 2026  
**Reviewed by:** Senior Windows Platform Engineer  
**Current State:** v5.5.0+11 — MSI installer + in-app auto-updater  
**Target State:** Enterprise-grade distribution system comparable to Chrome, VS Code, Slack

---

## Guiding Principles

Before any code changes, these five principles govern every decision:

1. **The installer only installs** — never performs application logic or configuration.
2. **The application never updates itself directly** — a detached update agent owns the entire update process.
3. **Every operation is recoverable** — updates, startup, and rollback should all be resumable after interruption.
4. **Every failure is diagnosable** — clear state machines, structured logs, and diagnostic exports.
5. **The user is never left with a broken application** — either the update succeeds completely, or the previous version continues working.

---

## Implementation Phases

```
Phase 0  Path Normalization & State Machine Foundation        ✅ Complete
Phase 1  Detached Update Agent                                ✅ Complete
Phase 2  Stateless Installer (WiX MSI)                        ✅ Complete
Phase 3  Application Startup Lifecycle                        ✅ Complete
Phase 4  Update Manifest & Validation                         ✅ Complete
Phase 5  Recovery Mode & Self-Repair                          ✅ Complete
Phase 6  Enterprise Deployment                                ✅ Complete
Phase 7  Cloud Observability & Diagnostics                    ✅ Complete
Phase 8  Production Certification                             ✅ Framework complete (awaiting execution)
Phase 9  Security Audit                                       ✅ Complete
Phase 10 Performance Validation                               ✅ Complete
Phase 11 Operational Readiness                                ✅ Complete
```

**Architecture Freeze:** Declared after Phase 6 — only bug fixes, security fixes, performance improvements, certification-driven changes accepted.

---

## Phase 0 — Path Normalization & State Machine Foundation

**Goal:** Establish the canonical directory layout (keeping the existing root for compatibility) and define the universal state machines used by every subsequent phase.

### Why compatibility matters

The install path `%LOCALAPPDATA%\IntelliAttendSmartBoard\` is already deployed to real classrooms. Renaming it would break:
- Existing shortcuts and auto-start registry entries
- Support scripts and documentation
- Backup/restore procedures
- User muscle memory

Instead, we keep the root and separate concerns **within** it.

### Directory Layout

```
%LOCALAPPDATA%\IntelliAttendSmartBoard\
│
├── App\                          # Binaries only (MSI owns this)
│   ├── intelliattend_smartboard.exe
│   ├── flutter_windows.dll
│   ├── isar.dll
│   ├── update_agent.exe          # Detached updater (Phase 1)
│   └── data\
│       ├── app.so
│       ├── icudtl.dat
│       └── flutter_assets\
│
├── Data\                         # Application state (app owns this)
│   ├── registration.json
│   ├── update_health.json
│   ├── update_state.json         # Agent ↔ App contract
│   └── isar\                     # Database files
│
├── Config\                       # Configuration
│   ├── env.json                  # Production config (written by IT)
│   └── config.json               # App configuration
│
├── Cache\                        # Temporary cached data
│
├── Updates\                      # Downloaded MSI files
│   └── IASB-{version}.msi
│
├── Logs\                         # Structured logs
│   ├── install.log
│   ├── update.log
│   ├── rollback.log
│   ├── startup.log
│   ├── network.log
│   └── crash.log
│
└── Backup\                       # Rollback backups
    └── v{version}\               # Previous version backup
```

### New file: `lib/core/config/install_paths.dart`

```dart
/// Single source of truth for all installation paths.
/// 
/// The root directory remains %LOCALAPPDATA%\IntelliAttendSmartBoard
/// for backward compatibility with existing deployments.
/// Internal separation is new.
class InstallPaths {
  InstallPaths._();
  
  static final String _localAppData = 
      Platform.environment['LOCALAPPDATA'] ??
      '${Platform.environment['USERPROFILE']}\\AppData\\Local';
  
  /// Root: %LOCALAPPDATA%\IntelliAttendSmartBoard
  static String get root => '$_localAppData\\IntelliAttendSmartBoard';
  
  /// Binaries (MSI-managed)
  static String get appDir => '$root\\App';
  static String get exePath => '$appDir\\intelliattend_smartboard.exe';
  static String get updateAgentPath => '$appDir\\update_agent.exe';
  
  /// Application state (app-managed)
  static String get dataDir => '$root\\Data';
  static String get configDir => '$root\\Config';
  static String get cacheDir => '$root\\Cache';
  static String get updateDir => '$root\\Updates';
  static String get logDir => '$root\\Logs';
  static String get backupDir => '$root\\Backup';
  
  /// Specific files
  static String get lockFile => '$root\\Data\\app.lock';
  static String get updateHealthFile => '$root\\Data\\update_health.json';
  static String get updateStateFile => '$root\\Data\\update_state.json';
  static String get registrationFile => '$root\\Data\\registration.json';
  static String get envFile => '$root\\Config\\env.json';
  static String get configFile => '$root\\Config\\config.json';
  
  /// Temp directory (outside app root)
  static String get tempDir => '${Directory.systemTemp.path}\\IntelliAttend';
  
  /// Ensure all directories exist
  static Future<void> ensureDirectories() async {
    for (final dir in [dataDir, configDir, cacheDir, updateDir, logDir, backupDir]) {
      await Directory(dir).create(recursive: true);
    }
  }
}
```

### New file: `lib/core/state/installation_state.dart`

```dart
/// Tracks the lifecycle of the installation on this machine.
/// Persisted to Data/installation_state.json.
enum InstallationState {
  fresh,        // MSI just completed, first launch
  installed,    // Files copied, not yet configured
  registered,   // Board registered with server
  configured,   // Config loaded, .env validated
  operational,  // Fully working
  updating,     // Update in progress
  healthy,      // Update completed, 3+ successful starts
  recovery,     // Something went wrong, in recovery mode
}

/// Tracks the lifecycle of an update operation.
/// Persisted to Data/update_state.json (read by update agent).
enum UpdateState {
  idle,              // No update in progress
  downloading,       // MSI being downloaded
  downloaded,        // MSI downloaded, awaiting verification
  verified,          // SHA-256 + signature verified
  waitingExit,       // Agent waiting for app to exit
  installing,        // msiexec running
  installed,         // msiexec completed successfully
  restarting,        // Agent launching new version
  failed,            // Update failed at some stage
  rollback,          // Rolling back to previous version
}

class UpdateStateFile {
  final String msiPath;
  final String targetVersion;
  final String expectedSha256;
  final int appPid;
  final String appExePath;
  final String logPath;
  final UpdateState state;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int attempt;
  
  // Serialization to/from JSON for agent communication
}
```

### New file: `lib/core/state/state_persister.dart`

```dart
/// Persists installation and update state to disk.
/// Survives crashes, power loss, and reboots.
class StatePersister {
  static Future<void> saveInstallationState(InstallationState state, {String? detail});
  static Future<InstallationState> loadInstallationState();
  static Future<void> saveUpdateState(UpdateStateFile state);
  static Future<UpdateStateFile?> loadUpdateState();
  static Future<void> clearUpdateState();
}
```

### Effort
**1–2 days** — Path constants, state enums, persistence layer.

### Verification
- All path references in codebase go through `InstallPaths`
- State persists across process restarts
- State file is valid JSON readable by both Dart and C++ agent

---

## Phase 1 — Detached Update Agent

**Goal:** Build a standalone 100–200 KB C++ executable that handles MSI installation after the app exits.

**Why this is the highest-impact change:** It eliminates file-in-use conflicts, removes hardcoded sleeps, and makes the update process deterministic — exactly how Chrome, VS Code, Slack, and Discord work.

### Architecture

```
┌──────────────────────────────┐
│  IntelliAttend SmartBoard    │
│  (Flutter app)               │
│                              │
│  1. Detect update            │
│  2. Download MSI             │
│  3. Verify SHA-256           │
│  4. Verify Authenticode      │
│  5. Write update_state.json  │
│  6. Launch update_agent.exe  │
│  7. Exit                     │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  update_agent.exe            │
│  (Native C++, ~150KB)       │
│                              │
│  State Machine:              │
│  IDLE → WAITING → INSTALLING│
│  → VERIFYING → RESTARTING   │
│  → CLEANUP → DONE           │
│                              │
│  1. Read update_state.json   │
│  2. Wait for app PID exit    │
│  3. Run msiexec /i /qn      │
│  4. Verify exe exists        │
│  5. Verify version           │
│  6. Launch app               │
│  7. Cleanup temp files       │
│  8. Write completion state   │
│  9. Exit                     │
└──────────────────────────────┘
```

### New files

#### `windows/update_agent/` (new directory)

```
windows/update_agent/
├── CMakeLists.txt           # Standalone build, no Flutter dependency
├── main.cpp                 # Entry point + state machine
├── process_watcher.cpp      # WaitForSingleObject on app PID
├── installer.cpp            # CreateProcess msiexec with args
├── version_checker.cpp      # GetFileVersionInfoW to verify version
├── launcher.cpp             # CreateProcess to relaunch app
├── logger.cpp               # Structured writes to update.log
├── json_reader.cpp          # Minimal JSON parser (no external deps)
├── file_utils.cpp           # File existence, size, hash checks
└── resources/
    ├── update_agent.ico
    └── version_info.rc
```

**Build requirements:**
- CMake 3.14+
- MSVC (comes with Visual Studio)
- No external libraries (Win32 API only)
- Target: x64, Release, ~150 KB

#### `lib/models/update_state.dart` (new)
#### `lib/services/update_agent_launcher.dart` (new)

### Update Agent State Machine

```
IDLE
  │ Read update_state.json
  │ Validate fields exist
  ▼
WAITING_APP_EXIT
  │ OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, appPid)
  │ WaitForSingleObject(hProcess, 30000)  // 30s timeout
  │ If timeout → try TerminateProcess (graceful → force)
  │ If process already gone → proceed
  ▼
INSTALLING
  │ CreateProcess("msiexec.exe", 
  │   "/i \"...\" /qn /norestart /log \"...\"")
  │ WaitForSingleObject(hMsiExec, 300000)  // 5min timeout
  │ Check exit code: 0 or 3010 = success
  │ If failure → retry up to 3 times with 5s delay
  ▼
VERIFYING
  │ FileExistsW(appExePath)
  │ GetFileVersionInfoW → extract version string
  │ Compare with targetVersion
  │ If mismatch → write error, exit(3)
  ▼
RESTARTING
  │ CreateProcess(appExePath, "--intelliattend-autostart")
  │ WaitForSingleObject(hNewProcess, 5000)  // Confirm it started
  │ If failed → write error, exit(4)
  ▼
CLEANUP
  │ DeleteFileW(msiPath)
  │ DeleteFileW(update_state.json)  // Or mark completed
  │ Delete old rollback dirs (>24h)
  ▼
DONE
  │ Write completion to update_state.json
  │ Exit(0)
```

### Error Recovery

Every state is recoverable. The agent writes its current state to `update_state.json` before each transition. If the agent crashes mid-operation:

```
Agent crash during INSTALLING
  → msiexec may be partially complete
  → On next app launch, read update_state.json
  → Detect state = "installing" with no completion
  → Option A: Retry by re-running msiexec (MSI is idempotent)
  → Option B: Rollback to backup
```

Exit codes:
```
0  = Success
1  = App exit timeout
2  = MSI install failed (all retries exhausted)
3  = Post-install verification failed (exe missing or wrong version)
4  = App restart failed
5  = Invalid state file
```

### Modified files

#### `lib/services/auto_updater.dart`

**Remove entirely:**
- `_installMsi()` method
- `_exitApp()` method
- All batch file / restart helper logic
- All `Process.run('msiexec', ...)` calls
- All hardcoded sleeps

**Replace with:**
```dart
// In _startUpdatePipeline, after hash verification:
await UpdateAgentLauncher.launch(UpdateStateFile(
  msiPath: msiPath,
  targetVersion: manifest.minimumVersion,
  expectedSha256: manifest.sha256!,
  appPid: pid,
  appExePath: InstallPaths.exePath,
  logPath: '${InstallPaths.logDir}\\update.log',
  state: UpdateState.verified,
  attempt: 1,
));
exit(0); // App exits cleanly, agent takes over
```

**Add to startup:**
```dart
// Check if agent left a partially completed update
final updateState = await StatePersister.loadUpdateState();
if (updateState != null && updateState.state == UpdateState.installing) {
  // Agent was installing when it crashed. MSI is idempotent — retry.
  await _retryFromLastState(updateState);
}
```

#### `lib/services/update_health_monitor.dart`

**Remove:**
- `_writeRollbackScript()` — PowerShell rollback is replaced by agent-native rollback
- `_performRollback()` on Windows — agent handles this

**Keep:**
- Health tracking logic (3-startup stabilization)
- Server reporting
- Backup creation (agent triggers this before install)

### Effort
**5–7 days** — New C++ project with state machine, process management, version verification, integration with Flutter side.

### Dependencies
- Phase 0 (paths and state definitions)

### Verification
- Manual test: run app → trigger update → verify agent installs and relaunches
- Test: kill app during update → verify agent handles gracefully
- Test: corrupt MSI → verify agent reports failure and app retries
- Test: kill agent during install → verify app detects and retries on next launch
- Test: verify no hardcoded sleeps anywhere in the update flow

---

## Phase 2 — Stateless Installer (WiX MSI)

**Goal:** Installer copies binaries only. No config, no API calls, no network. Clean uninstall preserves user data by default.

**Key principle:** The installer is stateless. It does not configure the application. The application configures itself on first launch.

### Changes

#### Modify: `windows/installer/product.wxs`

**Keep existing root path** (`%LOCALAPPDATA%\IntelliAttendSmartBoard`) for compatibility.

**Separate binaries into App subdirectory:**

```xml
<Directory Id="TARGETDIR" Name="SourceDir">
  <Directory Id="LocalAppDataFolder">
    <Directory Id="APPDATA_ROOT" Name="IntelliAttendSmartBoard">
      <Directory Id="INSTALLFOLDER" Name="App">
        <!-- Binaries only — MSI manages these -->
      </Directory>
    </Directory>
  </Directory>
</Directory>
```

**Remove all config-writing custom actions:**

Delete or disable:
- `LaunchApplication` custom action (app is launched by agent or user, not installer)
- Any custom actions that write `.env` or config files

The installer's only job:
```
✓ Copy files to App\
✓ Create Start Menu shortcut
✓ Register auto-start registry key
✓ Register with Add/Remove Programs
✓ Write version metadata
```

**Add proper ARP metadata:**

```xml
<Property Id="ARPINSTALLLOCATION" Value="[INSTALLFOLDER]" />
<Property Id="ARPNOREPAIR" Value="yes" Type="string" Secure="yes" />
<Property Id="ARPNOMODIFY" Value="yes" Type="string" Secure="yes" />
<Property Id="ARPHELPLINK" Value="https://intelliattend.app/support" />
<Property Id="ARPURLINFOABOUT" Value="https://intelliattend.app" />
<Property Id="ARPPRODUCTICON" Value="AppIcon" />

<Icon Id="AppIcon" SourceFile="$(var.SourceDir)\$(var.AppName).exe" />
```

**Fix auto-start removal on uninstall:**

```xml
<Component Id="C_AutoStart" Guid="...">
  <RegistryValue Root="HKCU" 
    Key="Software\Microsoft\Windows\CurrentVersion\Run"
    Name="IntelliAttend" 
    Value="&quot;[INSTALLFOLDER]$(var.AppName).exe&quot; --intelliattend-autostart"
    Type="string" KeyPath="yes" />
</Component>
```

WiX automatically removes registry values written by components during uninstall. The `KeyPath="yes"` ensures this.

**Add upgrade detection:**

```xml
<Upgrade Id="F4E7A3C8-2D5B-4A9E-8C1D-6F3B7A2E9D0C">
  <UpgradeVersion OnlyDetect="yes" Property="PREVIOUSVERSIONINSTALLED" 
    Minimum="0.0.0.0" IncludeMaximum="yes" />
</Upgrade>

<MajorUpgrade 
  AllowSameVersionUpgrades="yes"
  DowngradeErrorMessage="A newer version of IntelliAttend SmartBoard is already installed."
  Schedule="afterInstallInitialize" />
```

**Schedule `afterInstallInitialize`** ensures the old version is fully removed before new files are copied. This prevents file-in-use issues during major upgrades.

**Post-upgrade flag (optional):**

```xml
<!-- Write a flag so the app knows it was just upgraded -->
<CustomAction Id="WriteUpgradeFlag" Directory="APPDATA_ROOT" 
  Execute="deferred" Impersonate="yes">
  <![CDATA[PREVIOUSVERSIONINSTALLED <> ""]]>
</CustomAction>
```

### New file: `scripts/deploy_silent.ps1`

For IT administrators deploying via Group Policy / Intune / endpoint management:

```powershell
param(
  [Parameter(Mandatory=$true)]
  [string]$MsiPath,
  [string]$ConfigJson,  # Optional: pre-configured config
  [switch]$NoLaunch
)

$msiexec = "$env:SystemRoot\System32\msiexec.exe"
$logFile = "$env:TEMP\IntelliAttend\Logs\install_$(Get-Date -Format yyyyMMdd_HHmmss).log"

# Ensure log directory exists
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null

$args = @("/i", $MsiPath, "/qn", "/norestart", "/log", $logFile)
$result = Start-Process -FilePath $msiexec -ArgumentList $args -Wait -PassThru

switch ($result.ExitCode) {
  0    { Write-Host "Installation complete" -ForegroundColor Green }
  3010 { Write-Host "Installation complete (reboot recommended)" -ForegroundColor Yellow }
  default {
    Write-Host "Installation failed with exit code $($result.ExitCode)" -ForegroundColor Red
    Write-Host "Log: $logFile"
    exit $result.ExitCode
  }
}

if ($ConfigJson -and (Test-Path $ConfigJson)) {
  $configDir = "$env:LOCALAPPDATA\IntelliAttendSmartBoard\Config"
  New-Item -ItemType Directory -Path $configDir -Force | Out-Null
  Copy-Item $ConfigJson "$configDir\config.json" -Force
  Write-Host "Configuration applied"
}
```

### Delete: `scripts/install.ps1`

Raw file-copy installer is removed. Only MSI installations are supported.

### Effort
**3–4 days** — WiX XML modifications, testing with major upgrades, silent install testing.

### Dependencies
- Phase 0 (paths)

### Verification
- Fresh install → verify App\ directory structure
- Major upgrade (v5.5 → v5.6) → verify old removed, new installed
- Silent install via `msiexec /i ... /qn` → verify IT deployment works
- Install while app is running → verify MajorUpgrade handles gracefully

---

## Phase 3 — Application Startup Lifecycle

**Goal:** Deterministic startup sequence with integrity checks, self-repair, and update pending detection.

### Startup Sequence

```
Boot
  │
  ▼
Integrity Check
  │ Verify all critical files exist and have non-zero size
  │ If missing file → Repair Mode
  ▼
Migration Check
  │ Detect old directory structure, migrate if needed
  │ Run database schema migrations
  ▼
Update Pending Check
  │ Read update_state.json
  │ If agent left partial update → resume or rollback
  ▼
Configuration Load
  │ Load env.json, config.json
  │ Validate required fields
  ▼
Registration Check
  │ Load registration.json
  │ If not registered → Registration Flow
  ▼
Ready
  │ Start background services
  │ Begin normal operation
```

### New files

#### `lib/core/startup/lifecycle.dart`

```dart
enum StartupPhase {
  boot,
  integrityCheck,
  migrationCheck,
  updatePendingCheck,
  configurationLoad,
  registrationCheck,
  ready,
}

enum StartupResult {
  ready,
  needsRepair,
  updatePending,
  needsRegistration,
  failed,
}

class StartupLifecycle {
  static Future<StartupResult> execute() async {
    // Phase 1: Boot
    await InstallPaths.ensureDirectories();
    await LogManager.init();
    
    // Phase 2: Integrity Check
    final integrity = await IntegrityCheck.verify();
    if (integrity.hasMissingFiles) {
      Log.e('[Startup] Integrity check failed: ${integrity.missingFiles}');
      return StartupResult.needsRepair;
    }
    
    // Phase 3: Migration
    await PathMigration.migrateIfNeeded();
    await MigrationRunner.run();
    
    // Phase 4: Update Pending
    final updateState = await StatePersister.loadUpdateState();
    if (updateState != null && updateState.isInProgress) {
      // Agent may have crashed — check if install actually completed
      final installed = await _verifyInstallCompleted(updateState);
      if (!installed) {
        return StartupResult.updatePending;
      }
    }
    
    // Phase 5: Configuration
    await _loadEnvironment();
    AppConfig.validate();
    
    // Phase 6: Registration
    final registration = await _loadRegistration();
    if (registration == null) {
      return StartupResult.needsRegistration;
    }
    
    return StartupResult.ready;
  }
}
```

#### `lib/core/startup/integrity_check.dart`

```dart
class IntegrityCheck {
  static const _requiredFiles = [
    'intelliattend_smartboard.exe',
    'flutter_windows.dll',
    'isar.dll',
    'data/app.so',
    'data/icudtl.dat',
  ];
  
  static Future<IntegrityResult> verify() async {
    final missing = <String>[];
    for (final file in _requiredFiles) {
      final path = '${InstallPaths.appDir}\\$file';
      final f = File(path);
      if (!await f.exists() || await f.length() == 0) {
        missing.add(file);
      }
    }
    return IntegrityResult(missingFiles: missing);
  }
}
```

#### `lib/core/startup/self_repair.dart`

```dart
class SelfRepair {
  /// Attempt to repair missing/corrupt files by re-running MSI repair.
  static Future<bool> repair() async {
    // msiexec /fa  (repair mode)
    // This re-copies missing files from the MSI cache
    final result = await Process.run('msiexec', [
      '/fa', _findCachedMsi(),  // Find MSI in Windows Installer cache
      '/qn',
      '/norestart',
    ]);
    return result.exitCode == 0;
  }
  
  /// Find the cached MSI in Windows Installer directory
  static String _findCachedMsi() {
    // Search %WINDIR%\Installer\{GUID}\ for our MSI
  }
}
```

#### `lib/core/startup/migration_runner.dart`

```dart
class MigrationRunner {
  static const int currentSchemaVersion = 1;
  
  static Future<void> run() async {
    final current = await _getSchemaVersion();
    if (current < currentSchemaVersion) {
      Log.i('[Migration] Running migrations v$current → v$currentSchemaVersion');
      // Run pending migrations in order
    }
  }
}
```

#### Modify: `lib/main.dart`

Replace scattered initialization:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final result = await StartupLifecycle.execute();
  
  switch (result) {
    case StartupResult.ready:
      runApp(const IntelliAttendApp());
    case StartupResult.needsRepair:
      runApp(const RepairScreen());
    case StartupResult.updatePending:
      runApp(const UpdatePendingScreen());
    case StartupResult.needsRegistration:
      runApp(const IntelliAttendApp()); // Boot screen handles registration
    case StartupResult.failed:
      runApp(const InitFailureScreen());
  }
}
```

### Effort
**4–5 days** — Startup lifecycle, integrity checks, self-repair, migration framework.

### Dependencies
- Phase 0 (paths), Phase 1 (agent state file)

### Verification
- Fresh install → verify startup sequence in logs
- Corrupt DLL → verify integrity check catches it
- Missing DLL → verify self-repair triggers
- Update pending → verify app shows correct UI
- Database migration → verify data preserved

---

## Phase 4 — Update Manifest & Validation

**Goal:** Rich manifest with version compatibility, expiration, signature verification, and release channels.

### New file: `lib/models/update_manifest.dart`

```dart
enum UpdateChannel {
  stable,
  beta,
  internal,
}

class UpdateManifest {
  final String version;
  final String sha256;
  final String? signature;
  final String downloadUrl;
  final bool force;
  final int rolloutPercentage;
  final String minimumAppVersion;
  final int? minimumBuildNumber;
  final DateTime? expiresAt;
  final String? releaseNotes;
  final String? flutterSdkVersion;
  final String? compatiblePlatform;
  final UpdateChannel channel;
  
  /// Version compatibility check
  bool isCompatibleWith(Version current) {
    if (current < Version.parse(minimumAppVersion)) return false;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) return false;
    return true;
  }
  
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}
```

### Manifest validation pipeline

```dart
static Future<bool> checkForUpdate(UpdateManifest manifest) async {
  // 1. Version compatibility
  if (!manifest.isCompatibleWith(installedVersion)) {
    Log.w('[AutoUpdater] Incompatible with current version');
    return false;
  }
  
  // 2. Expiration
  if (manifest.isExpired) {
    Log.w('[AutoUpdater] Manifest expired');
    return false;
  }
  
  // 3. Channel check (only update within same channel unless forced)
  if (!manifest.force && manifest.channel != currentChannel) {
    return false;
  }
  
  // 4. Rollout cohort
  if (!manifest.force && !manifest.includesBoard(_boardId)) {
    return false;
  }
  
  // 5. Disk space
  if (!await _hasEnoughDiskSpace()) {
    return false;
  }
  
  // 6. Maintenance window (schools don't want updates during class)
  if (!_isWithinMaintenanceWindow()) {
    _scheduleForNextWindow(manifest);
    return false;
  }
  
  return true;
}
```

### New file: `lib/services/maintenance_window.dart`

```dart
class MaintenanceWindow {
  /// Default: 10 PM – 6 AM (outside school hours)
  static TimeOfDay get defaultStart => const TimeOfDay(hour: 22, minute: 0);
  static TimeOfDay get defaultEnd => const TimeOfDay(hour: 6, minute: 0);
  
  /// Check if current time is within the maintenance window
  static bool get isActive {
    final now = TimeOfDay.now();
    if (defaultStart.hour > defaultEnd.hour) {
      // Spans midnight
      return now.hour >= defaultStart.hour || now.hour < defaultEnd.hour;
    }
    return now.hour >= defaultStart.hour && now.hour < defaultEnd.hour;
  }
  
  /// Force updates bypass the maintenance window
  static bool isAllowed({required bool force}) {
    return force || isActive;
  }
}
```

### Modify: `.github/workflows/auto-deploy.yml`

```yaml
$manifest = @{
  version = $flutterVersion
  sha256 = $sha256
  signature = $signature
  download_url = "..."
  force = $true
  rollout_percentage = 100
  minimum_app_version = "5.0.0"
  expires = (Get-Date).AddMonths(6).ToString("o")
  flutter_sdk = "3.44.6"
  compatible_platform = "windows-x64"
  channel = "stable"
  release_notes = "..."
}
```

### Effort
**2–3 days** — Manifest model, validation logic, maintenance window, CI workflow updates.

### Dependencies
- Phase 1 (agent reads manifest)

---

## Phase 5 — Recovery Mode & Self-Repair

**Goal:** Application can detect and recover from corruption, failed updates, and misconfigurations without human intervention.

### Recovery Mode

Launch with `--recovery-mode` flag or automatically when startup detects issues.

```dart
class RecoveryScreen extends StatelessWidget {
  // Shows:
  // - "Something went wrong"
  // - Repair Installation button (runs MSI repair)
  // - Export Logs button (creates Diagnostics.zip)
  // - Reset Configuration button
  // - Retry button
  // - "Continue with previous version" (if update failed)
}
```

### Self-Repair Flow

```
Startup
  │
  ▼
Integrity Check
  │ Missing: flutter_windows.dll
  ▼
Self-Repair
  │ Find MSI cache: %WINDIR%\Installer\{GUID}\{GUID}.msi
  │ Run: msiexec /fa {cached_msi} /qn /norestart
  │ MSI repairs missing files
  ▼
Re-verify
  │ All files present?
  │ Yes → Continue startup
  │ No → Show Recovery Screen
```

### New file: `lib/core/startup/self_repair.dart`

```dart
class SelfRepair {
  /// Attempt automatic repair via MSI repair mode.
  static Future<RepairResult> attemptRepair() async {
    final cachedMsi = await _findCachedMsi();
    if (cachedMsi == null) {
      return RepairResult.noMsiFound;
    }
    
    final result = await Process.run('msiexec', [
      '/fa', cachedMsi,
      '/qn', '/norestart',
      '/log', '${InstallPaths.logDir}\\repair.log',
    ]).timeout(const Duration(minutes: 5));
    
    if (result.exitCode == 0 || result.exitCode == 3010) {
      // Re-verify
      final check = await IntegrityCheck.verify();
      return check.hasMissingFiles 
          ? RepairResult.stillCorrupt 
          : RepairResult.success;
    }
    
    return RepairResult.failed;
  }
  
  static Future<String?> _findCachedMsi() async {
    // Search Windows Installer cache for our product code
  }
}
```

### Effort
**2–3 days** — Recovery screen, self-repair logic, MSI cache detection.

### Dependencies
- Phase 3 (startup lifecycle)

---

## Phase 6 — Uninstall Experience

**Goal:** Enterprise-grade uninstall with data preservation options. User is never left confused about what was removed.

### Uninstall Dialog

```
IntelliAttend SmartBoard Uninstall

The following will be removed:
  ☑ Application files (App\)
  ☑ Start Menu shortcut
  ☑ Auto-start entry

Optionally remove:
  ☐ Cache files
  ☐ Log files
  ☐ Configuration
  ☐ Local database
  ☐ Backups

[Uninstall]  [Cancel]
```

### Modify: `windows/installer/product.wxs`

Add uninstall options dialog. Run cleanup script before file removal:

```xml
<CustomAction Id="RunCleanupScript" 
  FileKey="F_cleanup_ps1" 
  ExeCommand="-RemoveCache -RemoveLogs" 
  Return="check" 
  Execute="deferred" 
  Impersonate="yes" />
```

### New file: `scripts/cleanup_on_uninstall.ps1`

```powershell
param(
  [switch]$RemoveCache,
  [switch]$RemoveLogs,
  [switch]$RemoveConfig,
  [switch]$RemoveData,
  [switch]$RemoveBackup
)

$baseDir = "$env:LOCALAPPDATA\IntelliAttendSmartBoard"

if ($RemoveCache)   { Remove-Item "$baseDir\Cache" -Recurse -Force -ErrorAction SilentlyContinue }
if ($RemoveLogs)    { Remove-Item "$baseDir\Logs" -Recurse -Force -ErrorAction SilentlyContinue }
if ($RemoveConfig)  { Remove-Item "$baseDir\Config" -Recurse -Force -ErrorAction SilentlyContinue }
if ($RemoveData)    { Remove-Item "$baseDir\Data" -Recurse -Force -ErrorAction SilentlyContinue }
if ($RemoveBackup)  { Remove-Item "$baseDir\Backup" -Recurse -Force -ErrorAction SilentlyContinue }

# Clean up auto-start registry (safety net)
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
  -Name "IntelliAttend" -Force -ErrorAction SilentlyContinue

# Remove base directory if empty
if ((Get-ChildItem $baseDir -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
  Remove-Item $baseDir -Force
}
```

### Effort
**2–3 days** — WiX dialog, cleanup script, testing.

### Dependencies
- Phase 2 (installer redesign)

---

## Phase 7 — Enterprise Deployment Modes

**Goal:** Three installation modes for different institutional environments.

| Mode | Use Case | Command |
|------|----------|---------|
| Interactive MSI | Individual faculty installation | Double-click MSI |
| Silent MSI | Group Policy / Intune / endpoint management | `msiexec /i ... /qn` |
| Offline Bundle | Schools with no internet | USB drive with MSI + config |

### New file: `scripts/deploy_offline_bundle.ps1`

```powershell
param(
  [string]$MsiPath,
  [string]$ConfigPath,
  [string]$OutputDir = ".\IntelliAttend-Offline"
)

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Copy-Item $MsiPath "$OutputDir\"
Copy-Item $ConfigPath "$OutputDir\config.json"
Copy-Item "scripts\deploy_silent.ps1" "$OutputDir\"

@"
# IntelliAttend Offline Installation

1. Copy this folder to the target PC
2. Open PowerShell
3. Run: .\deploy_silent.ps1 -MsiPath .\*.msi -ConfigJson .\config.json
"@ | Out-File "$OutputDir\README.txt" -Encoding UTF8
```

### Effort
**1 day** — PowerShell scripts, documentation.

### Dependencies
- Phase 2 (installer)

---

## Phase 8 — Observability, Diagnostics & Windows Event Log

**Goal:** Separate log files per concern, diagnostic export, and Windows Event Log integration.

### Log Files

```
%LOCALAPPDATA%\IntelliAttendSmartBoard\Logs\
├── install.log        # MSI install/upgrade/uninstall
├── update.log         # Auto-update lifecycle
├── rollback.log       # Rollback operations
├── startup.log        # Startup sequence timing
├── network.log        # API calls, WebSocket, heartbeat
├── crash.log          # Native crashes, Flutter errors
└── repair.log         # Self-repair operations
```

### New file: `lib/core/logging/log_manager.dart`

```dart
class LogManager {
  static late Directory _logDir;
  
  static Future<void> init() async {
    _logDir = Directory(InstallPaths.logDir);
    await _logDir.create(recursive: true);
  }
  
  static String get installLog => '${_logDir.path}\\install.log';
  static String get updateLog => '${_logDir.path}\\update.log';
  static String get rollbackLog => '${_logDir.path}\\rollback.log';
  static String get startupLog => '${_logDir.path}\\startup.log';
  static String get networkLog => '${_logDir.path}\\network.log';
  static String get crashLog => '${_logDir.path}\\crash.log';
  static String get repairLog => '${_logDir.path}\\repair.log';
  
  /// Rotate logs: if any file > 5MB, rename to .log.{timestamp}
  static Future<void> rotateIfNeeded() async {
    for (final file in await _logDir.list().toList()) {
      if (file is File && await file.length() > 5 * 1024 * 1024) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        await file.rename('${file.path}.$timestamp');
      }
    }
  }
}
```

### Diagnostic Export

```dart
class DiagnosticExport {
  /// Create a ZIP file with everything IT support needs.
  static Future<File> export() async {
    final tempDir = Directory(InstallPaths.tempDir);
    final zipPath = '${tempDir.path}\\Diagnostics_${DateTime.now().millisecondsSinceEpoch}.zip';
    
    // Contents:
    // - All log files
    // - installation_state.json
    // - update_state.json
    // - update_health.json
    // - config.json (sanitized — no secrets)
    // - System info (Windows version, .NET version, GPU info)
    // - App version
    // - Installed file list with sizes
    // - Network status (last 10 heartbeat results)
    // - Update history (last 10 updates)
    
    return File(zipPath);
  }
}
```

### Windows Event Log Integration

#### New file: `windows/update_agent/event_logger.cpp`

```cpp
// Register Event Source on first run
// Log to Application log with source "IntelliAttend SmartBoard"
// Event IDs:
//   1000 - Installation successful
//   1001 - Update started
//   1002 - Update completed
//   1003 - Update failed
//   1004 - Rollback completed
//   1005 - Registration failed
//   1006 - Configuration loaded

void LogToEventLog(const wchar_t* message, WORD eventType, DWORD eventId) {
    HANDLE hEvent = RegisterEventSourceW(NULL, L"IntelliAttend SmartBoard");
    if (hEvent) {
        ReportEventW(hEvent, eventType, 0, eventId, NULL, 1, 0, &message, NULL);
        DeregisterEventSource(hEvent);
    }
}
```

### New file: `lib/core/logging/event_log.dart`

```dart
/// Dart wrapper for Windows Event Log (via Process.run)
class WindowsEventLog {
  static Future<void> log(WindowsEvent event, {String? detail}) async {
    if (!Platform.isWindows) return;
    
    final message = detail != null ? '${event.label}: $detail' : event.label;
    
    await Process.run('powershell', [
      '-NoProfile', '-Command',
      'Write-EventLog -LogName Application -Source "IntelliAttend SmartBoard" '
      '-EventId ${event.id} -EntryType ${event.entryType} -Message "$message"',
    ]);
  }
}

enum WindowsEvent {
  installSuccess(1000, 'Information'),
  updateStarted(1001, 'Information'),
  updateCompleted(1002, 'Information'),
  updateFailed(1003, 'Error'),
  rollbackCompleted(1004, 'Warning'),
  registrationFailed(1005, 'Error'),
  configLoaded(1006, 'Information');
  
  final int id;
  final String entryType;
  const WindowsEvent(this.id, this.entryType);
  
  String get label => name.replaceAll(RegExp(r'(?<!^)(?=[A-Z])'), ' ');
}
```

### Effort
**2–3 days** — Log manager, diagnostic export, event log integration.

### Dependencies
- Phase 0 (paths), Phase 1 (agent)

---

## Phase 9 — UX Polish — Human-Readable Messages

**Goal:** Every user-facing message is in plain language. Technical details belong in logs, not in UI.

### Installation UI

```
Installing IntelliAttend SmartBoard

Preparing installation...
Copying application files...
Registering with Windows...
Creating Start Menu shortcut...

✓ Installation Complete

[IntelliAttend SmartBoard has been installed successfully.]
[Launch IntelliAttend]                    [Close]
```

### Update UI

```
New Version Available

Version 5.6.0
  • Security improvements
  • Better performance
  • Bug fixes

Estimated time: ~30 seconds

[Update Now]    [Remind Me Later]
```

### During Update

```
Updating IntelliAttend

Downloading update... 75%
Verifying files...
Installing...
Restarting application...

Please do not turn off your computer.
```

### Failure Messages

**Never show:**
```
MSI Exit Code 1603
```

**Always show:**
```
The update couldn't be completed.

Your current version (v5.5.0) is still working normally.
We'll automatically retry the update later.

If this keeps happening, go to Settings → Help → Export Diagnostics
and send the file to support@intelliattend.app.
```

### Recovery Mode UI

```
Something Went Wrong

IntelliAttend detected a problem during startup.

What would you like to do?

[Repair Installation]    [Export Logs]
[Reset Configuration]    [Continue Anyway]
```

### Effort
**2–3 days** — Replace error codes with human-readable strings, create overlay widgets.

### Dependencies
- Phase 3 (startup lifecycle), Phase 5 (recovery mode)

---

## Dependency Graph

```
Phase 0 ──── Phase 1 ──── Phase 3 ──── Phase 4
   │              │              │
   │              │              └──────── Phase 5
   │              │
   │              └──────── Phase 8
   │
   └──────────── Phase 2 ──── Phase 6 ──── Phase 7
                    │
                    └──────── Phase 9
```

## Execution Order (Actual)

```
Phase 0  ✅ Path Normalization & State Machine Foundation
Phase 1  ✅ Detached Update Agent (C++) + Hardening
Phase 2  ✅ Stateless Installer (WiX MSI)
Phase 3  ✅ Application Lifecycle Manager
Phase 4  ✅ Manifest Enrichment (v2 schema, HMAC, channels)
Phase 5  ✅ Recovery UI (standalone dark-themed screen)
Phase 6  ✅ Enterprise Deployment (config schema, validator)
--- Architecture Freeze declared ---
Phase 7  ✅ Cloud Observability (Sentry, health snapshots, diagnostic bundles)
Phase 8  ✅ Production Certification (framework, 58 test scenarios)
Phase 9  ✅ Security Audit (31 findings, remediation matrix)
Phase 10 ✅ Performance Validation (10 surfaces, timing/memory budgets)
Phase 11 ✅ Operational Readiness (runbooks, monitoring, incident response)
```

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| WiX MajorUpgrade fails on existing installs | Medium | High | Test with v5.5.0 → v5.6.0 upgrade on clean and dirty installs |
| Update agent can't find app process | Low | Medium | Agent reads PID from state file; fallback: enumerate processes by name |
| MSI repair cache missing | Medium | Medium | Graceful fallback: show Recovery Screen with manual options |
| Self-repair fails (corrupt MSI cache) | Low | High | Show Recovery Screen; user can re-download MSI |
| Enterprise silent install requires admin | Low | Low | Per-user install doesn't require admin; document this |
| Maintenance window bypass in critical update | Low | Low | `force=true` bypasses maintenance window |

## Migration Strategy

For existing v5.5.0 installations:

1. On first launch after upgrade, detect old directory structure (no App\, Data\, Config\ subdirectories)
2. Create new subdirectories
3. Move files to appropriate locations:
   - `.exe`, `.dll` → `App\`
   - `update_health.json` → `Data\`
   - `.env` → `Config\env.json`
4. Write migration marker: `Data\migration_complete.json`
5. Log migration result

```dart
class PathMigration {
  static Future<void> migrateIfNeeded() async {
    final marker = File('${InstallPaths.dataDir}\\migration_complete.json');
    if (await marker.exists()) return;
    
    final root = Directory(InstallPaths.root);
    if (!await root.exists()) return;
    
    // Check if old flat structure exists (no App\ subdirectory)
    final appSubdir = Directory('${InstallPaths.root}\\App');
    if (await appSubdir.exists()) return; // Already migrated
    
    Log.i('[Migration] Detected old directory structure — migrating');
    
    // Create new directories
    await InstallPaths.ensureDirectories();
    
    // Move binaries to App\
    for (final file in await root.list().whereType<File>().toList()) {
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.exe') || name.endsWith('.dll')) {
        await file.rename('${InstallPaths.appDir}\\$name');
      }
    }
    
    // Move data files
    final updateHealth = File('${InstallPaths.root}\\update_health.json');
    if (await updateHealth.exists()) {
      await updateHealth.rename(InstallPaths.updateHealthFile);
    }
    
    // Move config
    final envFile = File('${InstallPaths.root}\\.env');
    if (await envFile.exists()) {
      await envFile.rename(InstallPaths.envFile);
    }
    
    // Mark migration complete
    await marker.writeAsString(jsonEncode({
      'migratedAt': DateTime.now().toIso8601String(),
      'fromVersion': '5.5.0',
    }));
    
    Log.i('[Migration] Complete');
  }
}
```
