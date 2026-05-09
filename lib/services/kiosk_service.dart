import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../core/utils/logger.dart';

enum KioskMode {
  /// Unlocked: Allows minimize, multitasking, and user OS access.
  soft,
  /// Locked: Fullscreen, Always-On-Top, Max Brightness, No Minimize.
  locked,
  /// Suspended: Currently minimized by user.
  suspended,
}

class KioskService {
  static bool _enabled = false;
  static KioskMode _currentMode = KioskMode.soft;
  static double _originalBrightness = 1.0;

  static void enable() {
    if (!Platform.isWindows) return;
    if (_enabled) return;

    try {
      _enabled = true;
      Log.i('🛡️ [Kiosk] Kiosk hardening enabled');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Failed to enable kiosk mode: $e');
    }
  }

  /// Sets the operational mode of the SmartBoard kiosk.
  static Future<void> setMode(KioskMode mode) async {
    if (mode == _currentMode) return;
    
    Log.i('🔄 [Kiosk] Transitioning: $_currentMode -> $mode');

    try {
      switch (mode) {
        case KioskMode.soft:
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setFullScreen(true); // Still fullscreen but not "locked"
          if (Platform.isWindows) {
            await windowManager.setPreventClose(false);
            await windowManager.setSkipTaskbar(false);
          }
          await _restoreBrightness();
          break;

        case KioskMode.locked:
          // DESIGN-2 FIX: Only save brightness if we're NOT already locked.
          // If we save while already locked, we'd overwrite the real user preference
          // with 1.0 (max brightness), destroying what we're trying to restore.
          if (_currentMode != KioskMode.locked) {
            await _saveBrightness();
          }
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setFullScreen(true);
          await windowManager.setAlwaysOnTop(true);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(true);
            await windowManager.setSkipTaskbar(true);
          }
          await _maximizeBrightness();
          break;

        case KioskMode.suspended:
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setFullScreen(false);
          if (Platform.isWindows) {
            await windowManager.setPreventClose(false);
            await windowManager.setSkipTaskbar(false);
          }
          await windowManager.minimize();
          await _restoreBrightness();
          break;
      }
      _currentMode = mode;
    } catch (e) {
      Log.e('❌ [Kiosk] Mode transition failed: $e');
    }
  }

  static Future<void> _saveBrightness() async {
    try {
      _originalBrightness = await ScreenBrightness().current;
      Log.i('🔅 [Kiosk] Saved original brightness: ${(_originalBrightness * 100).toInt()}%');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Failed to save brightness: $e');
    }
  }

  static Future<void> _maximizeBrightness() async {
    try {
      await ScreenBrightness().setScreenBrightness(1.0);
      Log.i('🔆 [Kiosk] Max brightness set for QR visibility.');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Failed to set max brightness: $e');
    }
  }

  static Future<void> _restoreBrightness() async {
    try {
      await ScreenBrightness().setScreenBrightness(_originalBrightness);
      Log.i('🔅 [Kiosk] Restored user brightness: ${(_originalBrightness * 100).toInt()}%');
    } catch (e) {
      Log.w('⚠️ [Kiosk] Failed to restore brightness: $e');
    }
  }

  static KioskMode get currentMode => _currentMode;
  static bool get isEnabled => _enabled;
}
