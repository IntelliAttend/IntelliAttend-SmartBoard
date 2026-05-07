import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:window_manager/window_manager.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'services/session_manager.dart';
import 'services/secure_storage_service.dart';
import 'presentation/screens/boot_screen.dart';
import 'services/device_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Core Services first
  await _initFirebase();
  await _loadEnvironment();
  await _initSecureStorage();
  _configureOrientation();
  await _initLocalVault();

  // 2. Start UI immediately
  runApp(const IntelliAttendApp());

  // 3. Handle Desktop Windowing after UI is up
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
    });
  }
}

Future<void> _initFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      // For Apple platforms, we try to use the native GoogleService-Info.plist automatically
      // if DefaultFirebaseOptions fails.
      if (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS) {
        await Firebase.initializeApp();
      } else {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      debugPrint('Firebase initialized');
    } else {
      debugPrint('Firebase already initialized');
    }
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
}

Future<void> _loadEnvironment() async {
  try {
    await dotenv.load(fileName: '.env');
    AppConfig.validate();
    debugPrint('Environment loaded');
  } catch (e) {
    debugPrint('Environment load error: $e');
  }
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
  try {
    await SecureStorageService.init();
    debugPrint('Secure storage initialized');
  } catch (e) {
    debugPrint('Secure storage init error: $e');
  }
}

Future<void> _initLocalVault() async {
  try {
    await SessionManager.init();
    debugPrint('Local vault initialized');
  } catch (e) {
    debugPrint('Local vault init error: $e');
  }
}

class IntelliAttendApp extends StatelessWidget {
  const IntelliAttendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IntelliAttend SmartBoard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light, // Force light for now as per "ideal screen" request
      home: const BootScreen(),
    );

  }
}
