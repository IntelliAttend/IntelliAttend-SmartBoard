import 'dart:async';

import 'package:flutter/foundation.dart';

import '../lifecycle/lifecycle_recover.dart';
import '../observability/observability_manager.dart';
import '../utils/logger.dart';
import 'recovery_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RecoveryManager
//
// Singleton state machine that owns the recovery lifecycle when the
// application fails to start normally.
//
// Responsibilities:
//   - Hold the current [RecoveryType] and [RecoveryDiagnostics]
//   - Attempt automatic recovery (stale state cleanup, migration retry)
//   - Expose the recovery state to the UI via [ValueNotifier]
//   - Execute recovery actions (retry, launch anyway, close)
//
// The manager is designed for use BEFORE the main app starts. It runs as
// a standalone MaterialApp (same pattern as the existing InitFailureScreen).
//
// ── State Machine ────────────────────────────────────────────────────────────
//
//   RESOLVING  ──success──▶  RESOLVED  ──onReady──▶  (app relaunches)
//       │
//       └──failure──▶  FAILED  ──user action──▶  (retry / close)
//
// ─────────────────────────────────────────────────────────────────────────────
class RecoveryManager {
  RecoveryManager._();

  // ── State ──────────────────────────────────────────────────────────────────

  static RecoveryType _type = RecoveryType.lifecycleFailure;
  static RecoveryDiagnostics _diagnostics = const RecoveryDiagnostics();
  static RecoveryPhase _phase = RecoveryPhase.resolving;
  static String? _statusMessage;
  static bool _canLaunchAnyway = false;

  /// Notifier for recovery state changes. The UI listens to this.
  static final ValueNotifier<RecoveryState> stateNotifier =
      ValueNotifier<RecoveryState>(_buildState());

  /// Callback invoked when the recovery manager wants to relaunch the app.
  static VoidCallback? _onRelaunch;

  // ── Public API ────────────────────────────────────────────────────────────

  static RecoveryType get type => _type;
  static RecoveryDiagnostics get diagnostics => _diagnostics;
  static RecoveryPhase get phase => _phase;
  static String? get statusMessage => _statusMessage;
  static bool get canLaunchAnyway => _canLaunchAnyway;

  /// Initialise the recovery manager with failure context and begin
  /// automatic recovery if applicable.
  static Future<void> init({
    required RecoveryType type,
    required RecoveryDiagnostics diagnostics,
    VoidCallback? onRelaunch,
  }) async {
    _type = type;
    _diagnostics = diagnostics;
    _onRelaunch = onRelaunch;
    _phase = RecoveryPhase.resolving;
    _statusMessage = 'Attempting automatic recovery...';
    _canLaunchAnyway = type == RecoveryType.crashLoop;
    _emit();

    Log.i('[Recovery] Init type=$type crashCount=${diagnostics.crashCount} '
        'phase=${diagnostics.failedPhase}');
    ObservabilityManager.recoveryBreadcrumb('init',
        detail: 'type=$type phase=${diagnostics.failedPhase}');

    // Attempt automatic recovery for recoverable states.
    if (_isAutoRecoverable(type)) {
      await _attemptAutoRecovery();
    } else {
      // Not auto-recoverable — go straight to failed, wait for user.
      _phase = RecoveryPhase.failed;
      _statusMessage = _humanMessage(type);
      _emit();
    }
  }

  /// User action: retry the startup.
  static Future<void> retry() async {
    _phase = RecoveryPhase.resolving;
    _statusMessage = 'Retrying...';
    _emit();

    Log.i('[Recovery] User-initiated retry');
    await _attemptAutoRecovery();
  }

  /// User action: launch the app anyway (bypassing recovery).
  /// Only available for crash loop recovery.
  static void launchAnyway() {
    if (!_canLaunchAnyway) return;
    Log.w('[Recovery] User chose to launch anyway');
    _phase = RecoveryPhase.launching;
    _statusMessage = 'Launching application...';
    _emit();
    _onRelaunch?.call();
  }

  /// User action: close the application.
  static void close() {
    Log.i('[Recovery] User chose to close');
    _phase = RecoveryPhase.closing;
    _emit();
  }

  // ── Automatic Recovery ──────────────────────────────────────────────────

  static Future<void> _attemptAutoRecovery() async {
    try {
      // Step 1: Clean stale update state.
      _statusMessage = 'Cleaning stale update state...';
      _emit();
      await LifecycleRecover.recoverFromStaleUpdateState();
      Log.d('[Recovery] Stale update state resolved');

      // Step 2: Run path migration.
      _statusMessage = 'Verifying directory structure...';
      _emit();
      await LifecycleRecover.runPathMigration();
      Log.d('[Recovery] Path migration complete');

      // Step 3: Mark launch completed so the next launch doesn't
      // re-enter crash loop detection.
      _statusMessage = 'Recording recovery result...';
      _emit();
      await LifecycleRecover.markLaunchCompleted();
      Log.d('[Recovery] Launch marked completed');

      // Recovery succeeded — relaunch the app.
      _phase = RecoveryPhase.resolved;
      _statusMessage = 'Recovery complete. Relaunching...';
      _emit();

      Log.i('[Recovery] Auto-recovery succeeded — relaunching in 2s');
      await Future.delayed(const Duration(seconds: 2));
      _onRelaunch?.call();
    } catch (e) {
      Log.e('[Recovery] Auto-recovery failed: $e');
      _phase = RecoveryPhase.failed;
      _statusMessage = 'Automatic recovery failed: $e';
      _emit();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static bool _isAutoRecoverable(RecoveryType type) {
    switch (type) {
      case RecoveryType.updateCorruption:
      case RecoveryType.crashLoop:
        return true;
      case RecoveryType.integrityFailure:
      case RecoveryType.lifecycleFailure:
      case RecoveryType.startupTimeout:
      case RecoveryType.unhandledError:
        return false;
    }
  }

  static String _humanMessage(RecoveryType type) {
    switch (type) {
      case RecoveryType.crashLoop:
        return 'The application has failed to start multiple times. '
            'You may retry or launch anyway.';
      case RecoveryType.integrityFailure:
        return 'The application files may be corrupted. '
            'Please reinstall from the installer.';
      case RecoveryType.lifecycleFailure:
        return 'A system component failed to initialize. '
            'Check the diagnostic details below.';
      case RecoveryType.startupTimeout:
        return 'Startup took too long and was interrupted. '
            'This may indicate a system resource issue.';
      case RecoveryType.updateCorruption:
        return 'A previous update was interrupted. '
            'Attempting to restore the previous state...';
      case RecoveryType.unhandledError:
        return 'An unexpected error occurred during startup.';
    }
  }

  static RecoveryState _buildState() {
    return RecoveryState(
      type: _type,
      phase: _phase,
      diagnostics: _diagnostics,
      statusMessage: _statusMessage,
      canLaunchAnyway: _canLaunchAnyway,
    );
  }

  static void _emit() {
    stateNotifier.value = _buildState();
  }
}
