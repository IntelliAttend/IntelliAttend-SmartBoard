import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/repositories/device_repository.dart';
import 'api_service.dart';
import '../core/utils/logger.dart';
import '../main.dart';
import '../presentation/screens/registration_screen.dart';

/// v6.0: Periodic heartbeat sender (Accountable Device Model).
///
/// Sends a POST /api/v1/device/heartbeat every 5 minutes so IT can monitor
/// board health via the Admin Panel.
///
/// Why 5 minutes:
///   - Balanced for kiosk monitoring without excessive API load.
class HeartbeatService {
  static Timer? _timer;
  static DateTime? _startedAt;
  static String? _cachedVersion;
  static IDeviceRepository? _deviceRepository;

  // Atomic double-start guard. Set synchronously before any async work so two
  // near-simultaneous start() calls cannot both pass the check and create
  // duplicate timers. Using `_timer != null` was racy because the one-shot →
  // periodic transition momentarily leaves _timer null.
  static bool _started = false;

  /// Current screen state reported in the heartbeat.
  static String screenState = 'unknown';

  static Future<void> start(IDeviceRepository deviceRepository) async {
    _deviceRepository = deviceRepository;

    if (_started) {
      Log.d('[Heartbeat] Already running — repository reference updated.');
      return;
    }
    _started = true;

    _startedAt ??= DateTime.now();
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _cachedVersion = 'unknown';
    }

    // Delay the first heartbeat by 30 s so the UI, window manager, and Firebase
    // platform bindings are fully settled before we call getIdToken(). On Windows
    // the Firebase Auth C++ plugin delivers its token-refresh callback on a
    // non-platform thread; if that callback fires during the first 1–2 s while
    // window_manager is also issuing native calls, the Flutter engine crashes.
    // After the initial beat we switch to the normal 5-minute periodic timer.
    _timer = Timer(const Duration(seconds: 30), () async {
      await _send();
      _timer = Timer.periodic(const Duration(minutes: 5), (_) => _send());
      Log.i('[Heartbeat] Periodic timer armed (interval: 5m).');
    });
    Log.i('[Heartbeat] Started — first beat in 30 s, then every 5 m (version: $_cachedVersion).');
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    Log.i('[Heartbeat] Stopped.');
  }

  static Future<void> _send() async {
    // Skip silently if the board has no registration yet — there is no auth
    // token to send, and a 401 on an unregistered device is meaningless noise.
    final registration = await _deviceRepository?.getRegistration();
    if (registration == null) {
      Log.d('[Heartbeat] No registration — skipping heartbeat.');
      return;
    }

    final uptime = _startedAt != null
        ? DateTime.now().difference(_startedAt!).inSeconds
        : 0;

    try {
      final smartBoardId = registration.smartBoardId;
      final hardwareId = registration.hardwareId;
      await _deviceRepository?.sendHeartbeat(
        smartBoardId: smartBoardId,
        hardwareId: hardwareId,
        screenState: screenState,
        uptimeSeconds: uptime,
        appVersion: _cachedVersion ?? 'unknown',
      );
    } catch (e) {
      if (e is ApiException &&
          (e.statusCode == 401 || e.statusCode == 404)) {
        Log.e('🚨 [Heartbeat] Authentication lost or device revoked. Forcing logout...');
        await stop();
        await _deviceRepository?.clearRegistration();

        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RegistrationScreen()),
          (route) => false,
        );
        return;
      }

      Log.w('[Heartbeat] Send failed (will retry in 5m): $e');
    }
  }
}
