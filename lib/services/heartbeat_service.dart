import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/repositories/device_repository.dart';
import 'package:dio/dio.dart';
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

  /// Current screen state reported in the heartbeat.
  static String screenState = 'unknown';

  static Future<void> start(IDeviceRepository deviceRepository) async {
    _deviceRepository = deviceRepository;

    // Guard against double-start (called once from _initTier3() at app launch
    // and again from startBackgroundProtocols() after registration completes).
    // The second call must only refresh the repository reference — it must NOT
    // fire an immediate heartbeat (which risks a 401 that triggers a forced
    // logout → RegistrationScreen loop) and must NOT create a second concurrent
    // timer running alongside the first.
    if (_timer != null) {
      Log.d('[Heartbeat] Already running — repository reference updated. Next heartbeat on schedule.');
      return;
    }

    _startedAt ??= DateTime.now();
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _cachedVersion = 'unknown';
    }

    // Send immediately on start, then every 5 minutes
    await _send();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _send());
    Log.i('[Heartbeat] Started (interval: 5m, version: $_cachedVersion).');
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
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
      if (e is DioException &&
          (e.response?.statusCode == 401 || e.response?.statusCode == 404)) {
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
