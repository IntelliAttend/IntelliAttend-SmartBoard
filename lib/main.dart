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
import 'services/secure_storage_service.dart';
import 'presentation/screens/boot_screen.dart';
import 'presentation/screens/init_failure_screen.dart';
import 'services/heartbeat_service.dart';
import 'services/integrity_verifier.dart';
import 'services/kiosk_service.dart';
import 'services/notification_service.dart';
import 'services/window_orchestrator_service.dart';
import 'services/startup_service.dart';
import 'services/pre_flight_service.dart';
import 'services/sync_manager.dart';
import 'firebase_options.dart';
import 'services/time_sync_service.dart';
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
    if (isFatal) return 'Critical initialization failed. Please reinstall or contact IT.';
    if (!firebase) return 'Running in offline mode — real-time updates unavailable.';
    return '';
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final IDeviceRepository globalDeviceRepository;
late final IAuthRepository globalAuthRepository;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Desktop Windowing (Critical to do before or during startup)
  try {
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        center: true,
      ), () async {
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setFullScreen(true);
        await windowManager.setAlwaysOnTop(true);
        if (Platform.isWindows) {
          await windowManager.setPreventClose(true);
          await windowManager.setSkipTaskbar(true);
        }
      });
    }
  } catch (e) {
    debugPrint('⚠️ [WindowManager] Init error: $e');
  }

  // 2. Kiosk Hardening (Windows only)
  KioskService.enable();

  // v6.4: Initialize Notification Service (no repo dependency)
  await NotificationService.init();

  // 3. Runtime Integrity Verification
  final tampered = await _verifyIntegrity();
  
  // 4. Initialize Core Services
  final status = await _initAll();

  // 5. Start Heartbeat Monitor (moved below repository initialization)

  // 6. Start UI
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
  } else if (status.isFatal) {
    runApp(InitFailureScreen(message: status.message));
  } else {
    final apiClient = ApiClient();
    globalAuthRepository = AuthRepository(apiClient);
    globalDeviceRepository = DeviceRepository(SessionManager.isar, globalAuthRepository);

    // Trigger Migration Bridge
    globalDeviceRepository.performMigrationBridge();

    // Start Heartbeat Monitor
    HeartbeatService.start(globalDeviceRepository);

    // Initialize Real-Time Timetable Mirror and Countdown Orchestrator
    _initializeBackgroundProtocols();

    runApp(
      MultiProvider(
        providers: [
          Provider<IDeviceRepository>.value(value: globalDeviceRepository),
          Provider<IAuthRepository>.value(value: globalAuthRepository),
          ChangeNotifierProvider(create: (_) => RegistrationProvider(globalAuthRepository, globalDeviceRepository)),
        ],
        child: IntelliAttendApp(isDegraded: !status.firebase),
      ),
    );
  }
}

void _initializeBackgroundProtocols() async {
  try {
    final registration = await globalDeviceRepository.getRegistration();
    if (registration != null) {
      // 1. Start Real-Time Firestore Mirroring for Timetable
      SyncManager().init(registration.smartBoardId);
      
      // 2. Start T-10 / T-3 Countdown Watcher (data side)
      PreFlightService().startCountdownWatcher();

      // 3. Start Window Orchestrator (UI/window side) — must be after repos ready
      WindowOrchestratorService().start();
      
      Log.i('🚀 [Protocols] Background Synchronization, Countdown Watchers, and Window Orchestrator active.');
    }
  } catch (e) {
    Log.e('❌ [Protocols] Background initialization failed: $e');
  }
}

Future<bool> _verifyIntegrity() async {
  bool tampered = false;

  if (!IntegrityVerifier.verify()) {
    Log.e('🚨 [Integrity] Critical constants hash mismatch — possible tampering');
    tampered = true;
  }

  final sigValid = await IntegrityVerifier.verifyCodeSignature();
  if (!sigValid) {
    Log.e('🚨 [Integrity] Code signature invalid — binary modified');
    tampered = true;
  }

  if (tampered) {
    await SecureStorageService.clearAll();
  }
  return tampered;
}

Future<InitStatus> _initAll() async {
  final errors = <String>[];

  final firebaseOk = await _tryInit('Firebase', _initFirebase);
  if (!firebaseOk) errors.add('Firebase');

  final dotenvOk = await _tryInit('Environment', _loadEnvironment);
  if (!dotenvOk) errors.add('Environment');

  final secureOk = await _tryInit('Secure Storage', _initSecureStorage);
  if (!secureOk) errors.add('SecureStorage');

  // Load cached clock skew immediately after SecureStorage is ready
  await _tryInit('Time Sync', TimeSyncService.init);

  _configureOrientation();

  final isarOk = await _tryInit('Local Vault', _initLocalVault);
  if (!isarOk) errors.add('Isar');

  return InitStatus(
    firebase: firebaseOk,
    isar: isarOk,
    secureStorage: secureOk,
    dotenv: dotenvOk,
    errors: errors,
  );
}

Future<bool> _tryInit(String name, Future<void> Function() fn) async {
  try {
    await fn();
    return true;
  } catch (e) {
    Log.e('❌ [$name] Initialization failed: $e');
    return false;
  }
}

Future<void> _initFirebase() async {
  if (Firebase.apps.isEmpty) {
    debugPrint('Initializing Firebase for platform: ${defaultTargetPlatform.name}');
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
