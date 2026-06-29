import 'dart:async';

import '../core/utils/logger.dart';
import 'auto_updater.dart';
import 'remote_config_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateChecker
//
// Lightweight service that schedules periodic checks for binary updates.
// It reads the [UpdateManifest] from [RemoteConfigService.updateManifest] and
// delegates to [AutoUpdater.checkForUpdate].
//
// Two triggering paths:
//
//   1. **Scheduled** — a timer runs every N minutes while the board is idle.
//      This catches updates that arrive between heartbeats, and handles the
//      case where the heartbeat response didn't include an update block but
//      the dedicated check-update endpoint has one.
//
//   2. **On heartbeat** — whenever a new [RemoteConfig] arrives (see
//      [HeartbeatService]), we call [checkNow] immediately. This is the
//      primary path; the timer is a safety net.
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
    final manifest = RemoteConfigService.updateManifest;
    if (manifest == null) {
      return; // no manifest configured
    }

    Log.d('[UpdateChecker] Checking for update (target: ${manifest.minimumVersion})');

    try {
      await AutoUpdater.checkForUpdate(manifest);
    } catch (e) {
      Log.e('[UpdateChecker] Check failed: $e');
    }
  }
}
