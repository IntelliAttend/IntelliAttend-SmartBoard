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
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Full Screen setup for Desktop
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux)) {
    await windowManager.ensureInitialized();
    
    await windowManager.waitUntilReadyToShow(const WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      center: true,
    ), () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setFullScreen(true);
      await windowManager.setAlwaysOnTop(true);
    });
  }

  await _initFirebase();
  await _loadEnvironment();
  await _initSecureStorage();
  _configureOrientation();
  await _initLocalVault();

  runApp(const IntelliAttendApp());
  
  // Secondary attempt after UI is rendered
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    Future.delayed(const Duration(milliseconds: 500), () async {
      await windowManager.setFullScreen(true);
    });
  }
}

Future<void> _initFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
