import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:window_manager/window_manager.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'services/session_manager.dart';
import 'core/security/secure_storage_service.dart';
import 'presentation/screens/boot_screen.dart';
import 'presentation/screens/init_failure_screen.dart';
import 'services/heartbeat_service.dart';
import 'core/security/integrity_verifier.dart';
import 'core/platform/kiosk_service.dart';

import 'core/platform/window_orchestrator_service.dart';
import 'services/pre_flight_service.dart';
import 'services/sync_manager.dart';
import 'services/time_sync_service.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/device_repository.dart';
import 'core/network/api_client.dart';
import 'presentation/providers/registration_provider.dart';

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
      final lockFile = File('${Directory.systemTemp.path}/intelliattend_smartboard.lock');
      try {
        final raf = await lockFile.open(mode: FileMode.write);
        try {
          await raf.lock(FileLock.exclusive);
          // We hold the lock for the lifetime of the process — do NOT close raf.
          // Dart will release it on process exit.
          // ignore: unawaited_futures
          Future(() async {
            // Keep a reference so the RAF (and therefore the lock) is not GC'd.
            // ignore: unused_local_variable
            final _ = raf;
          });
        } on FileSystemException {
          // Another instance already holds the lock — bring it to the front
          // and exit this one.
          debugPrint('⚠️ [SingleInstance] Another instance is running. Exiting.');
          exit(0);
        }
      } catch (_) {
        // Lock file approach failed (permissions, etc.) — allow launch anyway.
      }
    }

    // ─── TIER 1: Blocking (must pass or app can't run) ──────────────────────
    await _initWindow();
    KioskService.enable();
    final status = await _initTier1();

    if (status.isFatal) {
      runApp(InitFailureScreen(message: status.message));
      return;
    }

    // ─── TIER 2: Timeout-aware (fail gracefully, flag degraded) ─────────────
    final tier2 = await _initTier2(status);

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
        child: IntelliAttendApp(isDegraded: !tier2.firebase),
      ),
    );

    // ─── TIER 3: Fire-and-forget (don't block UI) ──────────────────────────
    _initTier3();
  }, (Object error, StackTrace stack) {
    Log.e('🔥 Unhandled application error', error, stack);
  });
}

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
  _initializeBackgroundProtocols();
}

/// Called at startup (Tier 3) AND again after first-time registration completes
/// so SyncManager, PreFlightService, and WindowOrchestratorService are always
/// running when the IdleScreen mounts.
Future<void> _initializeBackgroundProtocols() async {
  try {
    final registration = await globalDeviceRepository.getRegistration();
    if (registration != null) {
      final queryId = registration.classroomId ?? registration.smartBoardId;
      SyncManager().init(queryId);
      PreFlightService().startCountdownWatcher();
      WindowOrchestratorService().start();

      Log.i(
          '🚀 [Protocols] Background Synchronization, Countdown Watchers, and Window Orchestrator active.');
    }
  } catch (e) {
    Log.e('❌ [Protocols] Background initialization failed: $e');
  }
}

/// Public entry point so RegistrationProvider can start background protocols
/// after first-time hardware bonding completes (the device wasn't registered
/// at app launch, so Tier 3 skipped them).
Future<void> startBackgroundProtocols() => _initializeBackgroundProtocols();

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

Future<void> _initFirebase() async {
  if (Firebase.apps.isEmpty) {
    debugPrint(
        'Initializing Firebase for platform: ${defaultTargetPlatform.name}');
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    debugPrint('Firebase initialized');
  } else {
    debugPrint('Firebase already initialized');
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
  final bool isDegraded;
  const IntelliAttendApp({super.key, this.isDegraded = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'IntelliAttend SmartBoard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: BootScreen(isDegraded: isDegraded),
    );
  }
}
