import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/theme/app_theme.dart';
import 'core/config/install_paths.dart';
import 'core/utils/logger.dart';
import 'core/lifecycle/app_lifecycle_manager.dart';
import 'core/lifecycle/lifecycle_phase.dart';
import 'core/lifecycle/lifecycle_recover.dart';
import 'core/recovery/recovery_manager.dart';
import 'core/recovery/recovery_state.dart';
import 'core/observability/observability_manager.dart';
import 'core/config/enterprise_deploy_config.dart';
import 'services/session_manager.dart';
import 'core/security/secure_storage_service.dart';
import 'presentation/screens/boot_screen.dart';
import 'presentation/screens/attendance_screen.dart';
import 'presentation/screens/workspace_screen.dart';
import 'presentation/screens/recovery_screen.dart';
import 'services/api_service.dart';
import 'services/heartbeat_service.dart';
import 'core/platform/kiosk_service.dart';
import 'core/platform/window_orchestrator_service.dart';
import 'services/pre_flight_service.dart';
import 'services/sync_manager.dart';
import 'services/time_sync_service.dart';
import 'services/notification_listener_service.dart';
import 'services/auto_updater.dart' hide UpdateState;
import 'services/update_checker.dart';
import 'services/update_health_monitor.dart';
import 'core/utils/version.dart';
import 'package:provider/provider.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/device_repository.dart';
import 'core/network/api_client.dart';
import 'presentation/providers/registration_provider.dart';
import 'presentation/widgets/shutdown_countdown_overlay.dart';
import 'presentation/widgets/emergency_overlay.dart';
import 'presentation/widgets/priority_one_overlay.dart';
import 'presentation/widgets/update_overlay.dart';
import 'core/platform/power_command_service.dart';

/// Global kill switch: tracks Ctrl+Shift+JJJ sequence from any screen.
/// When triggered, releases kiosk mode and navigates to BootScreen.
class GlobalKillSwitch extends StatefulWidget {
  final Widget child;
  const GlobalKillSwitch({super.key, required this.child});

  @override
  State<GlobalKillSwitch> createState() => _GlobalKillSwitchState();
}

class _GlobalKillSwitchState extends State<GlobalKillSwitch> {
  final FocusNode _focusNode = FocusNode();
  int _jCount = 0;
  Timer? _resetTimer;

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final ctrl = HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.controlRight);
    final shift = HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.shiftRight);
    final isJ = event.logicalKey == LogicalKeyboardKey.keyJ;

    if (!ctrl || !shift || !isJ) {
      if (_jCount > 0) {
        _jCount = 0;
        _resetTimer?.cancel();
      }
      return;
    }

    _jCount++;
    _resetTimer?.cancel();

    if (_jCount >= 3) {
      _jCount = 0;
      Log.w(
          '🚨 [GlobalKillSwitch] Emergency exit triggered by keyboard (Ctrl+Shift+JJJ).');
      KioskService.executeAdministrativeShutdown();
      return;
    }

    _resetTimer = Timer(const Duration(seconds: 3), () {
      _jCount = 0;
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final IDeviceRepository globalDeviceRepository;
late final IAuthRepository globalAuthRepository;

/// When true, skips full lifecycle and shows AttendanceScreen directly for UI iteration.
bool kPreviewAttendance = false;
bool kPreviewWorkspace = false;

void main(List<String> args) {
  if (args.contains('--exit')) {
    print('[Main] --exit flag received. Shutting down gracefully.');
    exit(0);
  }

  // Preview mode: skip full lifecycle, jump straight to a screen for UI iteration.
  // Usage: flutter run -d windows --dart-define=PREVIEW=attendance
  //        flutter run -d windows --dart-define=PREVIEW=workspace
  final previewMode = const String.fromEnvironment('PREVIEW', defaultValue: '');
  if (previewMode.isNotEmpty) {
    WidgetsFlutterBinding.ensureInitialized();
    if (previewMode == 'workspace') {
      kPreviewWorkspace = true;
    } else {
      kPreviewAttendance = true;
    }
    runApp(const IntelliAttendApp());
    return;
  }

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ─── OBSERVABILITY (Sentry) ─────────────────────────────────────────
    // Initialise Sentry before the lifecycle manager so crashes during
    // startup are captured. DSN is read from env.json at runtime; for
    // now we use the environment variable or leave disabled.
    const sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
    await ObservabilityManager.init(dsn: sentryDsn.isEmpty ? null : sentryDsn);

    // ─── LIFECYCLE MANAGER ──────────────────────────────────────────────
    // The lifecycle manager is the single authority for startup. It owns
    // every phase: directories, recovery, validation, config, database,
    // window. Each phase is timed and logged.
    final phase = await AppLifecycleManager.run(
      args: args,
      onCrashLoop: (message) async {
        // Crash loop detected — initialise recovery manager and show
        // the recovery screen with full diagnostics.
        await _showRecovery(
          type: RecoveryType.crashLoop,
          args: args,
          diagnostics: RecoveryDiagnostics.fromGuard(
            appVersion: AppLifecycleManager.appVersion,
            guard: AppLifecycleManager.guardResult!,
            failedPhase: AppLifecycleManager.currentPhase,
            errorMessage: message,
            timings: AppLifecycleManager.timings,
            elapsed: AppLifecycleManager.elapsed,
          ),
        );
      },
      onReady: () async {
        // ─── POST-LIFECYCLE: Kiosk + Repos + UI ─────────────────────────
        await _postLifecycleStartup(args);
      },
    );

    // If lifecycle didn't reach READY, show the recovery screen.
    // This covers validation failures, database errors, and any
    // other phase that returns PhaseResult.fail().
    if (phase != AppLifecyclePhase.ready) {
      await _showRecovery(
        type: RecoveryType.lifecycleFailure,
        args: args,
        diagnostics: RecoveryDiagnostics.fromFailure(
          appVersion: AppLifecycleManager.appVersion,
          failedPhase: AppLifecycleManager.currentPhase,
          errorMessage: 'Lifecycle stopped at ${phase.name}',
          timings: AppLifecycleManager.timings,
          elapsed: AppLifecycleManager.elapsed,
        ),
      );
    }
  }, (Object error, StackTrace stack) {
    Log.e('Unhandled application error', error, stack);
    unawaited(ObservabilityManager.captureException(error, stackTrace: stack));
    unawaited(LifecycleRecover.markLaunchFailed('Unhandled: $error'));
    unawaited(KioskService.forceRelease());
  });
}

/// Show the recovery screen. Handles rollback attempt, kiosk release,
/// and RecoveryManager initialisation.
Future<void> _showRecovery({
  required RecoveryType type,
  required RecoveryDiagnostics diagnostics,
  List<String> args = const [],
}) async {
  // Attempt rollback if this is an update-related crash loop.
  if (type == RecoveryType.crashLoop) {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVer = Version.parse(info.version);
      final rollbackInitiated = await UpdateHealthMonitor.init(currentVer);
      if (rollbackInitiated) {
        Log.e('[Main] Rollback initiated — exiting for restart');
        return;
      }
    } catch (e) {
      Log.e('[Main] Rollback check failed: $e');
    }
    await LifecycleRecover.markLaunchCompleted();
  }

  await KioskService.forceRelease();

  // Initialise the recovery manager — it drives the state machine
  // and handles automatic recovery / user actions.
  await RecoveryManager.init(
    type: type,
    diagnostics: diagnostics,
    onRelaunch: () {
      // Relaunch the full app lifecycle.
      main(args);
    },
  );

  runApp(const RecoveryScreen());
}

/// Post-lifecycle startup: kiosk hardening, repositories, UI, services.
///
/// Called by the lifecycle manager's onReady callback after all phases
/// have completed successfully.
Future<void> _postLifecycleStartup(List<String> args) async {
  // ─── RESET (--reset flag) ─────────────────────────────────────────────
  if (args.contains('--reset')) {
    Log.w('[Main] --reset flag detected. Wiping all local data...');
    await SecureStorageService.clearAll().catchError((e) {
      Log.e('[Main] SecureStorage clear failed: $e');
    });
    final isarDir = await getApplicationSupportDirectory();
    if (isarDir.existsSync()) {
      isarDir.deleteSync(recursive: true);
    }
    Log.w('[Main] Local data wiped. Booting to registration flow.');
  }

  // ─── SINGLE INSTANCE GUARD ────────────────────────────────────────────
  final isPostUpdate = args.contains('--post-update');
  if (!kIsWeb && Platform.isWindows) {
    await _acquireSingleInstanceLock(retryForPostUpdate: isPostUpdate);
  }

  // ─── KIOSK HARDENING ──────────────────────────────────────────────────
  KioskService.enable();
  await KioskService.setMode(KioskMode.fullscreen);

  // ─── REPOSITORIES & UI ────────────────────────────────────────────────
  final apiClient = ApiClient();
  globalAuthRepository = AuthRepository(apiClient);
  globalDeviceRepository =
      DeviceRepository(SessionManager.isar, globalAuthRepository);
  unawaited(globalDeviceRepository.performMigrationBridge());

  runApp(
    GlobalKillSwitch(
      child: MultiProvider(
        providers: [
          Provider<IDeviceRepository>.value(value: globalDeviceRepository),
          Provider<IAuthRepository>.value(value: globalAuthRepository),
          ChangeNotifierProvider(
              create: (_) => RegistrationProvider(
                  globalAuthRepository, globalDeviceRepository)),
        ],
        child: const IntelliAttendApp(),
      ),
    ),
  );

  // ─── FIRE-AND-FORGET SERVICES ────────────────────────────────────────
  _initFireAndForget();
  _startStartupWatchdog();
}

/// Starts a one-shot timer that force-releases kiosk constraints if
/// startup is not complete within 60 seconds of app launch.
void _startStartupWatchdog() {
  Future.delayed(const Duration(seconds: 60), () async {
    if (!AppLifecycleManager.isCompleted) {
      Log.w('[Main] Watchdog fired - startup not complete after 60s');
      await LifecycleRecover.markLaunchFailed('Startup watchdog timed out.');
      await KioskService.forceRelease();

      // Show the recovery screen with startup timeout diagnostics.
      await RecoveryManager.init(
        type: RecoveryType.startupTimeout,
        diagnostics: RecoveryDiagnostics.fromFailure(
          appVersion: AppLifecycleManager.appVersion,
          failedPhase: AppLifecycleManager.currentPhase,
          errorMessage: 'Startup timed out after 60s',
          timings: AppLifecycleManager.timings,
          elapsed: AppLifecycleManager.elapsed,
        ),
      );

      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RecoveryScreen()),
        (_) => false,
      );
    }
  });
}

// ─── Single-instance guard ───────────────────────────────────────────────
//
// We write the current process's PID into the lock file after acquiring an
// exclusive OS file-lock on it. On a subsequent launch, if the lock cannot
// be acquired we read the PID inside the file and verify with the OS that
// the process is still alive. If the previous run aborted (the C++ runtime
// can take down a process without releasing the lock cleanly on some
// Windows builds) the PID is dead and the file is stale — we delete it and
// retry the acquire. This replaces the mtime-based stale-lock check, which
// was a heuristic; PID liveness is authoritative.

Future<void> _acquireSingleInstanceLock(
    {bool retryForPostUpdate = false}) async {
  final lockFile = InstallPaths.lockFileInstance;

  Future<RandomAccessFile?> tryAcquire() async {
    try {
      // Use append mode (not write) to avoid truncating the file before
      // acquiring the lock. If we truncated first and then failed to lock,
      // the running instance's PID would be destroyed, making the stale-
      // lock check read an empty file and incorrectly assume the lock is
      // stale — allowing a second instance to start.
      final raf = await lockFile.open(mode: FileMode.append);
      try {
        await raf.lock(FileLock.exclusive);
        // Lock acquired — file is ours. Clear any leftover content and
        // write our PID so the next launch can verify liveness.
        await raf.setPosition(0);
        await raf.truncate(0);
        await raf.writeString('$pid\n');
        await raf.flush();
        return raf; // Caller keeps the ref alive for the process lifetime.
      } on FileSystemException {
        await raf.close();
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  // Fast path: first attempt.
  var raf = await tryAcquire();
  if (raf != null) {
    _retainedLock = raf;
    return;
  }

  // Slow path: lock is held by something. Read its PID; if dead, the lock
  // is stale and we can take it.
  int? heldPid;
  try {
    final contents = await lockFile.readAsString();
    final firstLine = contents.split('\n').first.trim();
    heldPid = int.tryParse(firstLine);
  } catch (e) {
    Log.w('[SingleInstance] Could not read lock file: $e');
  }

  final alive = heldPid != null && await _isProcessAlive(heldPid);
  if (alive) {
    if (retryForPostUpdate) {
      // The old process is exiting after an auto-update (up to 3s).
      // Poll the lock until it's released or we time out.
      Log.i('[SingleInstance] Lock held by PID $heldPid (post-update). '
          'Waiting for old process to exit...');
      const maxWait = Duration(seconds: 8);
      const pollInterval = Duration(milliseconds: 500);
      final deadline = DateTime.now().add(maxWait);
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(pollInterval);
        raf = await tryAcquire();
        if (raf != null) {
          _retainedLock = raf;
          Log.i('[SingleInstance] Lock acquired after post-update wait.');
          return;
        }
      }
      // Timed out — old process is stuck or something else holds the lock.
      Log.e('[SingleInstance] Timed out waiting for old process to exit. '
          'Exiting to prevent dual instances.');
      exit(0);
    }
    Log.w(
        '[SingleInstance] Another instance is running (PID $heldPid). Exiting.');
    exit(0);
  }

  // Stale lock — the recorded PID is no longer running. Delete and retry.
  Log.i('[SingleInstance] Removed stale lock (dead PID $heldPid).');
  try {
    await lockFile.delete();
  } catch (e) {
    Log.w('[SingleInstance] Could not delete stale lock file: $e');
  }
  raf = await tryAcquire();
  if (raf != null) {
    _retainedLock = raf;
  } else {
    // Another instance grabbed the lock between our delete and retry,
    // or the OS hasn't fully released the old lock yet.  Exiting is the
    // only safe option — continuing without the guard allows two live
    // instances, which corrupts shared state (Isar DB, SecureStorage,
    // Firestore listeners, kiosk mode).
    Log.e(
        '[SingleInstance] Could not acquire lock after stale cleanup. Another instance may have started. Exiting.');
    exit(0);
  }
}

/// Whether the given Windows PID is currently running. Uses `tasklist` —
/// adds ~100 ms at startup but avoids pulling in dart:ffi / win32 for a
/// once-per-launch check.
Future<bool> _isProcessAlive(int targetPid) async {
  try {
    final result = await Process.run(
      'tasklist',
      ['/FI', 'PID eq $targetPid', '/FO', 'CSV', '/NH'],
    ).timeout(const Duration(seconds: 3));
    final out = result.stdout.toString();
    // `tasklist` returns "INFO: No tasks are running..." when no match.
    if (out.contains('No tasks') || out.trim().isEmpty) return false;
    // Otherwise the CSV has the matching process name on its first column.
    return out.contains('"');
  } catch (_) {
    // If tasklist isn't available we conservatively assume the process is
    // alive — better to refuse a launch than to clobber a live instance.
    return true;
  }
}

/// Held for the process lifetime so the OS file-lock isn't released until
/// the process exits.
// ignore: unused_element
RandomAccessFile? _retainedLock;

// ─── Fire-and-forget services ────────────────────────────────────────────

void _initFireAndForget() {
  unawaited(HeartbeatService.start(globalDeviceRepository).catchError((e) {
    Log.e('[Main] Heartbeat start failed: $e');
  }));

  // Background protocols (timetable/notification listeners, window orchestrator,
  // pre-flight, time sync) are started from IdleScreen's post-frame callback
  // to avoid window_manager platform-channel races during startup.
}

/// IdleScreen calls this from a post-frame callback so background protocols
/// start after the first frame is rendered, not during app launch. This avoids
/// window_manager platform-channel races: WindowOrchestratorService._tick()
/// calls windowManager methods (setMode, isMinimized, etc.) on every cycle,
/// and if multiple services touch native platform channels simultaneously
/// during startup the Flutter engine can lose its connection.
Future<void> startBackgroundProtocols() async {
  try {
    final registration = await globalDeviceRepository.getRegistration();
    if (registration == null) return;

    final queryId = registration.classroomId ?? registration.smartBoardId;
    SyncManager().init(queryId);
    final boardId = registration.smartBoardId;

    // Configure Sentry fleet-scale tags. Pulls location metadata from
    // deploy_config.json if present (school, building, room). These tags
    // enable filtering the Sentry dashboard by school, building, version,
    // channel, and OS — essential for fleet-scale observability.
    final deployConfig = await EnterpriseDeployConfig.loadFromFile(
      '${InstallPaths.configDir}\\deploy_config.json',
    );
    ObservabilityManager.configureFleetTags(
      boardId: boardId,
      appVersion: AppLifecycleManager.appVersion ?? 'unknown',
      channel: deployConfig?.update.channel ?? 'stable',
      osVersion: Platform.operatingSystemVersion,
      school: deployConfig?.location?.school,
      building: deployConfig?.location?.building,
      room: deployConfig?.location?.room,
      deploymentId: deployConfig?.deployment?.deploymentId,
      buildNumber: const String.fromEnvironment('BUILD_NUMBER'),
      gitCommit: const String.fromEnvironment('GIT_COMMIT'),
      buildDate: const String.fromEnvironment('BUILD_DATE'),
    );

    // Initialise the auto-update subsystem. [AutoUpdater.init] reads the
    // current installed version; [UpdateChecker.start] begins polling the
    // server manifest (already cached by [RemoteConfigService.init]) so
    // any pending forced update is caught within seconds of launch.
    await AutoUpdater.init(boardId: boardId);

    // Wire update state to Sentry tag for fleet observability.
    // When crashes cluster around a particular update phase, the
    // update.state tag identifies it immediately.
    AutoUpdater.progress.addListener(() {
      final state = AutoUpdater.progress.value?.state;
      ObservabilityManager.setUpdateState(state?.name ?? 'idle');
    });

    // Initialise the update health monitor with the current version. This
    // detects whether this is the first launch after an update and tracks
    // crash loops that are specific to the new version.
    await UpdateHealthMonitor.init(AutoUpdater.installedVersion);

    UpdateChecker.start();

    await globalDeviceRepository.hydrateFromServer();

    await NotificationListenerService().start(boardId);

    PowerCommandService().init();
    PreFlightService().startCountdownWatcher();
    WindowOrchestratorService().start();
    _startPeriodicTimeSync();

    Log.i(
        '🚀 [Protocols] Background Synchronization, Countdown Watchers, Window Orchestrator, and Time Sync active.');

    // Mark the startup as successful for the update health monitor. After
    // N consecutive successful starts, the current version is considered
    // "stable" and the rollback backup is deleted.
    await UpdateHealthMonitor.markStartupSuccessful();
  } catch (e) {
    Log.e('[Protocols] Background initialization failed: $e');
  } finally {
    await LifecycleRecover.markLaunchCompleted();
  }
}

/// Clock re-sync to prevent drift during long idle periods.
/// Runs immediately on boot (if cached skew is stale) and every 30 minutes.
Timer? _timeSyncTimer;
void _startPeriodicTimeSync() {
  _timeSyncTimer?.cancel();

  // Force an immediate sync if the cached skew is >1 hour old or missing
  if (TimeSyncService.isSkewStale) {
    Log.i('[TimeSync] Cached skew stale — forcing initial sync...');
    _doTimeSync();
  }

  _timeSyncTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
    await _doTimeSync();
  });
}

Future<void> _doTimeSync() async {
  try {
    final result = await ApiService.syncTime();
    // Feed the server timestamp back into TimeSyncService to update drift
    if (result > 0) {
      final now = DateTime.now();
      TimeSyncService.synchronizeWithServerLegacy(
        now.subtract(const Duration(seconds: 2)),
        now,
        result,
      );
    }
  } catch (e) {
    Log.w('[TimeSync] Periodic sync failed: $e');
  }
}

// ─── Shared helpers ──────────────────────────────────────────────────────

class _PreviewAttendanceScreen extends StatelessWidget {
  const _PreviewAttendanceScreen();

  @override
  Widget build(BuildContext context) {
    return AttendanceScreen(
      sessionId: 'preview-session-001',
      capacity: 40,
      courseName: 'CS101 - Data Structures',
      facultyName: 'Dr. Preview',
      roomName: 'Room 301',
      initialPresentCount: 0,
      slotId: 'slot-1',
      boardId: 'preview-board',
    );
  }
}

class _PreviewWorkspaceScreen extends StatelessWidget {
  const _PreviewWorkspaceScreen();

  @override
  Widget build(BuildContext context) {
    return const WorkspaceScreen(
      sessionId: 'preview-session-001',
      courseName: 'CS101 - Data Structures',
      facultyName: 'Dr. Preview',
      roomName: 'Room 301',
      presentCount: 32,
      totalCapacity: 40,
      isAttendanceSubmitted: true,
    );
  }
}

class IntelliAttendApp extends StatelessWidget {
  const IntelliAttendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'IntelliAttend SmartBoard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: kPreviewAttendance
          ? const _PreviewAttendanceScreen()
          : kPreviewWorkspace
              ? const _PreviewWorkspaceScreen()
              : const BootScreen(),
      builder: (context, child) {
        return UpdateOverlay(
          child: EmergencyOverlay(
            child: PriorityOneOverlay(
              child: ShutdownCountdownOverlay(child: child!),
            ),
          ),
        );
      },
    );
  }
}
