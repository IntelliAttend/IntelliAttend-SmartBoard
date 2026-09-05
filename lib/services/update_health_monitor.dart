import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/install_paths.dart';
import '../core/utils/logger.dart';
import '../core/utils/version.dart';
import 'api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateHealthMonitor
//
// Production-grade health tracking for binary auto-updates. This service
// sits between [AutoUpdater] (download + install) and [StartupService]
// (crash loop detection) to provide version-aware crash monitoring.
//
// ── Responsibilities ────────────────────────────────────────────────────────
//
//   1. **Version-aware crash detection** — detects when a crash loop is
//      specifically caused by a newly installed version (not just any crash).
//
//   2. **Rollback management** — triggers rollback to the previous version
//      when the new version crashes repeatedly. Copies the current install
//      directory to a backup *before* each update so a clean revert is
//      possible.
//
//   3. **Startup stabilisation** — requires N consecutive successful
//      launches before marking a version as "stable" and deleting the backup.
//
//   4. **Server reporting** — sends update success / failure / rollback
//      events to the server so the admin dashboard can track per-board
//      version status.
//
// ── Data persisted (Windows Registry) ───────────────────────────────────────
//
//   Registry: HKCU\Software\IntelliAttend\SmartBoard\UpdateHealth
//   ─────────────────────────────────────────────────────────────────
//   CurrentVersion    The version string of the currently running app
//   PreviousVersion   The version string before the most recent update
//   UpdateStatus      "stable" | "pending" | "rollingBack" | "failed"
//   StableStartups    How many consecutive successful starts of this version
//   LastStableVersion The last version that reached "stable" status
//   RollbackCount     Total number of rollbacks performed (diagnostic)
//   BackupPath        Path to the backup folder of the previous install
//
// ── Rollback mechanism ──────────────────────────────────────────────────────
//
//   Before [AutoUpdater] installs a new MSI, [preserveCurrentInstall] is
//   called to copy the current application directory to a backup location:
//
//     %LOCALAPPDATA%\IntelliAttend\Backup\v{previousVersion}/
//
//   The backup lives OUTSIDE the application install directory (Phase 1
//   isolation, via [InstallPaths.backupDir]) so a rollback that moves/rewrites
//   the app directory can never delete the backup it is about to restore.
//
//   If [UpdateHealthMonitor] detects a crash loop for the new version, it
//   calls [rollbackToPrevious]. This:
//     1. Deletes the current (broken) install directory.
//     2. Copies the backup back to the install directory.
//     3. Wipes UpdateHealth state except LastStableVersion.
//     4. Exits the current process so the OS re-launches the old version.
//
//   After 3 successful starts of the new version, the backup is deleted and
//   the version is marked "stable".
// ─────────────────────────────────────────────────────────────────────────────
class UpdateHealthMonitor {
  UpdateHealthMonitor._();

  // ── Thresholds ────────────────────────────────────────────────────────────

  /// How many consecutive successful starts are needed before a version is
  /// considered "stable" and the rollback backup is deleted.
  static const int _requiredStableStarts = 3;

  // ── State ─────────────────────────────────────────────────────────────────

  /// The current installed version as read from [PackageInfo].
  static Version _currentVersion = Version.zero;

  /// The previous version (before the most recent update).
  static Version _previousVersion = Version.zero;

  /// Health status of the current version.
  static UpdateHealthStatus _status = UpdateHealthStatus.stable;

  /// How many consecutive successful starts of the current version.
  static int _stableStartups = 0;

  /// The last version that achieved "stable" status.
  static Version _lastStableVersion = Version.zero;

  /// Total rollbacks ever performed (for diagnostics).
  static int _rollbackCount = 0;

  /// Path to the backup of the previous install, if any.
  static String? _backupPath;

  /// Whether we are mid-rollback (prevents re-entrance).
  static bool _isRollingBack = false;

  /// Test seam: override the app directory resolved by [_getAppDirectory]
  /// so backup scenarios are hermetic and fast in the validation harness.
  @visibleForTesting
  static Directory? testAppDirectoryOverride;

  // ── Initialisation (called early in main.dart) ───────────────────────────

  /// Initialise health state from registry.
  ///
  /// Must be called *after* [AutoUpdater.init] so [_currentVersion] is set,
  /// but *before* the app builds its UI (so crash detection happens early).
  ///
  /// Returns `true` if a rollback was just performed and the app should show
  /// a recovery message. Returns `false` for normal startup.
  static Future<bool> init(Version installedVersion) async {
    _currentVersion = installedVersion;
    _loadFromRegistry();

    // Check if this is a first launch after an update (version changed).
    final isNewVersion =
        _previousVersion > Version.zero && _currentVersion != _previousVersion;

    if (isNewVersion) {
      Log.i('[UpdateHealth] Detected version change: '
          '$_previousVersion → $_currentVersion');

      // Reset startup counter — this is a fresh version.
      _status = UpdateHealthStatus.pending;
      _stableStartups = 0;
      _saveToRegistry();
    }

    // If there's a backup from a previous update and we've been stable,
    // clean it up.
    if (_status == UpdateHealthStatus.stable && _backupPath != null) {
      _cleanupBackup();
    }

    Log.d('[UpdateHealth] init: v=$_currentVersion '
        'prev=$_previousVersion status=$_status '
        'starts=$_stableStartups rollbacks=$_rollbackCount');

    return _status == UpdateHealthStatus.rollingBack;
  }

  // ── Mark startup as completed (called from startBackgroundProtocols) ─────

  /// Called after a successful startup sequence completes.
  ///
  /// Increments the stable-startup counter. When the counter reaches
  /// [_requiredStableStarts], the version is marked "stable" and the
  /// rollback backup is deleted.
  static Future<void> markStartupSuccessful() async {
    _stableStartups++;
    Log.d(
        '[UpdateHealth] Successful startup #$_stableStartups for v$_currentVersion');

    if (_stableStartups >= _requiredStableStarts) {
      _status = UpdateHealthStatus.stable;
      _lastStableVersion = _currentVersion;
      _cleanupBackup();

      Log.i('[UpdateHealth] Version $_currentVersion marked STABLE');

      // Report success to server (fire-and-forget).
      _reportUpdateStatus(UpdateReportStatus.completed);
    }

    _saveToRegistry();
  }

  // ── Rollback detection ────────────────────────────────────────────────────

  /// Called when [StartupService] detects a crash loop.
  ///
  /// If the crash loop is happening on a version that was just installed
  /// (status == pending), this triggers an automatic rollback.
  ///
  /// Returns `true` if rollback was initiated, `false` if the crash is not
  /// related to an update.
  static Future<bool> handleCrashLoopDetected() async {
    if (_status != UpdateHealthStatus.pending) {
      Log.w('[UpdateHealth] Crash loop detected but version $_currentVersion '
          'is not in pending state (status=$_status) — no rollback');
      return false;
    }

    Log.w('[UpdateHealth] Crash loop on pending version $_currentVersion — '
        'triggering rollback');

    await _performRollback();
    return true;
  }

  // ── Pre-update backup (called by AutoUpdater before install) ─────────────

  /// Copy the current installation to a backup directory so we can roll back
  /// if the new version crashes.
  ///
  /// Called by [AutoUpdater] *before* downloading / installing the new MSI.
  /// Returns `true` if a recoverable backup was created. Returns `false` if
  /// the backup could not be produced — the caller MUST abort the update,
  /// because proceeding without rollback capability is a Phase 1 validation
  /// failure (never update without a recoverable backup).
  static Future<bool> preserveCurrentInstall(
      Version currentVersion, String? downloadUrl, String? sha256) async {
    try {
      final appDir = await _getAppDirectory();
      if (appDir == null) {
        Log.e('[UpdateHealth] Cannot backup — app directory unknown');
        return false;
      }

      // Use InstallPaths.backupDir for consistent backup location.
      final backupDir = Directory(
          '${InstallPaths.backupDir}\\v$currentVersion');
      if (await backupDir.exists()) {
        // Remove stale backup from a previous failed update.
        await backupDir.delete(recursive: true);
      }

      // Copy recursively (this may take a few seconds on large installs).
      await _copyDirectory(appDir, backupDir);
      _backupPath = backupDir.path;

      // Record pre-update state in registry.
      _previousVersion = currentVersion;
      _status = UpdateHealthStatus.pending;
      _stableStartups = 0;

      _saveToRegistry();

      Log.i('[UpdateHealth] Backup created: ${backupDir.path} '
          '(v$currentVersion)');
      return true;
    } catch (e) {
      Log.e('[UpdateHealth] Backup failed: $e — update will be ABORTED '
          '(no rollback capability)');
      return false;
    }
  }

  // ── Rollback execution ────────────────────────────────────────────────────

  /// Perform a rollback to the previous version.
  ///
  /// Steps:
  ///   1. Delete the current (broken) install directory.
  ///   2. Copy the backup back to the install directory.
  ///   3. Write rollback state to registry.
  ///   4. Exit the process (OS auto-start will relaunch the old version).
  static Future<void> _performRollback() async {
    if (_isRollingBack) {
      Log.w('[UpdateHealth] Rollback already in progress — skipping');
      return;
    }
    _isRollingBack = true;

    try {
      final appDir = await _getAppDirectory();
      if (appDir == null || _backupPath == null) {
        Log.e(
            '[UpdateHealth] Cannot rollback — app dir or backup path unknown');
        _reportUpdateStatus(UpdateReportStatus.failed);
        return;
      }

      // Ensure the backup actually exists.
      final backupDir = Directory(_backupPath!);
      if (!await backupDir.exists()) {
        Log.e('[UpdateHealth] Backup not found at $_backupPath — '
            'cannot rollback. Manual IT intervention required.');
        _reportUpdateStatus(UpdateReportStatus.failed);
        return;
      }

      if (Platform.isWindows) {
        _rollbackCount++;
        _status = UpdateHealthStatus.rollingBack;
        _saveToRegistry();

        _reportUpdateStatus(UpdateReportStatus.rolledBack);

        // Perform rollback directly in Dart (no PowerShell spawned)
        await _performRollbackDirect(appDir, backupDir);

        Log.i('[UpdateHealth] Rollback to v$_previousVersion scheduled '
            '(rollback #$_rollbackCount). Exiting so files can be restored.');
        await Future.delayed(const Duration(seconds: 1));
        exit(0);
      }

      // 1. Delete current app directory.
      Log.i('[UpdateHealth] Deleting current install: ${appDir.path}');
      await appDir.delete(recursive: true);

      // 2. Restore backup.
      Log.i(
          '[UpdateHealth] Restoring backup: ${backupDir.path} → ${appDir.path}');
      await backupDir.rename(appDir.path);

      // 3. Record rollback in persistent health state.
      _rollbackCount++;
      _status = UpdateHealthStatus.rollingBack;
      _saveToRegistry();

      _reportUpdateStatus(UpdateReportStatus.rolledBack);

      Log.i('[UpdateHealth] Rollback to v$_previousVersion complete '
          '(rollback #$_rollbackCount). Exiting for clean restart.');

      // 4. Exit so the OS / auto-start relaunches the old version.
      await Future.delayed(const Duration(seconds: 1));
      exit(0);
    } catch (e) {
      Log.e('[UpdateHealth] Rollback execution failed: $e');
      _reportUpdateStatus(UpdateReportStatus.failed);
    } finally {
      _isRollingBack = false;
    }
  }

  // ── Server reporting ──────────────────────────────────────────────────────

  /// Fire-and-forget report of update status to the server.
  static void _reportUpdateStatus(UpdateReportStatus status) {
    ApiService.reportUpdateStatus(
      currentVersion: _currentVersion.semantic,
      previousVersion: _previousVersion.semantic,
      status: status.name,
      stableStartups: _stableStartups,
      rollbackCount: _rollbackCount,
    ).catchError((e) {
      Log.d('[UpdateHealth] Status report failed (non-critical): $e');
    });
  }

  // ── Registry I/O ──────────────────────────────────────────────────────────

  /// Load persisted health state from the JSON file.
  static void _loadFromRegistry() {
    try {
      final file = _prefsFile;
      if (file.existsSync()) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _previousVersion = _parseVersion(json['previous_version']);
        _status = UpdateHealthStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => UpdateHealthStatus.stable,
        );
        _stableStartups = json['stable_startups'] as int? ?? 0;
        _lastStableVersion = _parseVersion(json['last_stable_version']);
        _rollbackCount = json['rollback_count'] as int? ?? 0;
        _backupPath = json['backup_path']?.toString();
      }
    } catch (e) {
      Log.w('[UpdateHealth] Failed to load state: $e');
    }
  }

  /// Persist health state to the JSON file in the app data directory.
  static void _saveToRegistry() {
    try {
      final data = {
        'previous_version': _previousVersion.semantic,
        'status': _status.name,
        'stable_startups': _stableStartups,
        'last_stable_version': _lastStableVersion.semantic,
        'rollback_count': _rollbackCount,
        if (_backupPath != null) 'backup_path': _backupPath,
      };
      // Ensure the Data\ directory exists — on a fresh install it may not yet
      // (the pipeline creates it later), and a missing parent would silently
      // drop the persisted health state.
      _prefsFile.parent.createSync(recursive: true);
      _prefsFile.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('[UpdateHealth] Failed to save state: $e');
    }
  }

  static File get _prefsFile => InstallPaths.updateHealthFileInstance;

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Find the current app installation directory.
  static Future<Directory?> _getAppDirectory() async {
    final override = testAppDirectoryOverride;
    if (override != null) return override;
    try {
      if (Platform.isWindows) {
        return File(Platform.resolvedExecutable).parent;
      }
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }

  /// Performs rollback directly in Dart without spawning PowerShell.
  /// Moves current app to failed dir, restores backup, launches restored exe.
  static Future<void> _performRollbackDirect(Directory appDir, Directory backupDir) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final failedDir =
        '${appDir.parent.path}\\${appDir.uri.pathSegments.last}_failed_$timestamp';
    final exeName =
        Platform.resolvedExecutable.split(Platform.pathSeparator).last;
    final restoredExe = '${appDir.path}\\$exeName';

    // Wait a moment for current process to be ready for file operations
    await Future.delayed(const Duration(seconds: 2));

    try {
      // Move current app directory to failed dir
      if (await appDir.exists()) {
        await appDir.rename(failedDir);
        Log.i('[UpdateHealth] Moved current app to: $failedDir');
      }

      // Restore backup to app directory
      if (await backupDir.exists()) {
        await backupDir.rename(appDir.path);
        Log.i('[UpdateHealth] Restored backup to: ${appDir.path}');
      }

      // Launch the restored executable
      if (await File(restoredExe).exists()) {
        await Process.start(restoredExe, ['--rollback-recovered']);
        Log.i('[UpdateHealth] Launched restored executable: $restoredExe');
      }
    } catch (e) {
      Log.e('[UpdateHealth] Rollback failed: $e');
      // Log error to temp file for diagnostics
      final logFile = File('${Directory.systemTemp.path}\\intelliattend_rollback_error.log');
      await logFile.writeAsString('[$timestamp] $e\n', mode: FileMode.append);
    }
  }

  /// Recursive directory copy.
  static Future<void> _copyDirectory(
      Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final entityName = entity.uri.pathSegments.last;
      if (entity is File) {
        await entity.copy('${destination.path}\\$entityName');
      } else if (entity is Directory) {
        final subDest = Directory('${destination.path}\\$entityName');
        await _copyDirectory(entity, subDest);
      }
    }
  }

  /// Delete the backup directory and clear backup path from registry.
  static void _cleanupBackup() {
    if (_backupPath == null) return;
    try {
      final backupDir = Directory(_backupPath!);
      if (backupDir.existsSync()) {
        backupDir.deleteSync(recursive: true);
        Log.i('[UpdateHealth] Backup cleaned up: $_backupPath');
      }
    } catch (e) {
      Log.w('[UpdateHealth] Backup cleanup failed: $e');
    }
    _backupPath = null;
  }

  static Version _parseVersion(dynamic value) {
    if (value == null) return Version.zero;
    try {
      return Version.parse(value.toString());
    } catch (_) {
      return Version.zero;
    }
  }

  // ── Public accessors ──────────────────────────────────────────────────────

  /// The current version running on this board.
  static Version get currentVersion => _currentVersion;

  /// The previous version (before the most recent update).
  static Version get previousVersion => _previousVersion;

  /// Health status of the current version.
  static UpdateHealthStatus get status => _status;

  /// Whether this version is still in the "pending" (unstable) state.
  static bool get isPendingStabilisation =>
      _status == UpdateHealthStatus.pending;

  /// Whether a rollback has been performed (diagnostic).
  static int get rollbackCount => _rollbackCount;

  /// The last version that was marked "stable".
  static Version get lastStableVersion => _lastStableVersion;
}

// ── Enums ───────────────────────────────────────────────────────────────────

/// Health status of the currently installed version.
enum UpdateHealthStatus {
  /// Version has been running successfully for >= N starts.
  stable,

  /// Version was just installed; still in the observation window.
  pending,

  /// Version was rolled back after a crash loop.
  rollingBack,

  /// Update failed and rollback was not possible.
  failed,
}

/// Status reported to the server for dashboard tracking.
enum UpdateReportStatus {
  completed,
  failed,
  rolledBack,
}
