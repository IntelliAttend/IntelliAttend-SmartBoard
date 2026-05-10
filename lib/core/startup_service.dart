import 'dart:io';
import 'package:win32_registry/win32_registry.dart';
import 'utils/logger.dart';

class StartupService {
  static const String _appName = 'IntelliAttendSmartBoard';
  static const String _registryKey =
      r'Software\Microsoft\Windows\CurrentVersion\Run';

  static Future<void> register() async {
    if (!Platform.isWindows) return;

    try {
      final appPath = Platform.resolvedExecutable;
      final quotedPath = '"$appPath"';

      final key = Registry.currentUser.createKey(_registryKey);
      key.createValue(RegistryValue.string(_appName, quotedPath));
      key.close();
      Log.i('🚀 [Startup] Registered auto-launch: $quotedPath');
    } catch (e) {
      Log.e('❌ [Startup] Failed to register auto-launch: $e');
    }
  }

  static Future<void> unregister() async {
    if (!Platform.isWindows) return;

    try {
      final key = Registry.currentUser.createKey(_registryKey);
      key.deleteValue(_appName);
      key.close();
      Log.i('🗑️ [Startup] Unregistered auto-launch.');
    } catch (e) {
      Log.e('❌ [Startup] Failed to unregister auto-launch: $e');
    }
  }
}
