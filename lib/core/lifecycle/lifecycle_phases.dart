import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

import '../security/integrity_verifier.dart';
import '../security/secure_storage_service.dart';
import '../config/app_config.dart';
import '../config/install_paths.dart';
import '../utils/logger.dart';
import '../../services/session_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';

/// Individual lifecycle phase implementations.
///
/// Separated from the main manager for testability and readability.
/// Each method is a self-contained phase that can be called independently.
class LifecyclePhases {
  LifecyclePhases._();

  // ── VALIDATION ────────────────────────────────────────────────────────────

  /// Verify integrity constants and code signature.
  static Future<bool> verifyIntegrity() async {
    bool tampered = false;

    if (!IntegrityVerifier.verify()) {
      Log.e('[Lifecycle] Critical constants hash mismatch - possible tampering');
      tampered = true;
    }

    if (!tampered) {
      try {
        final sigValid = await IntegrityVerifier.verifyCodeSignature()
            .timeout(const Duration(seconds: 5));
        if (!sigValid) {
          Log.e('[Lifecycle] Code signature invalid - binary modified');
          tampered = true;
        }
      } catch (e) {
        Log.w('[Lifecycle] Signature verification skipped ($e)');
      }
    }

    if (tampered) {
      await SecureStorageService.clearAll();
    }
    return tampered;
  }

  // ── CONFIGURATION ─────────────────────────────────────────────────────────

  /// Load environment configuration from Config\env.json.
  static Future<void> loadEnvironment() async {
    bool loaded = false;

    if (!kIsWeb && Platform.isWindows) {
      // Try new Config\env.json path first.
      try {
        final envPath = InstallPaths.envFile;
        await dotenv.load(fileName: envPath);
        loaded = dotenv.env.isNotEmpty;
        if (loaded) {
          Log.i('[Lifecycle] Environment loaded from: $envPath');
        }
      } catch (e) {
        Log.d('[Lifecycle] Local env.json not found at Config path: $e');
      }
      // Fall back to legacy .env path.
      if (!loaded) {
        try {
          final legacyPath = InstallPaths.legacyEnvPath;
          await dotenv.load(fileName: legacyPath);
          loaded = dotenv.env.isNotEmpty;
          if (loaded) {
            Log.i('[Lifecycle] Environment loaded from legacy path: $legacyPath');
          }
        } catch (e) {
          Log.d('[Lifecycle] Legacy .env not found: $e');
        }
      }
    }

    // Try Flutter assets (dev builds).
    if (!loaded) {
      try {
        await dotenv.load();
        loaded = dotenv.env.isNotEmpty;
        if (loaded) {
          Log.i('[Lifecycle] Environment loaded from Flutter assets');
        }
      } catch (_) {}
    }

    // Filesystem .env (dev).
    if (!loaded) {
      try {
        await dotenv.load(fileName: '.env');
        loaded = dotenv.env.isNotEmpty;
      } catch (_) {}
    }

    // Directory next to exe.
    if (!loaded && !kIsWeb && Platform.isWindows) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        await dotenv.load(fileName: '$exeDir\\.env');
        loaded = dotenv.env.isNotEmpty;
        if (loaded) {
          Log.i('[Lifecycle] Environment loaded from exe directory');
        }
      } catch (_) {}
    }

    if (!loaded) {
      Log.w('[Lifecycle] No .env file found - using dart-define fallbacks');
    }
    AppConfig.validate();
  }

  /// Register auto-start in Windows registry.
  static Future<void> registerAutoStart() async {
    if (!kIsWeb && Platform.isWindows) {
      try {
        final appPath = Platform.resolvedExecutable;
        final quotedPath = '"$appPath" --intelliattend-autostart';
        final key = Registry.currentUser.createKey(
            r'Software\Microsoft\Windows\CurrentVersion\Run');
        key.createValue(
            RegistryValue.string('IntelliAttendSmartBoard', quotedPath));
        key.close();
        Log.i('[Lifecycle] Auto-start registered: $quotedPath');
      } catch (e) {
        Log.e('[Lifecycle] Auto-start registration failed: $e');
      }
    }
  }

  // ── DATABASE ──────────────────────────────────────────────────────────────

  /// Initialize secure storage (OS keychain).
  static Future<void> initSecureStorage() async {
    await SecureStorageService.init();
    Log.i('[Lifecycle] Secure storage initialized');
  }

  /// Initialize Isar local vault.
  static Future<void> initLocalVault() async {
    await SessionManager.init();
    Log.i('[Lifecycle] Local vault initialized');
  }

  // ── WINDOW ────────────────────────────────────────────────────────────────

  /// Initialize window manager (1920x1080, hidden, centered).
  static Future<void> initWindow() async {
    try {
      if (!kIsWeb &&
          (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        await windowManager.ensureInitialized();

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
      Log.w('[Lifecycle] WindowManager init error: $e');
    }
  }
}
