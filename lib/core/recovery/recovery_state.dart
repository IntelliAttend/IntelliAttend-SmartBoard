import '../../core/lifecycle/lifecycle_phase.dart';
import '../../core/startup_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RecoveryType
//
// Classifies the kind of recovery being attempted. Each type determines:
//   - What the UI shows (title, icon, message, actions)
//   - Whether automatic retry is available
//   - Whether "Launch Anyway" is safe
//   - Whether diagnostic details should be shown
//
// The type is immutable after construction.
// ─────────────────────────────────────────────────────────────────────────────
enum RecoveryType {
  /// A previous launch crashed and the system detected a crash loop.
  /// Shows: crash count, last failure reason, version info.
  /// Actions: retry, launch anyway (risky), close.
  crashLoop,

  /// The application binary failed integrity verification (hash mismatch
  /// or code signature invalid).
  /// Shows: what failed, expected vs actual hashes.
  /// Actions: retry, close (launch anyway NOT safe).
  integrityFailure,

  /// A lifecycle phase returned an error (validation, config, database).
  /// Shows: which phase failed, error message, timing.
  /// Actions: retry, close.
  lifecycleFailure,

  /// A startup timeout occurred (watchdog fired after 60s).
  /// Shows: how long startup took, which phase was stuck.
  /// Actions: retry, close.
  startupTimeout,

  /// The previous update was interrupted or left the system in a bad state.
  /// Shows: update state details, version info.
  /// Actions: retry (auto-resolves), close.
  updateCorruption,

  /// An unhandled exception escaped the lifecycle.
  /// Shows: error message.
  /// Actions: retry, close.
  unhandledError,
}

// ─────────────────────────────────────────────────────────────────────────────
// RecoveryDiagnostics
//
// Rich diagnostic context collected at the point of failure. Passed to the
// recovery screen so support engineers can understand what happened without
// accessing log files.
//
// All fields are nullable — the recovery screen gracefully handles partial
// diagnostics.
// ─────────────────────────────────────────────────────────────────────────────
class RecoveryDiagnostics {
  /// The app version that failed to start.
  final String? appVersion;

  /// The lifecycle phase that was running when failure occurred.
  final AppLifecyclePhase? failedPhase;

  /// Human-readable error message from the failing phase.
  final String? errorMessage;

  /// Number of consecutive failed launches (from StartupService).
  final int? crashCount;

  /// Whether this launch was triggered by Windows auto-start.
  final bool isAutoStart;

  /// The time the lifecycle started (ISO-8601).
  final String? startedAt;

  /// Total elapsed time before failure (milliseconds).
  final int? elapsedMs;

  /// Phase timings collected before failure.
  final List<PhaseTiming> timings;

  /// Additional key-value pairs for diagnostic display.
  final Map<String, String> extra;

  const RecoveryDiagnostics({
    this.appVersion,
    this.failedPhase,
    this.errorMessage,
    this.crashCount,
    this.isAutoStart = false,
    this.startedAt,
    this.elapsedMs,
    this.timings = const [],
    this.extra = const {},
  });

  /// Create diagnostics from a lifecycle guard result.
  factory RecoveryDiagnostics.fromGuard({
    required String? appVersion,
    required StartupLaunchGuardResult guard,
    required AppLifecyclePhase? failedPhase,
    required String? errorMessage,
    required List<PhaseTiming> timings,
    required Duration elapsed,
  }) {
    return RecoveryDiagnostics(
      appVersion: appVersion,
      failedPhase: failedPhase,
      errorMessage: errorMessage,
      crashCount: guard.failedLaunches,
      isAutoStart: guard.isAutoStart,
      startedAt: DateTime.now().toIso8601String(),
      elapsedMs: elapsed.inMilliseconds,
      timings: timings,
    );
  }

  /// Minimal diagnostics for failures without a guard result.
  factory RecoveryDiagnostics.fromFailure({
    required String? appVersion,
    required AppLifecyclePhase? failedPhase,
    required String? errorMessage,
    required List<PhaseTiming> timings,
    required Duration elapsed,
  }) {
    return RecoveryDiagnostics(
      appVersion: appVersion,
      failedPhase: failedPhase,
      errorMessage: errorMessage,
      startedAt: DateTime.now().toIso8601String(),
      elapsedMs: elapsed.inMilliseconds,
      timings: timings,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RecoveryPhase
//
// Where the recovery process is right now. Drives UI indicators.
// ─────────────────────────────────────────────────────────────────────────────
enum RecoveryPhase {
  /// Automatic recovery is running (cleaning state, migrating paths).
  resolving,

  /// Recovery succeeded. App is about to relaunch.
  resolved,

  /// Recovery failed or is not possible. Waiting for user action.
  failed,

  /// User chose "Launch Anyway". App is about to start.
  launching,

  /// User chose "Close". App is shutting down.
  closing,
}

// ─────────────────────────────────────────────────────────────────────────────
// RecoveryState
//
// Immutable snapshot of the recovery manager's current state. The UI
// renders based on this single object. The [ValueNotifier] emits a new
// instance on every state change.
// ─────────────────────────────────────────────────────────────────────────────
class RecoveryState {
  /// The type of recovery being attempted.
  final RecoveryType type;

  /// Current phase of the recovery process.
  final RecoveryPhase phase;

  /// Rich diagnostic context.
  final RecoveryDiagnostics diagnostics;

  /// Human-readable status message shown in the UI.
  final String? statusMessage;

  /// Whether the "Launch Anyway" button should be shown.
  final bool canLaunchAnyway;

  const RecoveryState({
    required this.type,
    required this.phase,
    required this.diagnostics,
    this.statusMessage,
    this.canLaunchAnyway = false,
  });

  /// Whether recovery is actively running (progress indicator visible).
  bool get isResolving => phase == RecoveryPhase.resolving;

  /// Whether the user can interact with action buttons.
  bool get awaitingUserAction => phase == RecoveryPhase.failed;

  /// Whether the app is about to relaunch or close (buttons disabled).
  bool get isTransitioning =>
      phase == RecoveryPhase.resolved ||
      phase == RecoveryPhase.launching ||
      phase == RecoveryPhase.closing;
}
