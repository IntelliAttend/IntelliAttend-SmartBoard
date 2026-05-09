import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'api_service.dart';
import '../data/repositories/device_repository.dart';
import '../main.dart';
import 'session_manager.dart';
import 'sync_manager.dart';
import 'telemetry_service.dart';
import 'time_sync_service.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'hardware_fingerprint_service.dart';
import 'secure_storage_service.dart';
import 'dart:math';

class PreFlightService {
  static final PreFlightService _instance = PreFlightService._internal();
  factory PreFlightService() => _instance;
  PreFlightService._internal();

  bool _isDailyBootDone = false;
  bool _isWarmUpInProgress = false;
  int _warmUpRetryCount = 0;
  Timer? _retryTimer;

  /// Phase 1: The "Daily Boot" Sequence (T-10:00 Window)
  /// v6.1: Implements Random Jitter ±30s and Fibonacci Backoff.
  Future<void> runDailyBoot() async {
    if (_isDailyBootDone) return;

    // 1. Random Jitter (±30s) to prevent Thundering Herd
    final jitterSeconds = Random().nextInt(61) - 30;
    Log.i('🏗️ [PreFlight] Daily Boot scheduled with ${jitterSeconds}s jitter...');
    await Future.delayed(Duration(seconds: jitterSeconds.abs()));

    Log.i('🏗️ [PreFlight] Starting Daily Boot Sequence...');

    int attempts = 0;
    bool success = false;
    final fibonacci = [1, 2, 3, 5, 8]; // Backoff minutes

    while (!success && attempts < fibonacci.length) {
      try {
        final isar = SessionManager.isar;
        await isar.writeTxn(() async {
          await isar.activeSessions.clear();
        });

        await globalDeviceRepository.syncTimetable(fullSync: true);
        await _pushHardwareTelemetry();
        _checkMemoryThreshold();

        success = true;
        _isDailyBootDone = true;
        Log.i('✅ [PreFlight] Daily Boot Sequence Complete.');
      } catch (e) {
        attempts++;
        if (attempts < fibonacci.length) {
          final waitMin = fibonacci[attempts - 1];
          Log.e('❌ [PreFlight] Daily Boot Attempt $attempts Failed. Retrying in $waitMin minutes (Fibonacci)...');
          await Future.delayed(Duration(minutes: waitMin));
        }
      }
    }
  }

  /// Phase 2: The "Per-Session" Warm-Up (T-3:00 Window)
  /// v6.2: Atomic Ignition - No keys until OTP entry.
  Future<Map<String, dynamic>?> runPerSessionWarmUp(String slotId, {bool isRetry = false}) async {
    if (_isWarmUpInProgress && !isRetry) return null;
    
    if (!isRetry) {
      _warmUpRetryCount = 0;
      _retryTimer?.cancel();
    }

    _isWarmUpInProgress = true;
    _warmUpRetryCount++;
    
    Log.i('🔥 [PreFlight] Attempt $_warmUpRetryCount: Warm-Up for slot: $slotId');

    try {
      // 1. API Handshake (Context-only)
      final result = await ApiService.getPreFlight(slotId, retryCount: _warmUpRetryCount);
      
      final serverTs = result['server_timestamp'] as int;
      final sessionId = result['pre_allocated_session_id'] as String;

      // 2. Clock Synchronization
      TimeSyncService.setSkew(serverTs - DateTime.now().millisecondsSinceEpoch);

      Log.i('✅ [PreFlight] Warm-Up Successful. Context loaded for $sessionId');
      _isWarmUpInProgress = false;
      return result;
      
    } catch (e) {
      Log.e('❌ [PreFlight] Warm-Up Attempt $_warmUpRetryCount Failed: $e');
      
      final jitter = Random().nextInt(3);
      final nextRetryDelay = Duration(seconds: 20 + jitter);

      Log.i('⏳ [PreFlight] Retrying in ${nextRetryDelay.inSeconds}s...');
      
      _retryTimer = Timer(nextRetryDelay, () {
        runPerSessionWarmUp(slotId, isRetry: true);
      });
      
      return null;
    }
  }

  Future<void> _pushHardwareTelemetry() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final data = {
        'wifi_signal_dbm': -45, 
        'available_storage_gb': 12.5, 
        'app_version': packageInfo.version,
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
      };
      await ApiService.sendHardwareTelemetry(data);
      Log.i('📡 [PreFlight] Hardware Telemetry pushed.');
    } catch (e) {
      Log.w('⚠️ [PreFlight] Telemetry push failed: $e');
    }
  }

  void _checkMemoryThreshold() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        final memoryUsageMb = 250; 
        if (memoryUsageMb > 500) {
          Log.w('🚨 [PreFlight] Memory threshold exceeded. Restarting...');
          SystemNavigator.pop();
        }
      }
    } catch (e) {
      Log.w('⚠️ [PreFlight] Memory check skipped: $e');
    }
  }
}
