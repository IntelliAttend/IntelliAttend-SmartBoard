import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils/logger.dart';
import '../core/utils/version.dart';
import '../models/remote_config.dart';
import 'update_health_monitor.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateState
//
// Reflects where the board is in the update lifecycle. Exposed via
// [AutoUpdater.state] so the UI layer can show an appropriate overlay.
// ─────────────────────────────────────────────────────────────────────────────
enum UpdateState {
  /// No update in progress. This is the default / idle state.
  idle,

  /// A new version was detected and the board is downloading the MSI.
  downloading,

  /// Download complete, verifying file integrity (SHA-256).
  verifying,

  /// Verification passed, running msiexec to install.
  installing,

  /// Installation succeeded — app will exit momentarily (msiexec may request
  /// a reboot or the board will relaunch itself).
  completed,

  /// Something went wrong. [UpdateProgress.error] contains details.
  failed,
}

// ─────────────────────────────────────────────────────────────────────────────
// UpdateProgress
//
// Data class sent to the UI overlay whenever the state changes.
// ─────────────────────────────────────────────────────────────────────────────
class UpdateProgress {
  final UpdateState state;
  final String targetVersion;
  final double fraction; // 0.0 – 1.0 (download progress)
  final String? error;
  final bool force;

  const UpdateProgress({
    required this.state,
    required this.targetVersion,
    this.fraction = 0.0,
    this.error,
    this.force = false,
  });

  /// Human-readable status line for the overlay UI.
  String get statusText {
    switch (state) {
      case UpdateState.downloading:
        final pct = (fraction * 100).toStringAsFixed(0);
        return 'Downloading update v$targetVersion... $pct%';
      case UpdateState.verifying:
        return 'Verifying update v$targetVersion...';
      case UpdateState.installing:
        return 'Installing v$targetVersion — please wait...';
      case UpdateState.completed:
        return 'Update v$targetVersion installed. Restarting...';
      case UpdateState.failed:
        return error ?? 'Update failed';
      case UpdateState.idle:
        return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoUpdater
//
// Singleton service that orchestrates the binary auto-update flow:
//
//   1. [checkForUpdate] compares the installed version (from PackageInfo)
//      against the server-provided [UpdateManifest].
//   2. If an update is needed and this board is in the rollout cohort,
//      the MSI is stream-downloaded to a temp file with progress.
//   3. The SHA-256 hash is verified against the manifest.
//   4. msiexec is invoked silently to install the MSI.
//   5. The process exits; the installer (or Windows auto-start) relaunches
//      the app at the new version.
//
// ── Thread model ────────────────────────────────────────────────────────────
// All public methods are designed to be called from the main isolate (UI
// thread). Internally, file I/O and HTTP streaming happen on Isolate I/O
// workers via `dart:io` — the event loop is not blocked.
//
// ── Rollout safety ──────────────────────────────────────────────────────────
// The manifest includes [rolloutPercentage]. The board uses a deterministic
// hash of its board ID to decide whether it is in the canary cohort. This
// allows staged rollouts (e.g. 5 % → 25 % → 100 %).
// ─────────────────────────────────────────────────────────────────────────────
class AutoUpdater {
  AutoUpdater._(); // prevent instantiation

  // ── State ──────────────────────────────────────────────────────────────────

  /// The current update progress. `null` when idle, populated during active
  /// update. The UI layer listens to this notifier to show/hide the overlay.
  static final ValueNotifier<UpdateProgress?> progress =
      ValueNotifier<UpdateProgress?>(null);

  /// Cached package info so we don't call the platform channel on every check.
  static PackageInfo? _packageInfo;

  static String? _boardId;

  /// The parsed installed version, available after [init] is called.
  static Version get installedVersion => _installedVersion;

  // ── Thresholds ────────────────────────────────────────────────────────────

  /// HTTP client timeout for downloads.
  static const Duration _downloadTimeout = Duration(minutes: 10);

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Must be called once at startup before [checkForUpdate].
  static Future<void> init({String? boardId}) async {
    _boardId = boardId;
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      Log.w('[AutoUpdater] Could not read package info: $e');
    }
    Log.d('[AutoUpdater] Initialised (version: $_installedVersion)');
  }

  // ── Update check ──────────────────────────────────────────────────────────

  /// Check whether an update is available and, if so, start the update flow.
  ///
  /// This is typically called:
  ///   - At startup (after heartbeat has fetched a config).
  ///   - Whenever a new [RemoteConfig] arrives (on heartbeat).
  ///
  /// Returns `true` if an update was started, `false` if no update is needed
  /// or the board is not in the rollout cohort.
  static Future<bool> checkForUpdate(UpdateManifest manifest) async {
    // Guard: don't start a second update while one is running.
    if (progress.value != null && progress.value!.state != UpdateState.failed) {
      Log.d('[AutoUpdater] Update already in progress — ignoring');
      return false;
    }

    final installed = _installedVersion;
    final required = manifest.parsedMinimum;

    Log.d('[AutoUpdater] Installed=$installed, required=${manifest.minimumVersion}');

    // Already up to date.
    if (installed >= required) {
      Log.d('[AutoUpdater] Already at v$installed — no update needed');
      return false;
    }

    // No download URL — can't update.
    final url = manifest.downloadUrl;
    if (url == null || url.isEmpty) {
      Log.w('[AutoUpdater] Update needed but no download_url in manifest');
      return false;
    }

    // Check rollout cohort.
    if (_boardId != null && !manifest.includesBoard(_boardId!)) {
      Log.d('[AutoUpdater] Board $_boardId not in rollout cohort '
          '(${manifest.rolloutPercentage}%) — skipping');
      return false;
    }

    // Check disk space.
    if (!await _hasEnoughDiskSpace()) {
      Log.e('[AutoUpdater] Insufficient disk space for update');
      if (manifest.force) {
        // Even a forced update can't proceed without disk space.
        progress.value = UpdateProgress(
          state: UpdateState.failed,
          targetVersion: manifest.minimumVersion,
          error: 'Insufficient disk space. Free at least 200 MB.',
          force: manifest.force,
        );
      }
      return false;
    }

    // Start the update.
    Log.i('[AutoUpdater] Update available: v$installed → v${manifest.minimumVersion} '
        '(${manifest.force ? "forced" : "optional"})');

    _startUpdate(manifest, installed);
    return true;
  }

  // ── Internal: the actual update pipeline ──────────────────────────────────

  static Future<void> _startUpdate(
      UpdateManifest manifest, Version currentVersion) async {
    final targetVersion = manifest.minimumVersion;
    final url = manifest.downloadUrl!;

    // ── 0. Backup current installation ───────────────────────────────────────
    //
    // Before modifying the installed binaries, preserve the current version
    // so [UpdateHealthMonitor] can perform a clean rollback if the new
    // version crashes.
    await UpdateHealthMonitor.preserveCurrentInstall(
      currentVersion,
      url,
      manifest.sha256,
    );

    // ── 1. Download ──────────────────────────────────────────────────────────

    final tempDir = await getTemporaryDirectory();
    final msiPath = '${tempDir.path}\\IASB-$targetVersion.msi';
    final msiFile = File(msiPath);

    // Remove any partially-downloaded file from a previous attempt.
    if (await msiFile.exists()) {
      await msiFile.delete();
    }

    progress.value = UpdateProgress(
      state: UpdateState.downloading,
      targetVersion: targetVersion,
      force: manifest.force,
    );

    try {
      await _downloadWithProgress(url, msiPath, manifest.force);
    } catch (e) {
      Log.e('[AutoUpdater] Download failed: $e');
      progress.value = UpdateProgress(
        state: UpdateState.failed,
        targetVersion: targetVersion,
        error: 'Download failed: ${_userFriendlyError(e)}',
        force: manifest.force,
      );
      // Clean up partial file.
      if (await msiFile.exists()) {
        await msiFile.delete();
      }
      return;
    }

    // ── 2. Verify SHA-256 ────────────────────────────────────────────────────

    progress.value = UpdateProgress(
      state: UpdateState.verifying,
      targetVersion: targetVersion,
      fraction: 1.0,
      force: manifest.force,
    );

    if (manifest.sha256 != null && manifest.sha256!.isNotEmpty) {
      try {
        final ok = await _verifyHash(msiPath, manifest.sha256!);
        if (!ok) {
          throw Exception(
              'SHA-256 mismatch. Expected ${manifest.sha256}, got computed hash');
        }
        Log.i('[AutoUpdater] Hash verification passed');
      } catch (e) {
        Log.e('[AutoUpdater] Hash verification failed: $e');
        progress.value = UpdateProgress(
          state: UpdateState.failed,
          targetVersion: targetVersion,
          error: 'Integrity check failed. The downloaded file may be corrupted.',
          force: manifest.force,
        );
        await msiFile.delete();
        return;
      }
    } else {
      Log.w('[AutoUpdater] No SHA-256 in manifest — skipping verification');
    }

    // ── 3. Install ───────────────────────────────────────────────────────────

    progress.value = UpdateProgress(
      state: UpdateState.installing,
      targetVersion: targetVersion,
      fraction: 1.0,
      force: manifest.force,
    );

    try {
      await _installMsi(msiPath);
    } catch (e) {
      Log.e('[AutoUpdater] Installation failed: $e');
      progress.value = UpdateProgress(
        state: UpdateState.failed,
        targetVersion: targetVersion,
        error: 'Installation failed: ${_userFriendlyError(e)}',
        force: manifest.force,
      );
      return;
    }

    // ── 4. Done ──────────────────────────────────────────────────────────────

    progress.value = UpdateProgress(
      state: UpdateState.completed,
      targetVersion: targetVersion,
      fraction: 1.0,
      force: manifest.force,
    );

    Log.i('[AutoUpdater] Update to v$targetVersion installed. Exiting.');

    // Small delay so the UI overlay can show the "completed" state.
    await Future.delayed(const Duration(seconds: 2));

    // Exit the app. The MSI installer (via registry auto-start) will relaunch
    // the new version.
    _exitApp();
  }

  // ── Download with progress ────────────────────────────────────────────────

  /// Stream the MSI from [url] to [destination], updating [progress] along
  /// the way. Uses chunked transfer to avoid loading the entire file into
  /// memory — critical on low-RAM kiosk hardware.
  static Future<void> _downloadWithProgress(
      String url, String destination, bool force) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      // Suggest a reasonable timeout — the download may be large.
      final response = await client
          .send(request)
          .timeout(_downloadTimeout);

      if (response.statusCode != 200) {
        throw HttpException(
            'Server returned ${response.statusCode} for $url');
      }

      final contentLength = response.contentLength ?? 0;
      final file = File(destination);
      final sink = file.openWrite();

      int bytesReceived = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        bytesReceived += chunk.length;

        if (contentLength > 0) {
          progress.value = UpdateProgress(
            state: UpdateState.downloading,
            targetVersion: progress.value?.targetVersion ?? '?',
            fraction: bytesReceived / contentLength,
            force: force,
          );
        }
      }

      await sink.flush();
      await sink.close();

      Log.i('[AutoUpdater] Downloaded $bytesReceived bytes to $destination');
    } finally {
      client.close();
    }
  }

  // ── Hash verification ─────────────────────────────────────────────────────

  /// Compute SHA-256 of the file at [path] and compare it (hex) to [expected].
  static Future<bool> _verifyHash(String path, String expected) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    return hash.toLowerCase() == expected.toLowerCase();
  }

  // ── MSI installation ──────────────────────────────────────────────────────

  /// Invoke `msiexec` to install the MSI at [msiPath] in silent mode.
  ///
  /// Flags:
  ///   `/quiet`       — no UI, no prompts
  ///   `/norestart`   — don't force a reboot (the board will relaunch itself)
  ///   `/log`         — write install log for diagnostics
  ///
  /// Throws on non-zero exit code.
  static Future<void> _installMsi(String msiPath) async {
    if (!Platform.isWindows) {
      Log.w('[AutoUpdater] MSI install skipped (not Windows)');
      return;
    }

    final logPath = '${Directory.systemTemp.path}\\IASB_install_${DateTime.now().millisecondsSinceEpoch}.log';

    Log.i('[AutoUpdater] Installing: msiexec /i "$msiPath" /quiet /norestart /log "$logPath"');

    final result = await Process.run(
      'msiexec',
      ['/i', msiPath, '/quiet', '/norestart', '/log', logPath],
    ).timeout(const Duration(minutes: 5));

    if (result.exitCode != 0) {
      // Exit code 3010 means "reboot required" — which is acceptable.
      if (result.exitCode == 3010) {
        Log.i('[AutoUpdater] msiexec exit code 3010 (reboot required) — continuing');
        return;
      }
      throw Exception(
          'msiexec exited with code ${result.exitCode}\n'
          'stdout: ${result.stdout}\n'
          'stderr: ${result.stderr}\n'
          'Log: $logPath');
    }

    Log.i('[AutoUpdater] msiexec completed successfully');
  }

  // ── App exit after install ────────────────────────────────────────────────

  /// Terminate the current process. The MSI installer sets up the registry
  /// auto-start key, so the app will launch again automatically (either
  /// immediately after install or on the next user login).
  static void _exitApp() {
    Log.i('[AutoUpdater] Exiting current process for update to take effect.');
    // Small delay to let the progress notification reach the UI.
    Future.delayed(const Duration(milliseconds: 500), () {
      exit(0);
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Current installed version, parsed from [PackageInfo].
  static Version get _installedVersion {
    if (_packageInfo == null) return Version.zero;
    try {
      return Version.parse('${_packageInfo!.version}+${_packageInfo!.buildNumber}');
    } catch (_) {
      return Version.zero;
    }
  }

  /// Best-effort disk space check. Currently returns true (assumes enough
  /// space). On Windows a future implementation can use `GetDiskFreeSpaceExW`
  /// via `dart:ffi` for accurate reporting.
  static Future<bool> _hasEnoughDiskSpace() async {
    return true;
  }

  static String _userFriendlyError(Object error) {
    final msg = error.toString();
    if (msg.contains('timed out') || msg.contains('Timeout')) {
      return 'Download timed out. Check network connectivity.';
    }
    if (msg.contains('Connection refused') || msg.contains('SocketException')) {
      return 'Could not reach update server. Check network connectivity.';
    }
    if (msg.contains('404')) {
      return 'Update file not found on server. Contact IT.';
    }
    return 'An unexpected error occurred.';
  }
}
