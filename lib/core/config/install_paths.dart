import 'dart:io';

import 'package:flutter/foundation.dart';

/// Result of a path validation check.
class PathValidationResult {
  /// Writable directories (passed validation).
  final List<String> writable;

  /// Directories that failed the writability check.
  final List<String> failed;

  const PathValidationResult({required this.writable, required this.failed});

  bool get isValid => failed.isEmpty;
}

/// Single source of truth for all installation paths.
///
/// The root directory remains `%LOCALAPPDATA%\IntelliAttendSmartBoard` for
/// backward compatibility with existing deployments. Internal separation
/// into Data/Config/Cache/Updates/Logs/Backup is the current contract; the
/// binary directory is resolved at runtime from the running executable (see
/// [appDir]) because the MSI and Inno Setup installers use different layouts.
///
/// Every file path in the codebase MUST go through this class. No hardcoded
/// paths are allowed outside of this file.
///
/// Typed [Directory] and [File] getters are provided alongside string paths
/// so consumers never need to wrap strings manually:
/// ```dart
/// // Preferred:
/// InstallPaths.dataDirectory.createSync(recursive: true);
/// // Avoid:
/// Directory(InstallPaths.dataDir).createSync(recursive: true);
/// ```
class InstallPaths {
  InstallPaths._();

  // ── Root ─────────────────────────────────────────────────────────────────

  static final String _localAppData =
      Platform.environment['LOCALAPPDATA'] ??
      '${Platform.environment['USERPROFILE']}\\AppData\\Local';

  /// Root: `%LOCALAPPDATA%\IntelliAttendSmartBoard`
  static String get root =>
      testRootOverride ?? '$_localAppData\\IntelliAttendSmartBoard';
  static Directory get rootDirectory => Directory(root);

  // ── Binary directory ─────────────────────────────────────────────────────
  //
  // IMPORTANT (2026-07-31): The binary directory is resolved at runtime from
  // the running executable, NOT hardcoded to `$root\App`.
  //
  //   - The legacy MSI installer (v5.5.0.11 and earlier) placed binaries in
  //     `%LOCALAPPDATA%\IntelliAttendSmartBoard\App\`.
  //   - The current Inno Setup installer (v5.5.0.12+, windows/inno_setup/
  //     setup.iss) places binaries directly in the install root.
  //
  // Hardcoding `App\` broke self-update on Inno-installed boards: the app
  // looked for `App\update_agent.exe` while the installer shipped it to the
  // root, so UpdateAgentLauncher failed to launch the agent. Resolving from
  // `Platform.resolvedExecutable` is correct for BOTH layouts and self-heals
  // existing boards. Data/Config/Cache/Updates/Logs/Backup stay under [root].

  /// Test override for the install root. When set, the canonical `App\`
  /// subdirectory layout is used so unit tests stay hermetic.
  @visibleForTesting
  static String? testRootOverride;

  /// Directory containing the running application binary.
  static String get appDir {
    final override = testRootOverride;
    if (override != null && override.isNotEmpty) return '$override\\App';
    if (!kIsWeb && Platform.isWindows) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        if (exeDir.isNotEmpty) return exeDir;
      } catch (_) {}
    }
    return '$root\\App';
  }
  static Directory get appDirectory => Directory(appDir);

  /// Primary executable path (the running process).
  static String get exePath {
    final override = testRootOverride;
    if (override != null && override.isNotEmpty) {
      return '$override\\App\\intelliattend_smartboard.exe';
    }
    if (!kIsWeb && Platform.isWindows) {
      try {
        final exe = Platform.resolvedExecutable;
        if (exe.isNotEmpty) return exe;
      } catch (_) {}
    }
    return '$appDir\\intelliattend_smartboard.exe';
  }
  static File get exeFile => File(exePath);

  /// Detached update agent executable (Phase 1). Always co-located with the
  /// running application binary in both installer layouts.
  static String get updateAgentPath => '$appDir\\update_agent.exe';
  static File get updateAgentFile => File(updateAgentPath);

  // ── Application state (app-managed) ──────────────────────────────────────

  /// Persistent application state: registration, health, update state.
  static String get dataDir => '$root\\Data';
  static Directory get dataDirectory => Directory(dataDir);

  /// User-facing configuration: env.json, config.json.
  static String get configDir => '$root\\Config';
  static Directory get configDirectory => Directory(configDir);

  /// Ephemeral cached data that can be safely deleted.
  static String get cacheDir => '$root\\Cache';
  static Directory get cacheDirectory => Directory(cacheDir);

  /// Downloaded MSI update packages.
  static String get updateDir => '$root\\Updates';
  static Directory get updateDirectory => Directory(updateDir);

  /// Structured log files (install, update, rollback, crash, etc.).
  static String get logDir => '$root\\Logs';
  static Directory get logDirectory => Directory(logDir);

  /// Rollback backups of previous versions.
  static String get backupDir => '$root\\Backup';
  static Directory get backupDirectory => Directory(backupDir);

  // ── Specific files ──────────────────────────────────────────────────────

  /// Single-instance lock file.
  static String get lockFile => '$dataDir\\app.lock';
  static File get lockFileInstance => File(lockFile);

  /// Update health state (persisted by UpdateHealthMonitor).
  static String get updateHealthFile => '$dataDir\\update_health.json';
  static File get updateHealthFileInstance => File(updateHealthFile);

  /// Update state contract between app and detached update agent.
  static String get updateStateFile => '$dataDir\\update_state.json';
  static File get updateStateFileInstance => File(updateStateFile);

  /// Board registration data.
  static String get registrationFile => '$dataDir\\registration.json';
  static File get registrationFileInstance => File(registrationFile);

  /// Installation lifecycle state.
  static String get installationStateFile =>
      '$dataDir\\installation_state.json';
  static File get installationStateFileInstance =>
      File(installationStateFile);

  /// Production environment config (written by install_production_msi.ps1).
  static String get envFile => '$configDir\\env.json';
  static File get envFileInstance => File(envFile);

  /// Application configuration.
  static String get configFile => '$configDir\\config.json';
  static File get configFileInstance => File(configFile);

  // ── Temp directory (outside app root) ────────────────────────────────────

  /// Temporary files for the update agent and other transient operations.
  static String get tempDir => '${Directory.systemTemp.path}\\IntelliAttend';
  static Directory get tempDirectory => Directory(tempDir);

  // ── Legacy paths (for migration) ────────────────────────────────────────

  /// Old flat install directory used by v5.5.0 and earlier.
  static String get legacyRoot => _localAppData;

  /// Old executable path (before App\ subdirectory).
  static String get legacyExePath =>
      '$legacyRoot\\intelliattend_smartboard\\intelliattend_smartboard.exe';

  /// Old .env path (before Config\ subdirectory).
  static String get legacyEnvPath =>
      '$legacyRoot\\IntelliAttendSmartBoard\\.env';

  /// Old update health path (before Data\ subdirectory).
  static String get legacyUpdateHealthPath =>
      '$legacyRoot\\IntelliAttendSmartBoard\\update_health.json';

  // ── Directory creation ──────────────────────────────────────────────────

  /// Ensure all application directories exist. Called once at startup.
  static Future<void> ensureDirectories() async {
    final dirs = [
      rootDirectory,
      appDirectory,
      dataDirectory,
      configDirectory,
      cacheDirectory,
      updateDirectory,
      logDirectory,
      backupDirectory,
      tempDirectory,
    ];
    for (final dir in dirs) {
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
    }
  }

  // ── Validation ──────────────────────────────────────────────────────────

  /// Directories that must be writable for normal operation.
  static final List<String> _writableDirs = [
    dataDir,
    configDir,
    cacheDir,
    updateDir,
    logDir,
    backupDir,
  ];

  /// Validate that all critical directories exist and are writable.
  ///
  /// Called at startup. If any directory fails validation, the caller
  /// should enter Recovery Mode.
  static PathValidationResult validate() {
    final writable = <String>[];
    final failed = <String>[];

    for (final path in _writableDirs) {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        failed.add(path);
        continue;
      }

      // Test writability by attempting to write a temp file.
      try {
        final testFile = File('$path\\.write_test');
        testFile.writeAsStringSync('ok');
        testFile.deleteSync();
        writable.add(path);
      } catch (_) {
        failed.add(path);
      }
    }

    return PathValidationResult(writable: writable, failed: failed);
  }
}
