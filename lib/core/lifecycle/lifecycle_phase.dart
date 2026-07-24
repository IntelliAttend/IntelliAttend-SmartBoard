/// Defines every phase of the application lifecycle.
///
/// The lifecycle is deterministic: every launch transitions through
/// these phases in order, with well-defined recovery paths.
///
/// ```text
/// BOOT → RECOVERY → VALIDATION → CONFIGURATION → DATABASE
///   → READY → UPDATING → SHUTDOWN
/// ```
enum AppLifecyclePhase {
  /// Initial: directories, paths, single-instance lock.
  boot,

  /// Stale update state, path migration, crash loop detection.
  recovery,

  /// Integrity check, code signature verification.
  validation,

  /// Environment loading, remote config, auto-start registration.
  configuration,

  /// Isar vault, secure storage initialization.
  database,

  /// Window manager, kiosk hardening, repository setup.
  window,

  /// Running: heartbeat, auto-updater, background protocols.
  ready,

  /// Update agent launched, waiting for completion.
  updating,

  /// Clean exit or crash loop exit.
  shutdown,

  /// Fatal error — app cannot continue.
  failed,

  /// Rollback in progress — previous version being restored.
  rollingBack,
}

/// Result of a lifecycle phase execution.
class PhaseResult {
  /// Whether the phase succeeded.
  final bool success;

  /// Optional error message if the phase failed.
  final String? error;

  /// Whether the lifecycle should skip to READY (e.g., crash loop detected).
  final bool skipToReady;

  /// Whether the lifecycle should transition to UPDATING.
  final bool transitionToUpdate;

  /// Whether the lifecycle should transition to RECOVERY.
  final bool transitionToRecovery;

  /// Whether the lifecycle should transition to ROLLBACK.
  final bool transitionToRollback;

  /// Whether the lifecycle should transition to SHUTDOWN.
  final bool transitionToShutdown;

  const PhaseResult({
    required this.success,
    this.error,
    this.skipToReady = false,
    this.transitionToUpdate = false,
    this.transitionToRecovery = false,
    this.transitionToRollback = false,
    this.transitionToShutdown = false,
  });

  const PhaseResult.ok()
      : success = true,
        error = null,
        skipToReady = false,
        transitionToUpdate = false,
        transitionToRecovery = false,
        transitionToRollback = false,
        transitionToShutdown = false;

  const PhaseResult.fail(String message)
      : success = false,
        error = message,
        skipToReady = false,
        transitionToUpdate = false,
        transitionToRecovery = false,
        transitionToRollback = false,
        transitionToShutdown = false;

  const PhaseResult.skipToReady()
      : success = true,
        error = null,
        skipToReady = true,
        transitionToUpdate = false,
        transitionToRecovery = false,
        transitionToRollback = false,
        transitionToShutdown = false;

  const PhaseResult.shutdown()
      : success = true,
        error = null,
        skipToReady = false,
        transitionToUpdate = false,
        transitionToRecovery = false,
        transitionToRollback = false,
        transitionToShutdown = true;

  const PhaseResult.recover()
      : success = true,
        error = null,
        skipToReady = false,
        transitionToUpdate = false,
        transitionToRecovery = true,
        transitionToRollback = false,
        transitionToShutdown = false;

  const PhaseResult.rollback()
      : success = true,
        error = null,
        skipToReady = false,
        transitionToUpdate = false,
        transitionToRecovery = false,
        transitionToRollback = true,
        transitionToShutdown = false;

  const PhaseResult.update()
      : success = true,
        error = null,
        skipToReady = false,
        transitionToUpdate = true,
        transitionToRecovery = false,
        transitionToRollback = false,
        transitionToShutdown = false;
}

/// Timing information for a completed phase.
class PhaseTiming {
  final AppLifecyclePhase phase;
  final Duration duration;
  final DateTime startedAt;
  final DateTime completedAt;

  const PhaseTiming({
    required this.phase,
    required this.duration,
    required this.startedAt,
    required this.completedAt,
  });

  @override
  String toString() =>
      '[${phase.name}] ${duration.inMilliseconds}ms';
}
