# SmartBoard Auto-Update Strategy

> How to push feature changes, UI updates, and bug fixes to classroom boards without IT staff touching each machine.

---

## Three-Layer Update Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Remote Config / Feature Flags                 │
│  (Server-driven, no rebuild, instant)                   │
│  Use for: toggling features, changing UI labels,        │
│           disabling modules, A/B testing                │
├─────────────────────────────────────────────────────────┤
│  Layer 2: Shorebird Code Push                           │
│  (Dart code push, partial rebuild, ~seconds)            │
│  Use for: bug fixes, UI changes, business logic         │
├─────────────────────────────────────────────────────────┤
│  Layer 3: Binary Auto-Updater                           │
│  (Full MSI/exe replacement, ~minutes)                   │
│  Use for: native plugin changes, SDK updates,           │
│           Flutter engine upgrades                       │
└─────────────────────────────────────────────────────────┘
```

---

## Layer 1: Remote Config / Feature Flags (Recommended First)

### How It Works

The heartbeat response already carries a `session` object. Extend it to include a `config` map:

```json
// POST /api/v1/board/heartbeat response (extended)
{
  "status": "ok",
  "server_time": "...",
  "session": { ... },
  "config": {
    "config_version": 12,
    "flags": {
      "enable_video_background": false,
      "enable_documents": true,
      "enable_analytics": false,
      "enable_notifications": true,
      "enable_workspace": true,
      "kiosk_mode": "fullscreen",
      "qr_rotation_interval_ms": 5000,
      "session_window_seconds": 300,
      "idle_theme": "dark",
      "allowed_screens": ["idle", "attendance", "summary"],
      "disabled_features": ["analytics_nav", "debug_buttons"]
    },
    "ui": {
      "branding": {
        "title": "IntelliAttend SmartBoard",
        "logo_url": "https://cdn.example.com/logo.png"
      },
      "labels": {
        "welcome_text": "Welcome to Smart Class",
        "footer_text": "v5.4.0"
      }
    },
    "force_update": {
      "minimum_version": "5.3.0",
      "update_url": "https://releases.example.com/v5.5.0.msi",
      "update_required": false,
      "release_notes": "Bug fixes and performance improvements"
    }
  }
}
```

### Client-Side Implementation

**Step 1: Create a config model**

```dart
// lib/models/remote_config.dart
class RemoteConfig {
  final int configVersion;
  final Map<String, dynamic> flags;
  final Map<String, dynamic> ui;
  final ForceUpdateConfig? forceUpdate;

  RemoteConfig.fromJson(Map<String, dynamic> json)
      : configVersion = json['config_version'] ?? 0,
        flags = Map<String, dynamic>.from(json['flags'] ?? {}),
        ui = Map<String, dynamic>.from(json['ui'] ?? {}),
        forceUpdate = json['force_update'] != null
            ? ForceUpdateConfig.fromJson(json['force_update'])
            : null;
}

class ForceUpdateConfig {
  final String minimumVersion;
  final String? updateUrl;
  final bool updateRequired;

  ForceUpdateConfig.fromJson(Map<String, dynamic> json)
      : minimumVersion = json['minimum_version'] ?? '',
        updateUrl = json['update_url'],
        updateRequired = json['update_required'] ?? false;
}
```

**Step 2: Config service that persists and serves flags**

```dart
// lib/services/remote_config_service.dart
class RemoteConfigService {
  static RemoteConfig? _config;
  static int _lastConfigVersion = 0;

  static Future<void> applyConfig(Map<String, dynamic>? configData) async {
    if (configData == null) return;
    final config = RemoteConfig.fromJson(configData);
    if (config.configVersion <= _lastConfigVersion) return;

    _config = config;
    _lastConfigVersion = config.configVersion;
    await _persistConfig(config);
  }

  static bool isFeatureEnabled(String feature) {
    if (_config?.flags.containsKey(feature) == true) {
      return _config!.flags[feature] == true;
    }
    return true; // default: enabled
  }

  static String? getLabel(String key) {
    return _config?.ui[key]?.toString();
  }
}
```

**Step 3: Integrate with heartbeat**

In `heartbeat_service.dart`, after receiving the heartbeat response:

```dart
final configData = result['config'] as Map<String, dynamic>?;
if (configData != null) {
  await RemoteConfigService.applyConfig(configData);
}
```

**Step 4: Use flags throughout the app**

```dart
// In idle_screen.dart — conditionally hide nav items
if (RemoteConfigService.isFeatureEnabled('analytics_nav')) {
  // show analytics button
}

// In any screen — check if feature is disabled
if (!RemoteConfigService.isFeatureEnabled('enable_documents')) {
  // hide document buttons
}
```

### What You Can Control with Feature Flags

| Scenario | Config Change | Effect |
|----------|---------------|--------|
| Disable analytics | `flags.enable_analytics: false` | Analytics nav/link hidden |
| Disable documents | `flags.enable_documents: false` | Document buttons hidden |
| Change QR speed | `flags.qr_rotation_interval_ms: 8000` | QR rotates slower |
| Force dark theme | `flags.idle_theme: "dark"` | Theme switches immediately |
| Emergency lockdown | `flags.allowed_screens: ["idle"]` | Only idle screen accessible |
| Hide debug buttons | `flags.disabled_features: ["debug_buttons"]` | Debug UI hidden in release |
| Change welcome text | `ui.labels.welcome_text: "..."` | Text updates without rebuild |

### Pros & Cons

**Pros:**
- Instant — no download, no restart
- No app store review
- Can target specific boards or groups
- Can be reverted instantly
- Works offline (last config persisted)

**Cons:**
- Cannot change UI layout or add new screens
- Cannot fix native code bugs
- Limited to what's already coded

---

## Layer 2: Shorebird Code Push

### What It Is

[Shorebird](https://shorebird.dev/) is a Flutter code push service that delivers Dart code patches OTA. When you publish a patch, boards download and apply it on next restart (or immediately with a hot restart).

### How to Set It Up

```bash
# Install Shorebird CLI
powershell -Command "& { $(irm https://shorebird.dev/install.ps1) }"

# Initialize in your project
shorebird init

# Create a release
shorebird release --flavor production

# Push a patch (for hotfixes)
shorebird patch --flavor production

# Check patch status
shorebird account list
```

### Patch vs Release

| Aspect | Shorebird Patch | Full Release |
|--------|----------------|--------------|
| Size | ~100KB (Dart diff) | ~15MB (full binary) |
| Scope | Dart code only | Dart + native + assets |
| Restart | Required | Required |
| Engine update | ❌ No | ✅ Yes |
| Native plugins | ❌ No | ✅ Yes |

### When to Use

- **Bug fixes** in Dart business logic
- **UI tweaks** (colors, text, layout changes)
- **State management changes**
- **New screens** built with existing widgets/plugins

### Pros & Cons

**Pros:**
- Tiny download size (~100KB)
- Works with existing Flutter tooling
- Can patch any Dart code
- Supports Windows

**Cons:**
- Paid service (beyond free tier)
- Cannot change native plugins or Flutter engine
- Requires app restart to apply
- Need to manage releases + patches

---

## Layer 3: Binary Auto-Updater

### How It Works

The heartbeat response tells the board a new version is available. The app downloads the MSI in the background, verifies it, and installs it.

### Flow

```
1. Heartbeat returns { force_update: { minimum_version: "5.5.0",
     update_url: "https://.../IASB-v5.5.0.msi",
     update_required: true } }

2. App compares current version (5.4.0) with minimum_version

3. If update required:
   a. Show "Updating..." overlay to prevent use during install
   b. Download MSI to temp folder with progress indicator
   c. Verify file hash (SHA-256 from server)
   d. Run msiexec /i <msi> /quiet /norestart
   e. Wait for install to complete
   f. Restart the app (or reboot the system)

4. If update available (not required):
   a. Show notification "Update available — install on next restart?"
   b. Download in background, mark for install at next boot
```

### Client Implementation

```dart
class AutoUpdater {
  static Future<void> checkForUpdate(ForceUpdateConfig config) async {
    final current = await PackageInfo.fromPlatform();
    if (_compareVersions(current.version, config.minimumVersion) >= 0) {
      return; // already up to date
    }

    // Download MSI
    final tempDir = await getTemporaryDirectory();
    final msiPath = '${tempDir.path}\\IASB-${config.minimumVersion}.msi';

    await _downloadFile(config.updateUrl!, msiPath, onProgress: (progress) {
      // Update UI with progress
    });

    // Verify hash (optional — server provides SHA-256)
    // await _verifyHash(msiPath, config.expectedHash);

    // Run installer silently
    final result = await Process.run('msiexec', [
      '/i', msiPath,
      '/quiet',
      '/norestart',
    ]);

    if (result.exitCode == 0) {
      // Restart app
      await Process.start(
        'powershell',
        ['-Command', 'Start-Process "$msiPath"'],
      );
    }
  }
}
```

### Pros & Cons

**Pros:**
- Can update anything (Flutter engine, native plugins, assets)
- Full control over the process
- No third-party dependency
- Works with existing deployment (MSI)

**Cons:**
- Large download (~15MB+)
- Takes 1-3 minutes to install
- Requires app restart / reboot
- Risk of failed install leaving board unusable (need rollback plan)
- Need code signing / secure channel for MSI delivery

---

## Recommended Implementation Order

### Phase 1 (Week 1-2): Feature Flags via Heartbeat

The highest ROI with lowest risk. Implement `RemoteConfigService` and extend the heartbeat response.

**Files to create/modify:**
- `lib/models/remote_config.dart` — config model
- `lib/services/remote_config_service.dart` — apply & persist
- `lib/services/heartbeat_service.dart` — parse `config` from response
- Each screen — use `RemoteConfigService.isFeatureEnabled()` to gate features

**Testing:** No server change needed initially — if `config` is null/absent, app runs as before.

### Phase 2 (Week 3-4): Binary Auto-Updater

Implement the auto-download-and-install loop.

**Files to create/modify:**
- `lib/services/auto_updater.dart` — download + verify + install
- `lib/presentation/widgets/update_overlay.dart` — "Updating..." screen
- `lib/core/network/api_service.dart` — version check endpoint
- Backend: `POST /api/v1/board/check-update`

### Phase 3 (Future): Shorebird Code Push

Add Shorebird for rapid hotfix delivery when you need to push Dart code changes without a full MSI download.

---

## Backend Changes Required

The server needs to return a `config` block in the heartbeat response (or expose a `GET /api/v1/board/config` endpoint):

```python
# In heartbeat response
{
    "status": "ok",
    "server_time": "...",
    "session": {...},
    "config": {
        "config_version": <int>,
        "flags": { <feature_name>: <value> },
        "ui": { <ui_key>: <value> },
        "force_update": {
            "minimum_version": "5.5.0",
            "update_url": "https://cdn.example.com/releases/IASB-v5.5.0.msi",
            "update_required": false,
            "sha256": "abc123..."
        } | null
    }
}
```

Or as a dedicated endpoint:

```python
@router.get("/api/v1/board/config")
async def get_board_config(board=Depends(get_current_board_pg)):
    return {
        "config_version": db.get_config_version(board.institution_id),
        "flags": db.get_feature_flags(board.institution_id, board.board_id),
        "ui": db.get_ui_config(board.institution_id),
        "force_update": db.get_update_policy(board.institution_id),
    }
```

---

## Data Flow Summary

```
                      ┌──────────────────┐
                      │   Admin Dashboard │
                      │   (set flags)     │
                      └────────┬─────────┘
                               │
                               ▼
                      ┌──────────────────┐
                      │   Backend API     │
                      │   (PostgreSQL)    │
                      └────────┬─────────┘
                               │
            ┌──────────────────┼──────────────────┐
            ▼                  ▼                   ▼
    ┌──────────────┐  ┌──────────────┐   ┌──────────────┐
    │ Board #1     │  │ Board #2     │   │ Board #N     │
    │ (Room 204)   │  │ (Room 205)   │   │ (Room 206)   │
    │ Flags: A,B,C │  │ Flags: A,B   │   │ Flags: A,C   │
    └──────────────┘  └──────────────┘   └──────────────┘
         │                  │                   │
         ▼                  ▼                   ▼
    Heartbeat every 15s → parse config → apply locally
    Feature flags take effect within 15 seconds
    Force update → download MSI → install → reboot
```

---

## Layer 4: Rollback & Health Monitoring (Safety Net)

> The most critical guarantee in an auto-update system: **if the new version crashes, the board must recover automatically without IT intervention.**

### Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  UpdateHealthMonitor                                             │
│                                                                  │
│  On every startup:                                               │
│    1. Read current version from PackageInfo                      │
│    2. Compare with stored "previous version"                     │
│    3. If version changed → reset startup counter                 │
│    4. If crash loop detected AND version is new                  │
│       → ROLLBACK                                                 │
│                                                                  │
│  After 3 successful starts:                                     │
│    → Mark version as "stable"                                    │
│    → Delete rollback backup                                      │
│    → Report "completed" to server                                │
│                                                                  │
│  Storage:                                                        │
│    %LOCALAPPDATA%\IntelliAttendSmartBoard\update_health.json     │
│      { "previous_version": "5.4.0",                              │
│        "status": "pending",                                      │
│        "stable_startups": 0,                                     │
│        "backup_path": "..._backup_v5.4.0/" }                     │
└──────────────────────────────────────────────────────────────────┘
```

### Rollback Flow

```
1. Server heartbeat returns force_update: { minimum_version: "5.5.0" }
2. AutoUpdater calls UpdateHealthMonitor.preserveCurrentInstall()
   → Copies %LOCALAPPDATA%\IntelliAttendSmartBoard\ → ..._backup_v5.4.0\
3. AutoUpdater downloads + installs v5.5.0 MSI
4. App restarts on v5.5.0
5. UpdateHealthMonitor.init() detects version change (5.4.0 → 5.5.0)
   → Sets status = "pending", stable_startups = 0
6. Case A: v5.5.0 starts successfully
   → startBackgroundProtocols() calls markStartupSuccessful()
   → After 3 consecutive successes, status = "stable", backup deleted
   → Server notified: update completed
7. Case B: v5.5.0 crashes on startup
   → StartupService detects crash loop (LaunchInProgress + recent start)
   → main.dart checks UpdateHealthMonitor.handleCrashLoopDetected()
   → If status is "pending", rollback triggers:
     a. Delete current (broken) install dir
     b. Copy backup → install dir
     c. Write "rolled_back" status to registry
     d. Exit process
   → OS auto-start relaunches v5.4.0
   → Server notified: update rolled back
```

### What Makes This Production-Grade

| Feature | Why It Matters | Implementation |
|---------|---------------|----------------|
| **Version-aware crash detection** | Distinguishes "first launch after update crash" from "normal crash" — doesn't roll back the wrong version | `UpdateHealthMonitor.status == pending` check before rollback |
| **Pre-update backup** | Ensures a clean previous version always exists for rollback | `preserveCurrentInstall()` copies entire app dir |
| **Stabilisation window** | Prevents flapping — requires 3 successful starts before marking stable | `_requiredStableStarts = 3` |
| **Server reporting** | Dashboard knows exactly which boards updated, crashed, or rolled back | `POST /api/v1/board/update-status` |
| **Backup cleanup** | Automatically frees disk space after stabilisation | `_cleanupBackup()` deletes backup dir |
| **Rollback count tracking** | Diagnostic metric to detect systemic update issues | `_rollbackCount` counter |

---

## Summary: Which to Use When

| Situation | Best Approach |
|-----------|---------------|
| Hide a broken feature | Feature flag (instant) |
| Change welcome text | Feature flag (instant) |
| Disable analytics for a week | Feature flag (instant) |
| Fix a null pointer crash | Shorebird patch (~100KB) |
| Update QR code layout | Shorebird patch (~100KB) |
| Add analytics screen | Shorebird patch or release |
| Update Flutter SDK | Full MSI release |
| Change native Windows plugin | Full MSI release |
| Update assets (images, PDFs) | Full MSI release |
| Emergency lockdown (all boards) | Feature flag (instant) |
