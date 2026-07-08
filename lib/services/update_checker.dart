import 'dart:async';

import '../core/utils/logger.dart';
import 'auto_updater.dart';
import 'remote_config_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateChecker
//
// Checks for binary updates. ONLY uses WebSocket-triggered paths:
//   1. Server manifest via heartbeat (RemoteConfigService)
//
// HTTP polling and GitHub fallback have been DISABLED.
// Reason: HTTPS download through Cloudflare fails/throttles for large MSI files.
// Updates are triggered exclusively via:
//   - WebSocket "update_available" message (admin push)
//   - Heartbeat config delivery (server manifest)
//
// ── DISABLED (kept for reference) ───────────────────────────────────────────
// HTTP polling was removed because:
//   - Cloudflare throttles/blocks 19MB MSI downloads over HTTPS
//   - SmartBoard can't download from GitHub releases (private repo)
//   - WebSocket push is instant and reliable
//
// The methods below are commented out but preserved for future use if
// HTTPS download is fixed or a public download CDN is set up.
//
// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import '../core/config/app_config.dart';
//
// static String? _githubManifestUrl;
// static String? _lastGithubVersion;
// static String? _lastServerVersion;
//
// static void configure({String? githubManifestUrl}) {
//   _githubManifestUrl = githubManifestUrl;
// }
//
// static Future<void> _checkServerUpdates() async {
//   final serverUrl = AppConfig.baseUrl;
//   final url = '$serverUrl/api/v1/board/check-update';
//   final response = await http.get(Uri.parse(url), ...).timeout(...);
//   // parse manifest, call AutoUpdater.checkForUpdate(manifest, silent: true)
// }
//
// static Future<void> _checkGithubReleases() async {
//   final response = await http.get(Uri.parse(_githubManifestUrl!), ...).timeout(...);
//   // parse manifest, call AutoUpdater.checkForUpdate(manifest, silent: true)
// }
// ─────────────────────────────────────────────────────────────────────────────

class UpdateChecker {
  UpdateChecker._(); // prevent instantiation

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// No-op. Update checking is handled by heartbeat config delivery
  /// and WebSocket push. This method exists for backward compatibility.
  static void start() {
    Log.d('[UpdateChecker] Started — using WebSocket-only path (no HTTP polling)');
  }

  /// Stop the timer. No-op since we don't poll anymore.
  static void stop() {
    Log.d('[UpdateChecker] Stopped');
  }

  // ── Triggered check (called from heartbeat service) ───────────────────────

  /// Check for updates using the heartbeat manifest (no HTTP).
  static Future<void> checkNow() async {
    final manifest = RemoteConfigService.updateManifest;
    if (manifest != null) {
      Log.d('[UpdateChecker] Heartbeat manifest: v${manifest.minimumVersion}');
      await AutoUpdater.checkForUpdate(manifest, silent: true);
    }
  }
}
