import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
import 'services/timetable_cache.dart';
import 'services/timetable_listener_service.dart';
import 'services/time_sync_service.dart';
import 'package:provider/provider.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/device_repository.dart';
import 'core/network/api_client.dart';
import 'presentation/providers/registration_provider.dart';
import 'firebase_options.dart';

class InitStatus {
  final bool firebase;
  final bool isar;
  final bool secureStorage;
  final bool dotenv;
  final List<String> errors;

  const InitStatus({
    required this.firebase,
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
    if (!firebase) {
      return 'Running in offline mode — real-time updates unavailable.';
    }
    return '';
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final IDeviceRepository globalDeviceRepository;
late final IAuthRepository globalAuthRepository;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ─── SINGLE INSTANCE GUARD ──────────────────────────────────────────────
    // On Windows, prevent two copies of the board software running side-by-side
    // (e.g. startup registry entry + manual launch). We use an exclusive file
    // lock in the system temp directory — the OS releases it automatically when
    // the process exits, so no stale-lock problem on crash.
    if (!kIsWeb && Platform.isWindows) {
      await _acquireSingleInstanceLock();
    }

    // ─── TIER 1: Blocking (must pass or app can't run) ──────────────────────
    await _initWindow();
    KioskService.enable();
    final status = await _initTier1();

    if (status.isFatal) {
      runApp(InitFailureScreen(message: status.message));
      return;
    }

    // ─── Set app version for structured logging ──────────────────────────────
    try {
      final info = await PackageInfo.fromPlatform();
      Log.setAppVersion('${info.version}+${info.buildNumber}');
    } catch (_) {}

    // ─── TIER 2: Timeout-aware (fail gracefully, flag degraded) ─────────────
    await _initTier2(status);

    // ─── Runtime Integrity ──────────────────────────────────────────────────
    final tampered = await _verifyIntegrity();
    if (tampered) {
      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Device Integrity Check Failed',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Contact IT Support. Code: TAMPER-01'),
              ],
            ),
          ),
        ),
      ));
      return;
    }

    // ─── Create repositories & mount app ────────────────────────────────────
    final apiClient = ApiClient();
    globalAuthRepository = AuthRepository(apiClient);
    globalDeviceRepository =
        DeviceRepository(SessionManager.isar, globalAuthRepository);
    unawaited(globalDeviceRepository.performMigrationBridge());

    runApp(
      MultiProvider(
        providers: [
          Provider<IDeviceRepository>.value(value: globalDeviceRepository),
          Provider<IAuthRepository>.value(value: globalAuthRepository),
          ChangeNotifierProvider(
              create: (_) => RegistrationProvider(
                  globalAuthRepository, globalDeviceRepository)),
        ],
        child: const IntelliAttendApp(),
      ),
    );

    // ─── TIER 3: Fire-and-forget (don't block UI) ──────────────────────────
    _initTier3();
  }, (Object error, StackTrace stack) {
    Log.e('🔥 Unhandled application error', error, stack);
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

Future<void> _acquireSingleInstanceLock() async {
  final lockFile = File('${Directory.systemTemp.path}/intelliattend_smartboard.lock');

  Future<RandomAccessFile?> tryAcquire() async {
    try {
      final raf = await lockFile.open(mode: FileMode.write);
      try {
        await raf.lock(FileLock.exclusive);
        // Write our PID so the next launch can verify liveness.
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
  } catch (_) {}

  final alive = heldPid != null && await _isProcessAlive(heldPid);
  if (alive) {
    debugPrint('⚠️ [SingleInstance] Another instance is running (PID $heldPid). Exiting.');
    exit(0);
  }

  // Stale lock — the recorded PID is no longer running. Delete and retry.
  debugPrint('🧹 [SingleInstance] Removed stale lock (dead PID $heldPid).');
  try { await lockFile.delete(); } catch (_) {}
  raf = await tryAcquire();
  if (raf != null) {
    _retainedLock = raf;
  } else {
    debugPrint('⚠️ [SingleInstance] Could not acquire lock after stale cleanup. Continuing without guard.');
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
      final windowReady = Completer<void>();
      windowManager.waitUntilReadyToShow(
        // Start hidden so the window is never briefly visible in windowed state.
        // We apply fullscreen first, then show — the user only ever sees the
        // fully-maximised kiosk frame.
        const WindowOptions(
          titleBarStyle: TitleBarStyle.hidden,
          skipTaskbar: false,
        ),
        () async {
          try {
            // Order matters: configure BEFORE show() so the first visible
            // frame is already fullscreen. show() after setFullScreen() works
            // reliably on Windows; the reverse order causes a brief windowed flash.
            await windowManager.setResizable(false);
            await windowManager.setAlwaysOnTop(true);
            await windowManager.setFullScreen(true);
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
    debugPrint('⚠️ [WindowManager] Init error: $e');
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
    firebase: false,
    isar: isarOk,
    secureStorage: secureOk,
    dotenv: dotenvOk,
    errors: errors,
  );
}

// ─── TIER 2: Timeout-aware init steps ────────────────────────────────────

class _Tier2Status {
  final bool firebase;
  final bool timeSync;
  const _Tier2Status({required this.firebase, required this.timeSync});
}

Future<_Tier2Status> _initTier2(InitStatus tier1) async {
  final firebaseOk = await _tryInit(
    'Firebase',
    _initFirebase,
    timeout: const Duration(seconds: 5),
  );

  _configureOrientation();

  await _tryInit(
    'Time Sync',
    TimeSyncService.init,
    timeout: const Duration(seconds: 3),
  );

  return _Tier2Status(firebase: firebaseOk, timeSync: true);
}

// ─── TIER 3: Fire-and-forget (non-blocking) ──────────────────────────────

void _initTier3() {
  unawaited(HeartbeatService.start(globalDeviceRepository).catchError((e) {
    Log.e('❌ [Tier3] Heartbeat start failed: $e');
  }));

  // Re-register Windows auto-start on every launch so the registry key always
  // points to the current executable path (e.g. after a clean build or if the
  // app directory moves).
  if (!kIsWeb && Platform.isWindows) {
    unawaited(StartupService.register().catchError((e) {
      Log.e('❌ [Tier3] Startup registration failed: $e');
    }));
  }

  // Background protocols (SyncManager, WindowOrchestrator, PreFlight) used to
  // start here. They are now started from IdleScreen's post-frame callback so
  // they cannot race against window_manager initialisation. See
  // startBackgroundProtocols() above for the full rationale.
}

/// IdleScreen calls this from a post-frame callback after its first frame is
/// rendered. We deliberately do NOT start any of these at app launch:
///
///   - SyncManager opens a Firestore listener which triggers a Firebase Auth
///     token fetch. On Windows the auth callback arrives on a non-platform
///     thread; if it races with window_manager native calls during startup,
///     the Flutter engine crashes silently ("Lost connection to device").
///
///   - WindowOrchestratorService.start() calls _tick() immediately, which can
///     call windowManager methods (setMode locked, isMinimized) — racing
///     against IdleScreen's own setMode(soft).
///
/// By serialising everything behind IdleScreen's first frame, we guarantee:
///   1. Window manager is fully initialised and stable before any service
///      touches it.
///   2. Firebase auth callbacks land after the rendering pipeline has
///      committed at least one frame to the OS.
Future<void> startBackgroundProtocols() async {
  try {
    final registration = await globalDeviceRepository.getRegistration();
    if (registration == null) return;

    final queryId = registration.classroomId ?? registration.smartBoardId;
    SyncManager().init(queryId);
    final boardId = registration.smartBoardId;

    // Prime the in-memory timetable cache from Isar (last known state).
    // Gives the UI immediate data while the listener connects.
    TimetableCache()
        .updateAll(await globalDeviceRepository.getWeeklyTimeline());

    // Start real-time Firestore listener for timetable changes.
    // Uses smartBoardId — timetable_slots documents are keyed on
    // smart_board_id (physical board ID), not the logical classroomId.
    // Passes a REST fallback so the health monitor can recover on staleness.
    TimetableListenerService().start(
      boardId,
      restFallback: () =>
          globalDeviceRepository.syncTimetable(fullSync: true),
    );

    PreFlightService().startCountdownWatcher();
    WindowOrchestratorService().start();
    _startPeriodicTimeSync();

    Log.i(
        '🚀 [Protocols] Background Synchronization, Countdown Watchers, Window Orchestrator, and Time Sync active.');
  } catch (e) {
    Log.e('❌ [Protocols] Background initialization failed: $e');
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
    ApiService.syncTime().catchError((e) {
      Log.w('[TimeSync] Initial sync failed (will retry in 30s): $e');
      return 0;
    });
  }

  _timeSyncTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
    try {
      await ApiService.syncTime();
    } catch (e) {
      Log.w('[TimeSync] Periodic sync failed: $e');
    }
  });
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
    Log.e('🚨 [Integrity] Critical constants hash mismatch — possible tampering');
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

/// Firebase initialization — authenticates the plugin using stored
/// board credentials so that `.snapshots()` streams work.
///
/// `.snapshots()` is the **most cost-effective** approach: Firestore only
/// charges when documents actually change, not on every poll cycle.
/// REST polling (the old approach) billed for every poll × every document,
/// even when nothing changed — wasting money on a small team budget.
///
/// Flow:
///   1. Initialize Firebase with project options
///   2. Read stored email/password from SecureStorage (set during registration)
///   3. Sign into Firebase plugin with `signInWithEmailAndPassword()`
///   4. Screens use `.snapshots()` for all real-time data
Future<void> _initFirebase() async {
  try {
    final options = DefaultFirebaseOptions.fromConfig(
      apiKey: AppConfig.firebaseApiKey,
      projectId: AppConfig.firebaseProjectId,
    );
    await Firebase.initializeApp(options: options);
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );

    // Sign into Firebase plugin using stored board credentials.
    // These were saved during registration via SecureStorageService.storeBoardCredentials().
    final email = await SecureStorageService.getBoardEmail();
    final password = await SecureStorageService.getBoardPassword();

    if (email != null && password != null && email.isNotEmpty && password.isNotEmpty) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      Log.i('[Firebase] Plugin authenticated via stored credentials. .snapshots() ready.');
    } else {
      Log.w('[Firebase] No stored credentials — .snapshots() will be unavailable. '
          'REST clients will be used as fallback.');
    }
  } catch (e) {
    Log.w('[Firebase] Plugin init failed (non-fatal): $e. REST clients will be used as fallback.');
    // Don't rethrow — the app should still run even if Firebase plugin fails.
    // REST-based clients (FirebaseRestAuth, FirestoreRestClient) operate independently.
  }
}

Future<void> _loadEnvironment() async {
  await dotenv.load(fileName: '.env');
  AppConfig.validate();
  debugPrint('Environment loaded');
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
  debugPrint('Secure storage initialized');
}

Future<void> _initLocalVault() async {
  await SessionManager.init();
  debugPrint('Local vault initialized');
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
    );
  }
}
