import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/utils/logger.dart';
import '../models/remote_config.dart';
import 'auto_updater.dart';
import 'remote_config_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateChecker
//
// Lightweight service that schedules periodic checks for binary updates.
// Two sources:
//   1. Server manifest via heartbeat (RemoteConfigService)
//   2. GitHub releases latest.json (direct poll)
//
// ── Rationale ───────────────────────────────────────────────────────────────
// Separating the scheduling concern from [AutoUpdater] keeps the download /
// install logic testable (it doesn't depend on a timer) and keeps the
// scheduling logic simple (it doesn't care about files or processes).
// ─────────────────────────────────────────────────────────────────────────────
class UpdateChecker {
  UpdateChecker._(); // prevent instantiation

  static Timer? _timer;

  /// How often to check for updates during idle periods.
  static const Duration _checkInterval = Duration(minutes: 15);

  /// GitHub releases latest.json URL (set via configure).
  static String? _githubManifestUrl;

  /// Last version seen from GitHub (to avoid re-processing).
  static String? _lastGithubVersion;

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Configure the GitHub releases manifest URL.
  ///
  /// Example: `https://github.com/IntelliAttend/IntelliAttend-SmartBoard/releases/latest/download/latest.json`
  static void configure({String? githubManifestUrl}) {
    _githubManifestUrl = githubManifestUrl;
    Log.d('[UpdateChecker] Configured GitHub URL: $_githubManifestUrl');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Start the periodic check timer.
  ///
  /// Call once during startup, after [RemoteConfigService.init] and
  /// [AutoUpdater.init] have completed.
  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) {
      _check();
    });
    Log.d('[UpdateChecker] Started (interval: ${_checkInterval.inMinutes} min)');

    // Also run an immediate check.
    _check();
  }

  /// Stop the timer. Call during shutdown to avoid dangling timers.
  static void stop() {
    _timer?.cancel();
    _timer = null;
    Log.d('[UpdateChecker] Stopped');
  }

  // ── Triggered check (called from heartbeat service) ───────────────────────

  /// Perform an immediate update check.
  ///
  /// This is the entry point called from [HeartbeatService] whenever a new
  /// [RemoteConfig] arrives. It pulls the latest manifest from
  /// [RemoteConfigService] and, if present, delegates to [AutoUpdater].
  ///
  /// Safe to call frequently — [AutoUpdater.checkForUpdate] returns early
  /// if no update is needed or one is already in progress.
  static Future<void> checkNow() async {
    await _check();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static Future<void> _check() async {
    // Source 1: Server manifest via heartbeat
    final serverManifest = RemoteConfigService.updateManifest;
    if (serverManifest != null) {
      Log.d('[UpdateChecker] Server manifest: v${serverManifest.minimumVersion}');
      try {
        await AutoUpdater.checkForUpdate(serverManifest);
        return; // Server manifest takes priority
      } catch (e) {
        Log.e('[UpdateChecker] Server check failed: $e');
      }
    }

    // Source 2: GitHub releases latest.json
    if (_githubManifestUrl != null) {
      await _checkGithubReleases();
    }
  }

  static Future<void> _checkGithubReleases() async {
    try {
      Log.d('[UpdateChecker] Checking GitHub releases: $_githubManifestUrl');

      final response = await http.get(
        Uri.parse(_githubManifestUrl!),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        Log.w('[UpdateChecker] GitHub returned ${response.statusCode}');
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final manifest = UpdateManifest.fromJson(json);

      // Skip if same version already processed
      if (manifest.minimumVersion == _lastGithubVersion) {
        Log.d('[UpdateChecker] GitHub version unchanged: v${manifest.minimumVersion}');
        return;
      }

      _lastGithubVersion = manifest.minimumVersion;
      Log.i('[UpdateChecker] GitHub update available: v${manifest.minimumVersion}');

      await AutoUpdater.checkForUpdate(manifest);
    } catch (e) {
      Log.e('[UpdateChecker] GitHub check failed: $e');
    }
  }
}
