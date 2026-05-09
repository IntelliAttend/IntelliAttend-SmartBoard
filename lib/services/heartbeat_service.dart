import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';
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
    final uptime = _startedAt != null
        ? DateTime.now().difference(_startedAt!).inSeconds
        : 0;

    try {
      await _deviceRepository?.sendHeartbeat(
        screenState: screenState,
        uptimeSeconds: uptime,
        appVersion: _cachedVersion ?? 'unknown',
      );
    } catch (e) {
      if (e is DioException && (e.response?.statusCode == 401 || e.response?.statusCode == 404)) {
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
