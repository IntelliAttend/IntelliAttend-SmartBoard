import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/install_paths.dart';
import '../observability/observability_manager.dart';
import '../startup_service.dart';
import '../utils/logger.dart';
import 'lifecycle_phase.dart';
import 'lifecycle_recover.dart';
import 'lifecycle_phases.dart';

/// Central authority for the application's runtime lifecycle.
///
/// Every launch transitions through deterministic phases. Each phase is
/// timed, logged, and produces a result that determines the next state.
/// The manager is the single source of truth for what state the app is in.
///
/// ```text
/// BOOT -> RECOVERY -> VALIDATION -> CONFIGURATION -> DATABASE
///   -> WINDOW -> READY
/// ```
///
/// Recovery paths:
///   - Stale update state: cleaned in RECOVERY phase
///   - Crash loop detected: skip to READY with recovery UI
///   - Integrity failed: transition to FAILED
///   - Fatal database error: transition to FAILED
class AppLifecycleManager {
  AppLifecycleManager._();

  // ── State ─────────────────────────────────────────────────────────────────

  static AppLifecyclePhase _currentPhase = AppLifecyclePhase.boot;
  static final List<PhaseTiming> _timings = [];
  static DateTime? _startedAt;
  static String? _appVersion;
  static bool _completed = false;

  /// Crash loop result from the RECOVERY phase. Downstream phases
  /// (CONFIGURATION, DATABASE, etc.) check this to skip non-essential work.
  static StartupLaunchGuardResult? _guardResult;

  // ── Public API ────────────────────────────────────────────────────────────

  static AppLifecyclePhase get currentPhase => _currentPhase;
  static String? get appVersion => _appVersion;
  static bool get isCompleted => _completed;
  static List<PhaseTiming> get timings => List.unmodifiable(_timings);
  static StartupLaunchGuardResult? get guardResult => _guardResult;

  static Duration get elapsed =>
      _startedAt != null ? DateTime.now().difference(_startedAt!) : Duration.zero;

  /// Run the full lifecycle. Returns the final phase.
  static Future<AppLifecyclePhase> run({
    required List<String> args,
    required Future<void> Function(String message) onCrashLoop,
    required Future<void> Function() onReady,
  }) async {
    _startedAt = DateTime.now();
    _timings.clear();
    _completed = false;
    _guardResult = null;

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }

    _logBanner('BOOT starting (v$_appVersion)');

    // ── Phase 1: BOOT ─────────────────────────────────────────────────
    final bootResult = await _runPhase(AppLifecyclePhase.boot, () async {
      await InstallPaths.ensureDirectories();
      _trace('boot: directories ensured');
      return const PhaseResult.ok();
    });
    if (bootResult.transitionToShutdown) {
      return _complete(AppLifecyclePhase.shutdown);
    }

    // ── Phase 2: RECOVERY ─────────────────────────────────────────────
    final recoveryResult = await _runPhase(AppLifecyclePhase.recovery, () async {
      await LifecycleRecover.recoverFromStaleUpdateState();
      _trace('recovery: stale update state resolved');

      await LifecycleRecover.runPathMigration();
      _trace('recovery: migration complete');

      final guard = await LifecycleRecover.detectCrashLoop(args);
      _guardResult = guard;
      _trace('recovery: crashLoop=${guard.crashLoopDetected} '
          'autoStart=${guard.isAutoStart} failures=${guard.failedLaunches}');

      if (guard.crashLoopDetected) {
        return PhaseResult.skipToReady();
      }
      return const PhaseResult.ok();
    });

    if (recoveryResult.skipToReady) {
      final msg = _guardResult?.message ?? 'Crash loop detected';
      await onCrashLoop(msg);
      return _complete(AppLifecyclePhase.ready);
    }

    // ── Phase 3: VALIDATION ───────────────────────────────────────────
    final validationResult = await _runPhase(AppLifecyclePhase.validation, () async {
      final tampered = await LifecyclePhases.verifyIntegrity();
      _trace('validation: tampered=$tampered');
      if (tampered) return PhaseResult.fail('Integrity check failed');
      return const PhaseResult.ok();
    });
    if (!validationResult.success) {
      return _complete(AppLifecyclePhase.failed);
    }

    // ── Phase 4: CONFIGURATION ────────────────────────────────────────
    await _runPhase(AppLifecyclePhase.configuration, () async {
      await LifecyclePhases.loadEnvironment();
      _trace('configuration: environment loaded');

      if (!kIsWeb && Platform.isWindows) {
        unawaited(LifecyclePhases.registerAutoStart().catchError((e) {
          Log.e('[Lifecycle] Auto-start registration failed: $e');
        }));
      }

      Log.i('[Lifecycle] App version: $_appVersion');
      return const PhaseResult.ok();
    });

    // ── Phase 5: DATABASE ─────────────────────────────────────────────
    final dbResult = await _runPhase(AppLifecyclePhase.database, () async {
      await LifecyclePhases.initSecureStorage();
      _trace('database: secure storage initialized');

      await LifecyclePhases.initLocalVault();
      _trace('database: local vault initialized');
      return const PhaseResult.ok();
    });
    if (!dbResult.success) {
      return _complete(AppLifecyclePhase.failed);
    }

    // ── Phase 6: WINDOW ───────────────────────────────────────────────
    await _runPhase(AppLifecyclePhase.window, () async {
      await LifecyclePhases.initWindow();
      _trace('window: initialized');
      return const PhaseResult.ok();
    });

    // ── Complete ──────────────────────────────────────────────────────
    _completed = true;
    _logBanner('READY (${elapsed.inMilliseconds}ms)');
    _logTimings();

    await onReady();
    return _complete(AppLifecyclePhase.ready);
  }

  // ── Phase execution ──────────────────────────────────────────────────────

  static Future<PhaseResult> _runPhase(
    AppLifecyclePhase phase,
    Future<PhaseResult> Function() execute,
  ) async {
    _currentPhase = phase;
    ObservabilityManager.setLifecyclePhase(phase);
    ObservabilityManager.lifecycleBreadcrumb(phase, detail: 'started');
    final start = DateTime.now();
    try {
      final result = await execute();
      final timing = PhaseTiming(
        phase: phase,
        duration: DateTime.now().difference(start),
        startedAt: start,
        completedAt: DateTime.now(),
      );
      _timings.add(timing);
      ObservabilityManager.lifecycleBreadcrumb(phase,
          detail: '${result.success ? "OK" : "FAIL"} '
              '(${timing.duration.inMilliseconds}ms)');
      Log.d('[Lifecycle] ${timing.phase.name}: '
          '${timing.duration.inMilliseconds}ms ${result.success ? "OK" : "FAIL"}');
      return result;
    } catch (e, stack) {
      final timing = PhaseTiming(
        phase: phase,
        duration: DateTime.now().difference(start),
        startedAt: start,
        completedAt: DateTime.now(),
      );
      _timings.add(timing);
      Log.e('[Lifecycle] ${phase.name} CRASHED after '
          '${timing.duration.inMilliseconds}ms: $e');
      Log.e('[Lifecycle] Stack: $stack');
      return PhaseResult.fail(e.toString());
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static AppLifecyclePhase _complete(AppLifecyclePhase phase) {
    _currentPhase = phase;
    return phase;
  }

  static void _logBanner(String message) {
    Log.i('═══════════════════════════════════════════════════════════');
    Log.i('Lifecycle: $message');
    Log.i('═══════════════════════════════════════════════════════════');
  }

  static void _logTimings() {
    Log.i('[Lifecycle] Phase timings:');
    for (final t in _timings) {
      Log.i('  ${t.phase.name.padRight(16)} ${t.duration.inMilliseconds}ms');
    }
    Log.i('[Lifecycle] Total: ${elapsed.inMilliseconds}ms');
  }

  static void _trace(String message) {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final dir = File(Platform.resolvedExecutable).parent;
      final file = File('${dir.path}\\startup_trace.log');
      final now = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$now] $message\n', mode: FileMode.append);
    } catch (_) {
      // Startup tracing must never affect app launch.
    }
  }
}
