import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../core/config/app_config.dart';
import '../core/config/install_paths.dart';
import '../core/observability/observability_manager.dart';
import '../core/update/manifest_policy.dart';
import '../core/update/manifest_validator.dart';
import '../core/utils/logger.dart';
import '../core/utils/version.dart';
import '../models/remote_config.dart';
import 'update_agent_launcher.dart';
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

  /// A new version was detected and the board is downloading the installer.
  downloading,

  /// Download complete, verifying file integrity (SHA-256).
  verifying,

  /// Verification passed, running the update agent to install.
  installing,

  /// Installation succeeded — app will exit momentarily (the installer may
  /// request a reboot or the board will relaunch itself).
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
  final DateTime startedAt;

  UpdateProgress({
    required this.state,
    required this.targetVersion,
    this.fraction = 0.0,
    this.error,
    this.force = false,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

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
//      the installer is stream-downloaded to a temp file with progress.
//   3. The SHA-256 hash is verified against the manifest.
//   4. The update agent is launched to install the update.
//   5. The process exits; the installer relaunches the app at the new version.
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

  /// The release channel this board belongs to (e.g. "stable", "beta").
  static String _boardChannel = 'stable';

  /// HMAC-SHA256 secret key for manifest signature verification.
  /// Null disables signature checking (dev mode only).
  static String? _hmacSecretKey;

  /// Timestamp when AutoUpdater was initialized. Used to skip checks
  /// during the first 30s of startup (prevents overlay on boot).
  static DateTime? _initializedAt;

  /// Effective initialization time — [debugInitializedAt] wins when set.
  static DateTime? get _effectiveInitializedAt => debugInitializedAt ?? _initializedAt;

  /// The parsed installed version, available after [init] is called.
  static Version get installedVersion => _installedVersion;

  // ── Available update (for Settings button) ────────────────────────────────

  /// Notifies UI when a newer version is available but not yet applied.
  /// The Settings screen listens to this to show an "Update Available" button.
  /// Cleared on successful install; survives dismiss so user can retry later.
  static final ValueNotifier<UpdateManifest?> availableUpdate =
      ValueNotifier<UpdateManifest?>(null);

  // ── Dismiss support (user-initiated cancel) ───────────────────────────────

  /// Set to `true` when the user taps Dismiss.
  static bool _dismissRequested = false;

  /// Active HTTP client during download — closed on dismiss to abort the stream.
  static http.Client? _activeDownloadClient;

  /// Path of the file being downloaded — deleted on dismiss.
  static String? _activeDownloadPath;

  // ── Circuit Breaker ───────────────────────────────────────────────────────

  /// Consecutive failures for the current version fingerprint.
  static int _consecutiveFailures = 0;

  /// Version fingerprint for which consecutive failures are counted.
  static String? _failedVersionFingerprint;

  /// Maximum consecutive failures before the circuit opens (auto-retry stops).
  static const int _maxConsecutiveFailures = 3;

  // ── Thresholds ────────────────────────────────────────────────────────────

  /// HTTP client timeout for downloads.
  static const Duration _downloadTimeout = Duration(minutes: 10);

  // ── Test seams (used by the Phase 1 validation harness) ──────────────────
  //
  // These are `@visibleForTesting` injection points so the validation suite
  // can drive the real pipeline deterministically without a device, a real
  // update server, or a real detached update agent.

  /// Overrides the installed version reported by [installedVersion].
  @visibleForTesting
  static String? testInstalledVersionOverride;

  /// Overrides [_initializedAt] so the 30-second startup guard can be
  /// satisfied immediately in validation scenarios.
  @visibleForTesting
  static DateTime? debugInitializedAt;

  /// Overrides the disk-space probe so tests can simulate full/low/fail-open
  /// disks deterministically (the real probe shells out to PowerShell).
  @visibleForTesting
  static Future<bool> Function()? diskSpaceProbeOverride;

  /// Overrides the detached-agent launch so tests can capture launch
  /// arguments and simulate success/failure without spawning a process.
  @visibleForTesting
  static Future<bool> Function({
    required String installerPath,
    required String targetVersion,
    required String expectedSha256,
    required String logPath,
  })? agentLauncherOverride;

  /// When false, the pipeline stops before `exit(0)` so the test process
  /// survives a completed update.
  @visibleForTesting
  static bool debugExitOnCompletion = true;

  /// Overrides the download timeout (default 10 minutes) so timeout
  /// scenarios finish quickly.
  @visibleForTesting
  static Duration downloadTimeoutOverride = _downloadTimeout;

  /// Whether an update pipeline is currently executing. Closes the TOCTOU
  /// window between two near-simultaneous `checkForUpdate` calls: a
  /// synchronous claim is taken immediately before [ _startUpdate] runs, so
  /// interleaved calls can never both enter the pipeline even before
  /// [progress] is populated.
  static bool _updatePipelineInFlight = false;

  /// True while a pipeline is executing (validation harness polls this).
  @visibleForTesting
  static bool get debugUpdateInFlight => _updatePipelineInFlight;

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Must be called once at startup before [checkForUpdate].
  static Future<void> init({
    String? boardId,
    String boardChannel = 'stable',
    String? hmacSecretKey,
  }) async {
    _boardId = boardId;
    _boardChannel = boardChannel;
    _hmacSecretKey = hmacSecretKey;
    _initializedAt = DateTime.now();
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      Log.w('[AutoUpdater] Could not read package info: $e');
    }
    Log.d('[AutoUpdater] Initialised (version: $_installedVersion, '
        'channel: $_boardChannel)');
  }

  // ── Update check ──────────────────────────────────────────────────────────

  /// Tracks the last manifest fingerprint checked to avoid re-processing the
  /// same manifest when heartbeat keeps delivering an unchanged config.
  ///
  /// Fingerprint includes [minimumVersion], [force], and [rolloutPercentage] so
  /// that admin changes (e.g. escalating force from false→true for the same
  /// version) re-trigger the update pipeline.
  static String? _lastCheckedManifestFingerprint;

  /// Check whether an update is available and, if so, start the update flow.
  ///
  /// This is typically called:
  ///   - At startup (after heartbeat has fetched a config).
  ///   - Whenever a new [RemoteConfig] arrives (on heartbeat).
  ///
  /// Returns `true` if an update was started, `false` if no update is needed
  /// or the board is not in the rollout cohort.
  /// If [silent] is true, failures are logged but no overlay is shown.
  static Future<bool> checkForUpdate(UpdateManifest manifest, {bool silent = false}) async {
    // Guard: Auto-update is currently disabled. Will be re-enabled in a
    // future release. To opt back in, set ENABLE_AUTO_UPDATE=true in .env.
    if (!AppConfig.enableAutoUpdate) {
      Log.i('[AutoUpdater] Auto-update disabled via config — skipping');
      return false;
    }

    // Guard: AutoUpdater.init() must be called before checkForUpdate
    // (unless the validation harness injects an installed-version override).
    if (_packageInfo == null && testInstalledVersionOverride == null) {
      Log.w('[AutoUpdater] checkForUpdate skipped — AutoUpdater not yet initialized');
      return false;
    }

    // Guard: skip updates during first 30s of startup to prevent overlay on boot.
    final initializedAt = _effectiveInitializedAt;
    if (initializedAt != null &&
        DateTime.now().difference(initializedAt) < const Duration(seconds: 30)) {
      Log.d('[AutoUpdater] Skipping update check — app still starting up');
      return false;
    }

    final installed = _installedVersion;
    final required = manifest.parsedMinimum;
    final forceUpdate = manifest.force;

    Log.i('[AutoUpdater] checkForUpdate: installed=$installed, required=${manifest.minimumVersion}, force=$forceUpdate');

    // Dedup: skip if we already processed this exact manifest fingerprint.
    // Fingerprint includes version + force + rollout so admin changes to
    // force/rollout for the same version re-trigger the check.
    final fingerprint = '${manifest.minimumVersion}|${manifest.force}|${manifest.rolloutPercentage}';
    if (fingerprint == _lastCheckedManifestFingerprint) {
      Log.d('[AutoUpdater] Manifest $fingerprint already checked — skipping');
      return false;
    }
    _lastCheckedManifestFingerprint = fingerprint;

    // ── Phase 4: Policy Validation ──────────────────────────────────────────
    //
    // Before doing anything else, ask ManifestValidator whether this
    // manifest is allowed to install on this machine. This covers:
    //   - Schema version compatibility
    //   - Manifest expiry
    //   - Release channel enforcement
    //   - Version range / downgrade protection
    //   - OS compatibility
    //   - Rollout cohort inclusion
    //   - HMAC signature verification
    final policy = ManifestPolicy(
      boardChannel: _boardChannel,
      windowsVersion: UpdateManifest.currentWindowsVersion,
      installedVersion: _installedVersion.toString(),
      boardId: _boardId ?? 'unknown',
      hmacSecretKey: _hmacSecretKey,
    );
    final validation = ManifestValidator.check(manifest, policy);
    if (validation.denied) {
      Log.w('[AutoUpdater] Manifest denied by policy: ${validation.firstReason}');
      ObservabilityManager.updateBreadcrumb('denied',
          detail: validation.firstReason);
      return false;
    }

    // ── Guard: circuit breaker ────────────────────────────────────────────
    //
    // After [maxConsecutiveFailures] consecutive failures for the same version
    // fingerprint, auto-retry is blocked. The user can still retry from the
    // Settings screen, or an admin can re-push via WebSocket.
    if (_consecutiveFailures >= _maxConsecutiveFailures &&
        fingerprint == _failedVersionFingerprint) {
      Log.w('[AutoUpdater] Circuit breaker open for $fingerprint — skipping auto-retry');
      availableUpdate.value = manifest;
      return false;
    }

    // ── Guard: in-progress / failed state ──────────────────────────────────
    //
    // Don't start a second update while one is running.
    // - Non-terminal states (downloading/verifying/installing): block unless
    //   force=true AND stuck >5 min.
    // - Failed state: block unless force=true (admin intent).
    if (_updatePipelineInFlight) {
      Log.w('[AutoUpdater] Update pipeline already in flight — ignoring '
          'concurrent update request');
      return false;
    }
    if (progress.value != null) {
      final ps = progress.value!.state;
      final elapsed = DateTime.now().difference(progress.value!.startedAt);

      if (ps == UpdateState.downloading ||
          ps == UpdateState.verifying ||
          ps == UpdateState.installing) {
        if (forceUpdate && elapsed > const Duration(minutes: 5)) {
          Log.w('[AutoUpdater] Force update with stuck progress '
              '(${elapsed.inMinutes}min) — resetting');
          progress.value = null;
        } else if (!forceUpdate) {
          Log.d('[AutoUpdater] Update already in progress — ignoring');
          return false;
        }
      }
    }

    // Already up to date (build-number-aware comparison).
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

    // Check disk space.
    if (!await _hasEnoughDiskSpace()) {
      Log.e('[AutoUpdater] Insufficient disk space for update');
      progress.value = UpdateProgress(
        state: UpdateState.failed,
        targetVersion: manifest.minimumVersion,
        error: 'Insufficient disk space. Free at least 200 MB.',
        force: forceUpdate,
      );
      return false;
    }

    // Notify UI that an update is available (for Settings button).
    availableUpdate.value = manifest;

    // Start the update.
    Log.i('[AutoUpdater] Update available: v$installed → v${manifest.minimumVersion} '
        '(${manifest.force ? "forced" : "optional"})');

    // Single-flight claim. Synchronous check+set with no await between, so
    // two interleaved checkForUpdate calls can never both enter the pipeline
    // (the TOCTOU window before [progress] is populated is now closed).
    if (_updatePipelineInFlight) {
      Log.w('[AutoUpdater] Update pipeline already in flight — ignoring');
      return false;
    }
    _updatePipelineInFlight = true;

    _startUpdate(manifest, installed, silent: silent);
    return true;
  }

  // ── Internal: the actual update pipeline ──────────────────────────────────

  static Future<void> _startUpdate(
      UpdateManifest manifest, Version currentVersion, {bool silent = false}) async {

    try {
      await _startUpdatePipeline(manifest, currentVersion, silent: silent);
      // Pipeline succeeded — reset circuit breaker and allow re-check.
      // Deliberately keep `_lastCheckedManifestFingerprint` so a replay of the
      // same manifest is deduplicated (the "already up to date" version guard
      // normally covers this after a real install; the fingerprint closes the
      // same-process replay window).
      _consecutiveFailures = 0;
      _failedVersionFingerprint = null;
    } catch (e) {
      Log.e('[AutoUpdater] Update pipeline failed unexpectedly: $e');
      _lastCheckedManifestFingerprint = null;
      _incrementCircuitBreaker(manifest);
    } finally {
      _updatePipelineInFlight = false;
    }
  }

  /// The actual update pipeline (download → verify → install → exit).
  /// Throws on any failure; the caller resets dedup state.
  static Future<void> _startUpdatePipeline(
      UpdateManifest manifest, Version currentVersion, {bool silent = false}) async {
    final targetVersion = manifest.minimumVersion;
    final url = manifest.downloadUrl!;

    // ── 0. Backup current installation ───────────────────────────────────────
    //
    // Before modifying the installed binaries, preserve the current version
    // so [UpdateHealthMonitor] can perform a clean rollback if the new
    // version crashes. This is FAIL-CLOSED: if the backup cannot be created,
    // the update is aborted rather than proceeding without rollback
    // capability (a requirement of the Phase 1 validation matrix).
    final backedUp = await UpdateHealthMonitor.preserveCurrentInstall(
      currentVersion,
      url,
      manifest.sha256,
    );
    if (!backedUp) {
      Log.e('[AutoUpdater] Backup failed — aborting update so rollback '
          'capability is never silently lost');
      progress.value = UpdateProgress(
        state: UpdateState.failed,
        targetVersion: targetVersion,
        error: 'Could not back up the current version. Update aborted.',
        force: manifest.force,
      );
      throw Exception('Backup failed; update aborted');
    }

    // ── 1. Download ──────────────────────────────────────────────────────────

    await InstallPaths.ensureDirectories();
    final installerPath = '${InstallPaths.updateDir}\\IASB-$targetVersion-Setup.exe';
    final installerFile = File(installerPath);

    // Remove any partially-downloaded file from a previous attempt.
    if (await installerFile.exists()) {
      await installerFile.delete();
    }

    progress.value = UpdateProgress(
      state: UpdateState.downloading,
      targetVersion: targetVersion,
      force: manifest.force,
    );

    // The SHA-256 of the downloaded bytes is computed incrementally during the
    // stream (never loading the whole installer into memory), and returned for
    // the verification step below — no post-download re-read of the file.
    String downloadedHash = '';

    try {
      downloadedHash =
          await _downloadWithProgress(url, installerPath, manifest.force);
      if (_dismissRequested) {
        _dismissRequested = false;
        if (await installerFile.exists()) {
          try {
            await installerFile.delete();
          } catch (_) {}
        }
        return;
      }
      Log.i('[AutoUpdater] Download complete. Computed SHA-256: $downloadedHash');
    } catch (e) {
      if (_dismissRequested) {
        _dismissRequested = false;
        if (await installerFile.exists()) {
          try {
            await installerFile.delete();
          } catch (_) {}
        }
        return;
      }
      Log.e('[AutoUpdater] Download failed: $e');
      if (!silent) {
        progress.value = UpdateProgress(
          state: UpdateState.failed,
          targetVersion: targetVersion,
          error: 'Download failed: ${_userFriendlyError(e)}',
          force: manifest.force,
        );
      }
      // Clean up partial file.
      if (await installerFile.exists()) {
        await installerFile.delete();
      }
      rethrow;
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
        if (!_matchesHash(downloadedHash, manifest.sha256!)) {
          throw Exception(
              'SHA-256 mismatch. Expected ${manifest.sha256}, got $downloadedHash');
        }
        Log.i('[AutoUpdater] Hash verification passed');
      } catch (e) {
        if (_dismissRequested) {
          _dismissRequested = false;
          return;
        }
        Log.e('[AutoUpdater] Hash verification failed: $e');
        progress.value = UpdateProgress(
          state: UpdateState.failed,
          targetVersion: targetVersion,
          error: 'Integrity check failed. The downloaded file may be corrupted.',
          force: manifest.force,
        );
        await installerFile.delete();
        rethrow;
      }
    } else {
      // SHA-256 is mandatory — reject updates without a hash.
      Log.e('[AutoUpdater] No SHA-256 in manifest — refusing to install unverified update');
      progress.value = UpdateProgress(
        state: UpdateState.failed,
        targetVersion: targetVersion,
        error: 'Update rejected: missing integrity hash. Contact IT.',
        force: manifest.force,
      );
      await installerFile.delete();
      throw Exception('Update rejected: manifest has no SHA-256 hash');
    }

    // ── 3. Launch Update Agent ──────────────────────────────────────────────

    progress.value = UpdateProgress(
      state: UpdateState.installing,
      targetVersion: targetVersion,
      fraction: 1.0,
      force: manifest.force,
    );

    final logPath =
        '${InstallPaths.logDir}\\update_${DateTime.now().millisecondsSinceEpoch}.log';

    final launched = agentLauncherOverride != null
        ? await agentLauncherOverride!(
            installerPath: installerPath,
            targetVersion: targetVersion,
            expectedSha256: manifest.sha256 ?? '',
            logPath: logPath,
          )
        : await UpdateAgentLauncher.launch(
            installerPath: installerPath,
            targetVersion: targetVersion,
            expectedSha256: manifest.sha256 ?? '',
            logPath: logPath,
          );

    if (!launched) {
      Log.e('[AutoUpdater] Failed to launch update agent');
      progress.value = UpdateProgress(
        state: UpdateState.failed,
        targetVersion: targetVersion,
        error: 'Failed to launch update agent. Try again later.',
        force: manifest.force,
      );
      // Throw so `_startUpdate` increments the circuit breaker. Without this,
      // a persistent launch failure (e.g. missing update_agent.exe) retried
      // every heartbeat forever, hammering the server with re-downloads.
      throw Exception('Failed to launch update agent');
    }

    // ── 4. Done ──────────────────────────────────────────────────────────────

    progress.value = UpdateProgress(
      state: UpdateState.completed,
      targetVersion: targetVersion,
      fraction: 1.0,
      force: manifest.force,
    );

    Log.i('[AutoUpdater] Agent launched for v$targetVersion. Exiting.');

    if (debugExitOnCompletion) {
      // Small delay so the UI overlay can show the "completed" state.
      await Future.delayed(const Duration(seconds: 2));

      // Exit the app. The agent owns the update process from here.
      exit(0);
    }
  }

  // ── Download with progress ────────────────────────────────────────────────

  /// Stream the installer from [url] to [destination], updating [progress]
  /// along the way. Uses chunked transfer to avoid loading the entire file
  /// into memory — critical on low-RAM kiosk hardware.
  ///
  /// SHA-256 is computed incrementally on the same bytes (via a chunked
  /// conversion) and the hex digest is returned. This replaces the old
  /// "download then read the whole file back into RAM to hash" approach.
  static Future<String> _downloadWithProgress(
      String url, String destination, bool force) async {
    final client = http.Client();
    _activeDownloadClient = client;
    _activeDownloadPath = destination;

    // Streaming SHA-256: feeds every chunk through the hasher so no
    // post-download re-read of the installer is ever needed.
    final digest = _DigestCapture();
    final hasher = sha256.startChunkedConversion(digest);

    try {
      final request = http.Request('GET', Uri.parse(url));
      // Suggest a reasonable timeout — the download may be large.
      final response = await client
          .send(request)
          .timeout(downloadTimeoutOverride);

      if (response.statusCode != 200) {
        throw HttpException(
            'Server returned ${response.statusCode} for $url');
      }

      final contentLength = response.contentLength ?? 0;
      final file = File(destination);
      final sink = file.openWrite();
      var sinkClosed = false;

      int bytesReceived = 0;
      try {
        await for (final chunk in response.stream) {
          // Abort promptly when the user dismisses the overlay. [dismiss] has
          // already closed the active client; this makes the stream error out
          // immediately instead of draining the remaining body.
          if (_dismissRequested) {
            throw const _DownloadCancelled();
          }
          sink.add(chunk);
          hasher.add(chunk);
          bytesReceived += chunk.length;

          if (contentLength > 0) {
            progress.value = UpdateProgress(
              state: UpdateState.downloading,
              targetVersion: progress.value?.targetVersion ?? '?',
              fraction: bytesReceived / contentLength,
              force: force,
            );
          } else if (bytesReceived > 0 && bytesReceived % (512 * 1024) == 0) {
            // Unknown total size — show indeterminate progress every 512KB
            progress.value = UpdateProgress(
              state: UpdateState.downloading,
              targetVersion: progress.value?.targetVersion ?? '?',
              fraction: -1,
              force: force,
            );
          }
        }

        await sink.flush();
        await sink.close();
        sinkClosed = true;
        hasher.close();
      } finally {
        // Ensure a mid-stream error cannot leak the file handle.
        if (!sinkClosed) {
          try {
            await sink.close();
          } catch (_) {}
        }
      }

      Log.i('[AutoUpdater] Downloaded $bytesReceived bytes to $destination');
      return digest.value?.toString() ?? '';
    } finally {
      _activeDownloadClient = null;
      _activeDownloadPath = null;
      client.close();
      // On Windows an open file handle cannot be deleted, so [dismiss]'s
      // synchronous delete fails silently while the stream is still open.
      // Delete the partial file here, after the sink has been closed.
      if (_dismissRequested) {
        try {
          final f = File(destination);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  // ── Hash verification ─────────────────────────────────────────────────────

  /// Case-insensitive hex comparison of the streamed SHA-256 digest against
  /// the manifest's expected hash.
  static bool _matchesHash(String computedHex, String expectedHex) =>
      computedHex.toLowerCase() == expectedHex.toLowerCase();

  // ── Dismiss (user-initiated cancel) ───────────────────────────────────────

  /// Called when the user taps Dismiss on the update overlay.
  ///
  /// - Aborts any in-flight HTTP download stream.
  /// - Cleans up the partial MSI file.
  /// - Clears the progress overlay.
  /// - Resets the dedup fingerprint so the next manifest delivery re-evaluates.
  /// - Does NOT clear [availableUpdate] — the Settings button persists.
  static void dismiss() {
    Log.i('[AutoUpdater] User dismissed the update overlay');

    // Signal in-flight operations to bail out.
    _dismissRequested = true;

    // Abort active HTTP download if in progress.
    if (_activeDownloadClient != null) {
      try {
        _activeDownloadClient!.close();
      } catch (_) {
        // Best-effort — client may already be closed.
      }
      _activeDownloadClient = null;
    }

    // Delete partially-downloaded file.
    if (_activeDownloadPath != null) {
      try {
        final f = File(_activeDownloadPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      _activeDownloadPath = null;
    }

    // Clear the overlay.
    progress.value = null;

    // Reset fingerprint so next heartbeat re-evaluates (circuit breaker still
    // applies, so it won't loop infinitely).
    _lastCheckedManifestFingerprint = null;
  }

  // ── Circuit Breaker ──────────────────────────────────────────────────────

  /// Called after each pipeline failure to increment the failure counter.
  /// When the counter hits [maxConsecutiveFailures], auto-retry is blocked.
  static void _incrementCircuitBreaker(UpdateManifest manifest) {
    final fp =
        '${manifest.minimumVersion}|${manifest.force}|${manifest.rolloutPercentage}';

    if (_failedVersionFingerprint != fp) {
      // New version / different params — reset counter.
      _consecutiveFailures = 0;
      _failedVersionFingerprint = fp;
    }

    _consecutiveFailures++;

    Log.w('[AutoUpdater] Circuit breaker: $_consecutiveFailures'
        '/$_maxConsecutiveFailures failures for $fp');

    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      Log.e('[AutoUpdater] Circuit breaker OPEN — '
          'auto-retry disabled for $fp');
      // [availableUpdate] stays set so Settings shows the retry button.
    }
  }

  /// Reset the circuit breaker, allowing auto-retry again.
  /// Called when:
  ///   - Admin sends a fresh WebSocket `update_available` push.
  ///   - User taps "Retry Update" in Settings.
  ///   - A force-update overrides a failed state.
  static void resetCircuitBreaker() {
    if (_consecutiveFailures > 0 || _failedVersionFingerprint != null) {
      Log.i('[AutoUpdater] Circuit breaker reset by user or admin action');
    }
    _consecutiveFailures = 0;
    _failedVersionFingerprint = null;
  }

  /// Whether the circuit breaker is currently open for the latest failed version.
  static bool get isCircuitBreakerOpen =>
      _consecutiveFailures >= _maxConsecutiveFailures;

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Current installed version, parsed from [PackageInfo].
  static Version get _installedVersion {
    final override = testInstalledVersionOverride;
    if (override != null && override.isNotEmpty) {
      try {
        return Version.parse(override);
      } catch (_) {}
    }
    if (_packageInfo == null) return Version.zero;
    try {
      // PackageInfo.version already contains the build number (e.g. "5.5.0+6").
      // Do NOT append buildNumber again — it produces "5.5.0+6+6" which breaks parsing.
      return Version.parse(_packageInfo!.version);
    } catch (_) {
      return Version.zero;
    }
  }

  /// Minimum free bytes required on the staging drive before an update is
  /// accepted. The installer can be a few hundred MB (Inno Setup compresses
  /// heavily but the unpacked app is larger), and the rollback backup adds
  /// headroom on top.
  static const int _minFreeDiskBytes = 200 * 1024 * 1024; // 200 MB

  /// Best-effort disk space check on the update staging drive.
  ///
  /// On Windows queries `Get-PSDrive` (avoids adding a native `ffi`/win32
  /// dependency). Returns `true` (allow) if the probe cannot be performed so
  /// updates are never blocked by a check failure, only by a genuine shortage.
  static Future<bool> _hasEnoughDiskSpace() async {
    try {
      if (diskSpaceProbeOverride != null) {
        return await diskSpaceProbeOverride!();
      }
      if (Platform.isWindows) {
        final drive = _driveLetter(InstallPaths.updateDir);
        final result = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            "(Get-PSDrive -Name '$drive' -ErrorAction SilentlyContinue).Free",
          ],
        ).timeout(const Duration(seconds: 10));

        final stdout = result.stdout.toString().trim();
        final lastLine = stdout.isEmpty ? '' : stdout.split('\n').last.trim();
        final freeBytes = int.tryParse(lastLine);
        if (freeBytes != null) {
          final ok = freeBytes >= _minFreeDiskBytes;
          Log.i('[AutoUpdater] Disk space: '
              '${(freeBytes / (1024 * 1024)).toStringAsFixed(0)} MB free on '
              'drive $drive (need ${_minFreeDiskBytes ~/ (1024 * 1024)} MB) '
              '→ ${ok ? "ok" : "INSUFFICIENT"}');
          return ok;
        }
        Log.w('[AutoUpdater] Could not parse free space output: '
            '"$stdout" — assuming OK');
      }
    } catch (e) {
      Log.w('[AutoUpdater] Disk space check failed (non-fatal): $e');
    }
    return true;
  }

  /// Extract the drive letter (e.g. `C`) from a Windows path.
  static String _driveLetter(String path) {
    if (path.length >= 2 && path[1] == ':') return path[0];
    return 'C';
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

  // ── Validation-harness helpers ────────────────────────────────────────────

  /// Reset all mutable state so a validation scenario starts clean.
  @visibleForTesting
  static void debugReset() {
    progress.value = null;
    availableUpdate.value = null;
    _dismissRequested = false;
    try {
      _activeDownloadClient?.close();
    } catch (_) {}
    _activeDownloadClient = null;
    _activeDownloadPath = null;
    _lastCheckedManifestFingerprint = null;
    _consecutiveFailures = 0;
    _failedVersionFingerprint = null;
    _updatePipelineInFlight = false;
    _packageInfo = null;
    _boardId = null;
    _boardChannel = 'stable';
    _hmacSecretKey = null;
    _initializedAt = null;
    testInstalledVersionOverride = null;
    debugInitializedAt = null;
    diskSpaceProbeOverride = null;
    agentLauncherOverride = null;
    debugExitOnCompletion = true;
    downloadTimeoutOverride = _downloadTimeout;
  }

  /// Wait until the in-flight pipeline completes (or [timeout] elapses).
  /// Returns false on timeout so validation scenarios can fail loudly.
  @visibleForTesting
  static Future<bool> debugWaitForPipeline({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_updatePipelineInFlight) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future.delayed(const Duration(milliseconds: 20));
    }
    return true;
  }
}

/// Thrown when the user dismisses the overlay while the installer is still
/// streaming, so `_downloadWithProgress` aborts promptly and the pipeline can
/// clean up the partial file.
class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}

/// Captures the final [Digest] produced by a chunked hash conversion.
///
/// Used to compute SHA-256 incrementally during download without loading the
/// whole installer into memory (crypto's `DigestSink` is not part of the
/// public `crypto` 3.x API, so we provide our own `Sink<Digest>`).
class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
