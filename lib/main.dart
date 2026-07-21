import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'services/session_manager.dart';
import 'core/security/secure_storage_service.dart';
import 'presentation/screens/boot_screen.dart';
import 'presentation/screens/init_failure_screen.dart';
import 'services/api_service.dart';
import 'services/heartbeat_service.dart';
import 'core/security/integrity_verifier.dart';
import 'core/platform/kiosk_service.dart';
import 'core/startup_service.dart';
import 'core/platform/window_orchestrator_service.dart';
import 'services/pre_flight_service.dart';
import 'services/sync_manager.dart';
import 'services/time_sync_service.dart';
import 'services/notification_listener_service.dart';
import 'services/auto_updater.dart';
import 'services/remote_config_service.dart';
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

class InitStatus {
  final bool isar;
  final bool secureStorage;
  final bool dotenv;
  final List<String> errors;

  const InitStatus({
    required this.isar,
    required this.secureStorage,
    required this.dotenv,
    required this.errors,
  });

  bool get isFatal => !isar || !secureStorage;
  String get message {
    if (isFatal) {
      return 'Critical initialization failed. Please reinstall or contact IT.';
    }
    return '';
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final IDeviceRepository globalDeviceRepository;
late final IAuthRepository globalAuthRepository;

void main(List<String> args) {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _traceStartup('main: widgets initialized args=$args');

    final startupGuard = await StartupService.beginLaunch(args);
    _traceStartup(
        'startupGuard: crashLoop=${startupGuard.crashLoopDetected} autoStart=${startupGuard.isAutoStart} failures=${startupGuard.failedLaunches}');
    if (startupGuard.crashLoopDetected) {
      // ── Version-aware rollback check ──────────────────────────────────
      // Before declaring total failure, check if this crash loop was
      // caused by a newly installed version. If so, [UpdateHealthMonitor]
      // will transparently roll back to the previous known-good version
      // and restart the app.
      try {
        final info = await PackageInfo.fromPlatform();
        final currentVer = Version.parse(info.version);
        final rollbackInitiated = await UpdateHealthMonitor.init(currentVer);
        if (rollbackInitiated) {
          // UpdateHealthMonitor._performRollback exits the process.
          // If we get here, rollback failed — fall through to failure screen.
          Log.e('[Startup] Rollback was initiated but did not exit — '
              'proceeding to failure screen.');
        }
      } catch (e) {
        Log.e('[Startup] Rollback check failed: $e');
      }

      await _initWindow();
      await KioskService.forceRelease();
      runApp(InitFailureScreen(message: startupGuard.message));
      return;
    }

    // ─── SINGLE INSTANCE GUARD ──────────────────────────────────────────────
    // On Windows, prevent two copies of the board software running side-by-side
    // (e.g. startup registry entry + manual launch). We use an exclusive file
    // lock in the system temp directory — the OS releases it automatically when
    // the process exits, so no stale-lock problem on crash.
    //
    // The --post-update flag is passed by AutoUpdater._exitApp() after a
    // successful MSI install. The old process is still alive (it hasn't exited
    // yet), so we retry the lock acquisition with a short timeout — the old
    // process exits within 3 seconds.  We no longer skip the guard entirely
    // because that left a window where a third manual launch could start a
    // second concurrent instance.
    final isPostUpdate = args.contains('--post-update');
    if (!kIsWeb && Platform.isWindows) {
      await _acquireSingleInstanceLock(retryForPostUpdate: isPostUpdate);
      _traceStartup('singleInstance: acquired');
    }

    // ─── TIER 1: Blocking (must pass or app can't run) ──────────────────────
    await _initWindow();
    _traceStartup('window: initialized');

    // ─── RESET (--reset flag) ───────────────────────────────────────────────
    // Wipe all persisted state BEFORE Isar / Firestore open. This lets the user
    // start the registration flow from scratch without stale SecureStorage keys
    // or a populated Isar database.
    if (args.contains('--reset')) {
      Log.w('[Startup] --reset flag detected. Wiping all local data...');
      await SecureStorageService.clearAll().catchError((e) {
        Log.e('[Startup] SecureStorage clear failed: $e');
      });
      final isarDir = await getApplicationSupportDirectory();
      if (isarDir.existsSync()) {
        isarDir.deleteSync(recursive: true);
      }
      Log.w('[Startup] Local data wiped. Booting to registration flow.');
    }

    // NOTE: Kiosk fullscreen is intentionally deferred until AFTER Tier-1
    // plugin initialization succeeds. If a native C++ exception is thrown
    // during plugin init, exiting the process while the window is already
    // in fullscreen popup mode leaves DWM in a broken state — taskbar
    // hidden, no visible window, system frozen.  By keeping the window in
    // normal mode during init, any crash during plugin loading allows DWM
    // to recover naturally.
    final status = await _initTier1();
    _traceStartup(
        'tier1: isar=${status.isar} secure=${status.secureStorage} dotenv=${status.dotenv} fatal=${status.isFatal} errors=${status.errors}');

    if (status.isFatal) {
      await StartupService.markLaunchCompleted();
      runApp(InitFailureScreen(message: status.message));
      return;
    }

    // NOTE: Kiosk fullscreen is intentionally deferred until AFTER Tier-2
    // and Integrity checks succeed. If a native C++ exception is thrown
    // during plugin init or a fatal error occurs early, exiting the process
    // while the window is already in fullscreen popup mode leaves DWM in
    // a broken state — taskbar hidden, no visible window, system frozen.
    // By keeping the window in normal mode during early boot, any crash
    // allows DWM to recover naturally.  Fullscreen is applied immediately
    // after integrity verification passes (see below).

    // Register Windows auto-start immediately (before Tier 2) so the
    // registry key is written even if a later step crashes the process.
    // Previously this ran in Tier 3 (fire-and-forget) and was silently
    // skipped when the app crashed.
    if (!kIsWeb && Platform.isWindows) {
      unawaited(StartupService.register().catchError((e) {
        Log.e('❌ [Startup] Registration failed: $e');
      }));
    }

    // ─── Set app version for structured logging ──────────────────────────────
    try {
      final info = await PackageInfo.fromPlatform();
      Log.setAppVersion('${info.version}+${info.buildNumber}');
    } catch (e) {
      Log.w('[Startup] Could not read package version: $e');
    }

    // ─── TIER 2: Timeout-aware (fail gracefully, flag degraded) ─────────────
    await _initTier2();
    _traceStartup('tier2: completed');

    // ─── Runtime Integrity ──────────────────────────────────────────────────
    final tampered = await _verifyIntegrity();
    _traceStartup('integrity: tampered=$tampered');
    if (tampered) {
      await StartupService.markLaunchCompleted();
      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Device Integrity Check Failed',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Contact IT Support. Code: TAMPER-01'),
              ],
            ),
          ),
        ),
      ));
      return;
    }

    // Integrity and Tiers 1-2 passed — enable kiosk hardening and go
    // fullscreen immediately so the taskbar is never visible.  The
    // skipTaskbar:true in _initWindow() already hides the taskbar button;
    // this call covers the entire screen and blocks close/sys commands.
    KioskService.enable();
    await KioskService.setMode(KioskMode.fullscreen);
    _traceStartup('kiosk: enabled, fullscreen applied');

    // ─── Create repositories & mount app ────────────────────────────────────
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

    // ─── TIER 3: Fire-and-forget (don't block UI) ──────────────────────────
    _initTier3();
    _traceStartup('tier3: started');

    // ─── Startup watchdog ──────────────────────────────────────────────────
    // If the app does not reach a stable state (startBackgroundProtocols
    // completes) within 45 seconds, forcibly release all kiosk constraints
    // so the user can close the window. This prevents the "frozen fullscreen
    // with no taskbar icon" scenario even when the event loop is alive but
    // startup is blocked (e.g. BootScreen stuck on network timeout).
    _startStartupWatchdog();
  }, (Object error, StackTrace stack) {
    Log.e('🔥 Unhandled application error', error, stack);
    unawaited(
        StartupService.markLaunchFailed('Unhandled application error: $error'));
    _traceStartup('zone error: $error\n$stack');
    unawaited(KioskService.forceRelease());
  });
}

void _traceStartup(String message) {
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

/// Tracks whether startup has reached a stable state.  Set to true after
/// [startBackgroundProtocols] completes.  Reset to false on each full restart.
bool _startupCompleted = false;

/// Starts a one-shot timer that force-releases kiosk constraints if
/// [_startupCompleted] is not set within 60 seconds of app launch.
void _startStartupWatchdog() {
  Future.delayed(const Duration(seconds: 60), () async {
    if (!_startupCompleted) {
      Log.w('🚨 [Startup] Watchdog fired — startup not complete after 60s. '
          'Releasing kiosk constraints.');
      _traceStartup('watchdog: startup incomplete after 60s');
      await StartupService.markLaunchFailed('Startup watchdog timed out.');
      await KioskService.forceRelease();
      // Show error screen with retry option
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const InitFailureScreen(
            message: 'Startup timed out. The board will retry automatically.',
          ),
        ),
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
  final lockFile =
      File('${Directory.systemTemp.path}/intelliattend_smartboard.lock');

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

// ─── TIER 1: Blocking init steps ─────────────────────────────────────────

Future<void> _initWindow() async {
  try {
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await windowManager.ensureInitialized();

      // Set initial window to 1920×1080 (the most common kiosk resolution)
      // so Flutter's MediaQuery has correct logical dimensions from the
      // very first frame.  Without explicit sizing, the window opens at a
      // default 800×600 and switching to fullscreen moments later can
      // leave MediaQuery with stale dimensions on certain Windows
      // DPI / multi-monitor configurations — causing stretched / clipped
      // layouts.
      //
      // skipTaskbar: true hides the taskbar button from the start so the
      // taskbar is never visible during boot.  Fullscreen is applied
      // later after Tier-1 + Tier-2 + integrity checks pass.
      final windowReady = Completer<void>();
      windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: const Size(1920, 1080),
          minimumSize: const Size(800, 600),
          center: true,
          titleBarStyle: TitleBarStyle.hidden,
          skipTaskbar: true,
          backgroundColor: AppColors.bgLight,
        ),
        () async {
          try {
            await windowManager.show();
            await windowManager.focus();
          } finally {
            if (!windowReady.isCompleted) windowReady.complete();
          }
        },
      );
      await windowReady.future;
    }
  } catch (e) {
    Log.w('[WindowManager] Init error: $e');
  }
}

Future<InitStatus> _initTier1() async {
  final errors = <String>[];

  final dotenvOk = await _tryInit('Environment', _loadEnvironment);
  if (!dotenvOk) errors.add('Environment');

  final secureOk = await _tryInit('Secure Storage', _initSecureStorage);
  if (!secureOk) errors.add('SecureStorage');

  final isarOk = await _tryInit('Local Vault', _initLocalVault);
  if (!isarOk) errors.add('Isar');

  return InitStatus(
    isar: isarOk,
    secureStorage: secureOk,
    dotenv: dotenvOk,
    errors: errors,
  );
}

// ─── TIER 2: Timeout-aware init steps ────────────────────────────────────

Future<void> _initTier2() async {
  _configureOrientation();

  await _tryInit(
    'Time Sync',
    TimeSyncService.init,
    timeout: const Duration(seconds: 3),
  );

  // Restore cached remote config from SharedPreferences so feature flags
  // are available before the first heartbeat completes. This is a fast,
  // non-blocking read — typically <5 ms.
  await _tryInit(
    'Remote Config',
    RemoteConfigService.init,
    timeout: const Duration(seconds: 2),
  );
}

// ─── TIER 3: Fire-and-forget (non-blocking) ──────────────────────────────

void _initTier3() {
  unawaited(HeartbeatService.start(globalDeviceRepository).catchError((e) {
    Log.e('❌ [Tier3] Heartbeat start failed: $e');
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

    // Initialise the auto-update subsystem. [AutoUpdater.init] reads the
    // current installed version; [UpdateChecker.start] begins polling the
    // server manifest (already cached by [RemoteConfigService.init]) so
    // any pending forced update is caught within seconds of launch.
    await AutoUpdater.init(boardId: boardId);

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
    Log.e('❌ [Protocols] Background initialization failed: $e');
  } finally {
    _startupCompleted = true;
    await StartupService.markLaunchCompleted();
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

Future<bool> _tryInit(
  String name,
  Future<void> Function() fn, {
  Duration? timeout,
}) async {
  try {
    if (timeout != null) {
      await fn().timeout(timeout);
    } else {
      await fn();
    }
    return true;
  } catch (e) {
    if (e is TimeoutException) {
      Log.w('⚠️ [$name] Timed out after ${timeout?.inSeconds}s');
    } else {
      Log.e('❌ [$name] Initialization failed: $e');
    }
    return false;
  }
}

Future<bool> _verifyIntegrity() async {
  bool tampered = false;

  if (!IntegrityVerifier.verify()) {
    Log.e(
        '🚨 [Integrity] Critical constants hash mismatch — possible tampering');
    tampered = true;
  }

  if (!tampered) {
    try {
      final sigValid = await IntegrityVerifier.verifyCodeSignature()
          .timeout(const Duration(seconds: 5));
      if (!sigValid) {
        Log.e('🚨 [Integrity] Code signature invalid — binary modified');
        tampered = true;
      }
    } catch (e) {
      Log.w('⚠️ [Integrity] Signature verification skipped ($e)');
    }
  }

  if (tampered) {
    await SecureStorageService.clearAll();
  }
  return tampered;
}

// Firebase init removed — auth is handled by FirebaseRestAuth
// (Identity Toolkit + Secure Token API over HTTPS) which requires no
// Flutter Firebase plugins. Timetable data is fetched via REST APIs.

Future<void> _loadEnvironment() async {
  bool loaded = false;

  // Production machine-local config. This survives MSI upgrades because it's
  // stored outside the install directory at:
  //   %LOCALAPPDATA%\IntelliAttendSmartBoard\.env
  // The install_production_msi.ps1 script writes this file before launching.
  if (!kIsWeb && Platform.isWindows) {
    try {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Local';
      final envPath = '$localAppData\\IntelliAttendSmartBoard\\.env';
      await dotenv.load(fileName: envPath);
      loaded = dotenv.env.isNotEmpty;
      if (loaded) {
        Log.i('[Startup] Environment loaded from: $envPath');
      }
    } catch (e) {
      Log.d('[Startup] Local .env not found at expected path: $e');
    }
  }
  // Try loading from Flutter assets (legacy path — .env may be bundled here
  // for development builds, but production should use the path above).
  if (!loaded) {
    try {
      await dotenv.load();
      loaded = dotenv.env.isNotEmpty;
      if (loaded) {
        Log.i('[Startup] Environment loaded from Flutter assets (legacy)');
      }
    } catch (_) {}
  }

  // Fall back to filesystem .env (development / local builds only).
  if (!loaded) {
    try {
      await dotenv.load(fileName: '.env');
      loaded = dotenv.env.isNotEmpty;
      if (loaded) {
        Log.i('[Startup] Environment loaded from CWD/.env');
      }
    } catch (_) {}
  }

  // Last resort: try the directory next to the running executable.
  if (!loaded && !kIsWeb && Platform.isWindows) {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      await dotenv.load(fileName: '$exeDir\\.env');
      loaded = dotenv.env.isNotEmpty;
      if (loaded) {
        Log.i('[Startup] Environment loaded from exe directory');
      }
    } catch (_) {}
  }

  if (!loaded) {
    Log.w('[Startup] No .env file found — using --dart-define fallbacks.');
  }
  AppConfig.validate();
  Log.i('[Startup] Environment config ready');
}

void _configureOrientation() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

Future<void> _initSecureStorage() async {
  await SecureStorageService.init();
  Log.i('[Startup] Secure storage initialized');
}

Future<void> _initLocalVault() async {
  await SessionManager.init();
  Log.i('[Startup] Local vault initialized');
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
      home: const BootScreen(),
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
