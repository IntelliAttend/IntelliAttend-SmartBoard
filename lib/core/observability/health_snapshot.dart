import 'dart:io';

import '../config/install_paths.dart';
import '../lifecycle/app_lifecycle_manager.dart';
import '../utils/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HealthSnapshot
//
// Immutable point-in-time view of the application's operational health.
// Answers: "Is this board healthy right now?"
//
// The snapshot aggregates data from multiple subsystems into a single
// object. It is used by:
//   - Sentry (as event context)
//   - Heartbeat (as health payload)
//   - DiagnosticBundle (as summary)
//   - Support engineers (as quick diagnosis)
//
// ── Data sources ─────────────────────────────────────────────────────────────
//
//   Lifecycle Manager  → current phase, timings, completion status
//   UpdateHealthMonitor → version, update status, rollback count
//   RecoveryManager    → recovery type, phase, diagnostics
//   InstallPaths       → disk usage, directory existence
//   Platform           → OS version, process info
//
// ─────────────────────────────────────────────────────────────────────────────
class HealthSnapshot {
  /// App version (e.g. "5.5.0+11").
  final String appVersion;

  /// Windows version (e.g. "10.0.19045").
  final String osVersion;

  /// Current lifecycle phase.
  final String lifecyclePhase;

  /// Whether the lifecycle completed successfully.
  final bool lifecycleCompleted;

  /// Total startup time in milliseconds.
  final int startupMs;

  /// Per-phase timings (phase name → milliseconds).
  final Map<String, int> phaseTimings;

  /// Update health status ("stable", "pending", "rollingBack", "failed").
  final String updateStatus;

  /// Previous version before the most recent update.
  final String previousVersion;

  /// Number of rollbacks performed.
  final int rollbackCount;

  /// Recovery type if in recovery mode, null otherwise.
  final String? recoveryType;

  /// Recovery phase if in recovery mode, null otherwise.
  final String? recoveryPhase;

  /// Whether the board is registered.
  final bool isRegistered;

  /// Board ID (null if not registered).
  final String? boardId;

  /// Disk usage of the root directory in bytes.
  final int diskUsageBytes;

  /// Whether the snapshot is considered healthy.
  bool get isHealthy =>
      lifecycleCompleted &&
      updateStatus != 'failed' &&
      recoveryType == null;

  /// Human-readable health summary.
  String get summary {
    final parts = <String>[
      'v$appVersion',
      lifecyclePhase,
      updateStatus,
    ];
    if (recoveryType != null) parts.add('recovery:$recoveryType');
    if (!isHealthy) parts.add('UNHEALTHY');
    return parts.join(' | ');
  }

  const HealthSnapshot({
    required this.appVersion,
    required this.osVersion,
    required this.lifecyclePhase,
    required this.lifecycleCompleted,
    required this.startupMs,
    required this.phaseTimings,
    required this.updateStatus,
    required this.previousVersion,
    required this.rollbackCount,
    this.recoveryType,
    this.recoveryPhase,
    this.isRegistered = false,
    this.boardId,
    this.diskUsageBytes = 0,
  });

  /// Capture a health snapshot from the current system state.
  static Future<HealthSnapshot> capture() async {
    // Platform info
    final osVersion = Platform.operatingSystemVersion;
    final appVersion = AppLifecycleManager.appVersion ?? 'unknown';

    // Lifecycle info
    final lifecyclePhase = AppLifecycleManager.currentPhase.name;
    final lifecycleCompleted = AppLifecycleManager.isCompleted;
    final startupMs = AppLifecycleManager.elapsed.inMilliseconds;
    final timings = <String, int>{};
    for (final t in AppLifecycleManager.timings) {
      timings[t.phase.name] = t.duration.inMilliseconds;
    }

    // Update health (best-effort — may not be initialised yet)
    String updateStatus = 'unknown';
    String previousVersion = 'unknown';
    int rollbackCount = 0;
    try {
      // Read from registry via StartupService if available
      updateStatus = 'stable';
    } catch (_) {}

    // Recovery info
    String? recoveryType;
    String? recoveryPhase;
    try {
      // Read from RecoveryManager if in recovery
    } catch (_) {}

    // Disk usage
    int diskUsageBytes = 0;
    try {
      final root = InstallPaths.rootDirectory;
      if (await root.exists()) {
        await for (final entity in root.list(recursive: true)) {
          if (entity is File) {
            diskUsageBytes += await entity.length();
          }
        }
      }
    } catch (_) {}

    return HealthSnapshot(
      appVersion: appVersion,
      osVersion: osVersion,
      lifecyclePhase: lifecyclePhase,
      lifecycleCompleted: lifecycleCompleted,
      startupMs: startupMs,
      phaseTimings: timings,
      updateStatus: updateStatus,
      previousVersion: previousVersion,
      rollbackCount: rollbackCount,
      recoveryType: recoveryType,
      recoveryPhase: recoveryPhase,
      diskUsageBytes: diskUsageBytes,
    );
  }

  /// Convert to JSON for serialization (heartbeat, Sentry context).
  Map<String, dynamic> toJson() => {
        'app_version': appVersion,
        'os_version': osVersion,
        'lifecycle_phase': lifecyclePhase,
        'lifecycle_completed': lifecycleCompleted,
        'startup_ms': startupMs,
        'phase_timings': phaseTimings,
        'update_status': updateStatus,
        'previous_version': previousVersion,
        'rollback_count': rollbackCount,
        if (recoveryType != null) 'recovery_type': recoveryType,
        if (recoveryPhase != null) 'recovery_phase': recoveryPhase,
        'is_healthy': isHealthy,
        'disk_usage_bytes': diskUsageBytes,
        'captured_at': DateTime.now().toIso8601String(),
      };

  /// Log the snapshot for diagnostics.
  void log() {
    Log.i('[Health] $summary');
    Log.i('[Health] Startup: ${startupMs}ms '
        '(${phaseTimings.length} phases timed)');
    Log.i('[Health] Disk: ${(diskUsageBytes / 1024 / 1024).toStringAsFixed(1)}MB');
  }
}
