import 'dart:io';
import 'package:win32_registry/win32_registry.dart';
import 'utils/logger.dart';

class StartupLaunchGuardResult {
  final bool isAutoStart;
  final bool crashLoopDetected;
  final int failedLaunches;
  final String message;

  const StartupLaunchGuardResult({
    required this.isAutoStart,
    required this.crashLoopDetected,
    required this.failedLaunches,
    required this.message,
  });

  static const normal = StartupLaunchGuardResult(
    isAutoStart: false,
    crashLoopDetected: false,
    failedLaunches: 0,
    message: '',
  );
}

class StartupService {
  static const String _appName = 'IntelliAttendSmartBoard';
  static const String autoStartArg = '--intelliattend-autostart';
  static const String _registryKey =
      r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _guardRegistryKey =
      r'Software\IntelliAttend\SmartBoard\StartupGuard';
  static const String _launchInProgress = 'LaunchInProgress';
  static const String _failedLaunches = 'FailedLaunches';
  static const String _lastStartedAt = 'LastStartedAtUtcMs';
  static const String _lastCompletedAt = 'LastCompletedAtUtcMs';
  static const String _lastFailureReason = 'LastFailureReason';

  static const Duration _failedLaunchWindow = Duration(minutes: 10);
  static const int _maxFailedAutoStarts = 2;

  static Future<void> register() async {
    if (!Platform.isWindows) return;

    try {
      final appPath = Platform.resolvedExecutable;
      final quotedPath = '"$appPath" $autoStartArg';

      final key = Registry.currentUser.createKey(_registryKey);
      key.createValue(RegistryValue.string(_appName, quotedPath));
      key.close();
      Log.i('[Startup] Registered auto-launch: $quotedPath');
    } catch (e) {
      Log.e('[Startup] Failed to register auto-launch: $e');
    }
  }

  static Future<void> unregister() async {
    if (!Platform.isWindows) return;

    try {
      final key = Registry.currentUser.createKey(_registryKey);
      key.deleteValue(_appName);
      key.close();
      Log.i('[Startup] Unregistered auto-launch.');
    } catch (e) {
      Log.e('[Startup] Failed to unregister auto-launch: $e');
    }
  }

  /// Records a launch attempt and detects the auto-start crash loop where
  /// Windows keeps reopening a build that dies before kiosk mode can recover.
  static Future<StartupLaunchGuardResult> beginLaunch(List<String> args) async {
    if (!Platform.isWindows) {
      return StartupLaunchGuardResult.normal;
    }
    final isAutoStart = args.contains(autoStartArg);

    RegistryKey? key;
    try {
      key = Registry.currentUser.createKey(_guardRegistryKey);
      final now = DateTime.now().toUtc();
      final nowMs = now.millisecondsSinceEpoch;
      final inProgress = _readInt(key, _launchInProgress) == 1;
      final lastStartedAt = _readInt(key, _lastStartedAt) ?? 0;
      final lastStart = DateTime.fromMillisecondsSinceEpoch(
        lastStartedAt,
        isUtc: true,
      );
      final previousLaunchWasRecent =
          now.difference(lastStart) <= _failedLaunchWindow;

      var failedLaunches = _readInt(key, _failedLaunches) ?? 0;
      if (inProgress && previousLaunchWasRecent) {
        failedLaunches++;
        key.createValue(RegistryValue.int32(_failedLaunches, failedLaunches));
        key.createValue(RegistryValue.string(
          _lastFailureReason,
          'Previous launch did not report startup completion.',
        ));
        Log.w('[StartupGuard] Previous launch did not complete. '
            'failedLaunches=$failedLaunches isAutoStart=$isAutoStart');
      } else if (!inProgress) {
        failedLaunches = 0;
        key.createValue(RegistryValue.int32(_failedLaunches, 0));
      }

      key.createValue(RegistryValue.int32(_launchInProgress, 1));
      key.createValue(RegistryValue.int64(_lastStartedAt, nowMs));

      if (isAutoStart && failedLaunches >= _maxFailedAutoStarts) {
        await unregister();
        await markLaunchCompleted();
        return StartupLaunchGuardResult(
          isAutoStart: true,
          crashLoopDetected: true,
          failedLaunches: failedLaunches,
          message:
              'IntelliAttend failed to start safely $failedLaunches times in a row, so automatic startup has been disabled.\n\n'
              'The app is running in recovery mode with kiosk locks released. Please contact IT support before re-enabling startup.',
        );
      }

      return StartupLaunchGuardResult(
        isAutoStart: isAutoStart,
        crashLoopDetected: false,
        failedLaunches: failedLaunches,
        message: '',
      );
    } catch (e) {
      Log.w('[StartupGuard] beginLaunch failed: $e');
      return StartupLaunchGuardResult(
        isAutoStart: isAutoStart,
        crashLoopDetected: false,
        failedLaunches: 0,
        message: '',
      );
    } finally {
      key?.close();
    }
  }

  static Future<void> markLaunchCompleted() async {
    if (!Platform.isWindows) return;

    RegistryKey? key;
    try {
      key = Registry.currentUser.createKey(_guardRegistryKey);
      key.createValue(RegistryValue.int32(_launchInProgress, 0));
      key.createValue(RegistryValue.int32(_failedLaunches, 0));
      key.createValue(RegistryValue.int64(
        _lastCompletedAt,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ));
      try {
        key.deleteValue(_lastFailureReason);
      } catch (_) {
        // Optional value; it only exists after a failed launch.
      }
      Log.i('[StartupGuard] Launch marked complete.');
    } catch (e) {
      Log.w('[StartupGuard] markLaunchCompleted failed: $e');
    } finally {
      key?.close();
    }
  }

  static Future<void> markLaunchFailed(String reason) async {
    if (!Platform.isWindows) return;

    RegistryKey? key;
    try {
      key = Registry.currentUser.createKey(_guardRegistryKey);
      final failedLaunches = (_readInt(key, _failedLaunches) ?? 0) + 1;
      key.createValue(RegistryValue.int32(_launchInProgress, 0));
      key.createValue(RegistryValue.int32(_failedLaunches, failedLaunches));
      key.createValue(RegistryValue.string(_lastFailureReason, reason));
      Log.w('[StartupGuard] Launch marked failed: $reason');
      if (failedLaunches >= _maxFailedAutoStarts) {
        await unregister();
      }
    } catch (e) {
      Log.w('[StartupGuard] markLaunchFailed failed: $e');
    } finally {
      key?.close();
    }
  }

  static int? _readInt(RegistryKey key, String name) {
    final value = key.getValue(name);
    if (value is Int32Value) return value.value;
    if (value is Int64Value) return value.value;
    if (value is StringValue) return int.tryParse(value.value);
    return null;
  }
}
