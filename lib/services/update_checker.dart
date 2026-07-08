import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../core/utils/logger.dart';
import '../models/remote_config.dart';
import 'auto_updater.dart';
import 'remote_config_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateChecker
//
// Lightweight service that schedules periodic checks for binary updates.
// Three sources (in priority order):
//   1. Server manifest via heartbeat (RemoteConfigService)
//   2. Direct server check (/api/v1/board/check-update)
//   3. GitHub releases latest.json (fallback)
//
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

  /// Last version seen from server (to avoid re-processing).
  static String? _lastServerVersion;

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Configure the GitHub releases manifest URL (fallback).
  static void configure({String? githubManifestUrl}) {
    _githubManifestUrl = githubManifestUrl;
    Log.d('[UpdateChecker] Configured GitHub URL: $_githubManifestUrl');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Start the periodic check timer.
  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) {
      _check();
    });
    Log.d('[UpdateChecker] Started (interval: ${_checkInterval.inMinutes} min)');

    // Delay first check by 30s to let the app fully initialize.
    Timer(const Duration(seconds: 30), () => _check());
  }

  /// Stop the timer.
  static void stop() {
    _timer?.cancel();
    _timer = null;
    Log.d('[UpdateChecker] Stopped');
  }

  // ── Triggered check (called from heartbeat service) ───────────────────────

  /// Perform an immediate update check.
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
        await AutoUpdater.checkForUpdate(serverManifest, silent: true);
        return;
      } catch (e) {
        Log.e('[UpdateChecker] Server manifest check failed: $e');
      }
    }

    // Source 2: Direct server check
    await _checkServerUpdates();
    
    // Source 3: GitHub releases (fallback)
    if (_githubManifestUrl != null) {
      await _checkGithubReleases();
    }
  }

  /// Check server directly for updates.
  static Future<void> _checkServerUpdates() async {
    try {
      final serverUrl = AppConfig.baseUrl;
      final url = '$serverUrl/api/v1/board/check-update';
      
      Log.d('[UpdateChecker] Checking server: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        Log.d('[UpdateChecker] Server returned ${response.statusCode}');
        return;
      }
      
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      
      // Fix relative download URL
      if (json['download_url']?.toString().startsWith('/') == true) {
        json['download_url'] = '$serverUrl${json['download_url']}';
      }
      
      final manifest = UpdateManifest.fromJson(json);
      
      // Skip if same version already processed
      if (manifest.minimumVersion == _lastServerVersion) {
        Log.d('[UpdateChecker] Server version unchanged: v${manifest.minimumVersion}');
        return;
      }
      
      _lastServerVersion = manifest.minimumVersion;
      Log.i('[UpdateChecker] Server update available: v${manifest.minimumVersion}');
      
      await AutoUpdater.checkForUpdate(manifest, silent: true);
    } catch (e) {
      Log.e('[UpdateChecker] Server check failed: $e');
    }
  }

  /// Check GitHub releases (fallback).
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

      if (manifest.minimumVersion == _lastGithubVersion) {
        Log.d('[UpdateChecker] GitHub version unchanged: v${manifest.minimumVersion}');
        return;
      }

      _lastGithubVersion = manifest.minimumVersion;
      Log.i('[UpdateChecker] GitHub update available: v${manifest.minimumVersion}');

      await AutoUpdater.checkForUpdate(manifest, silent: true);
    } catch (e) {
      Log.e('[UpdateChecker] GitHub check failed: $e');
    }
  }
}
