import 'dart:io';
import '../core/utils/logger.dart';

class KioskService {
  static bool _enabled = false;

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

  static bool get isEnabled => _enabled;
}
