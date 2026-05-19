import 'dart:async';
import 'package:isar/isar.dart';
import 'api_service.dart';
import '../main.dart';
import 'session_manager.dart';
import 'time_sync_service.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:math';

class PreFlightService {
  static final PreFlightService _instance = PreFlightService._internal();
  factory PreFlightService() => _instance;
  PreFlightService._internal();

  static const int _maxWarmUpRetries = 5;

  bool _isDailyBootDone = false;
  bool _isWarmUpInProgress = false;
  int _warmUpRetryCount = 0;
  Timer? _retryTimer;
  Timer? _countdownTimer;

  /// Phase 0: The "Countdown Watcher"
  /// Periodically checks the Isar timetable for the next class.
  void startCountdownWatcher() {
    _countdownTimer?.cancel();
    _countdownTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _checkCountdown());
    _checkCountdown(); // Initial check
  }

  Future<void> _checkCountdown() async {
    try {
      final now = TimeSyncService.timeNow;
      final currentSlot = await globalDeviceRepository.getCurrentSlot();

      // If we are already in a class, no need for ignition checks
      if (currentSlot != null) return;

      // Find the next upcoming slot today
      final todaySlots = await globalDeviceRepository.getTodayTimeline();
      final timeStr =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      final nextSlot = todaySlots
          .where((s) => s.startTime.compareTo(timeStr) > 0)
          .firstOrNull;
      if (nextSlot == null) return;

      // Calculate minutes until start
      final startTimeParts = nextSlot.startTime.split(':');
      final startDateTime = DateTime(now.year, now.month, now.day,
          int.parse(startTimeParts[0]), int.parse(startTimeParts[1]));
      final diffMin = startDateTime.difference(now).inMinutes;

      Log.i(
          '⏳ [PreFlight] Next class: ${nextSlot.courseName} in $diffMin minutes.');

      // Requirement: T-10 Handshake (Status 1)
      if (diffMin <= 10 && diffMin > 3) {
        _triggerStatusCheck(nextSlot.slotId);
      }

      // Requirement: T-3 Pre-Flight Ignition
      if (diffMin <= 3 && diffMin >= 0) {
        runPerSessionWarmUp(nextSlot.slotId);
      }
    } catch (e) {
      Log.w('⚠️ [PreFlight] Countdown check failed: $e');
    }
  }

  Future<void> _triggerStatusCheck(String slotId) async {
    Log.i(
        '🏗️ [PreFlight] T-10 Window Detected. Triggering Status 1 Handshake for $slotId...');
    try {
      // Sync clock before timetable to ensure accurate time comparison.
      // Skew is persisted in SecureStorage so a single failure doesn't break us.
      await ApiService.syncTime();
      // Fallback timetable sync — the Firestore listener normally keeps the
      // timetable current; this REST call is a safety net in case the listener
      // missed an update during an offline period.
      await globalDeviceRepository.syncTimetable(fullSync: false);
      await _pushHardwareTelemetry();
      Log.i('✅ [PreFlight] Status 1 Handshake Successful.');
    } catch (e) {
      Log.e(
          '❌ [PreFlight] Status 1 Handshake Failed (will retry in 1 minute): $e');
    }
  }

  /// Phase 1: The "Daily Boot" Sequence (T-10:00 Window)
  /// v6.1: Implements Random Jitter ±30s and Fibonacci Backoff.
  Future<void> runDailyBoot() async {
    if (_isDailyBootDone) return;

    // 1. Random Jitter (±30s) to prevent Thundering Herd
    final jitterSeconds = Random().nextInt(61) - 30;
    Log.i(
        '🏗️ [PreFlight] Daily Boot scheduled with ${jitterSeconds}s jitter...');
    await Future.delayed(Duration(seconds: jitterSeconds.abs()));

    Log.i('🏗️ [PreFlight] Starting Daily Boot Sequence...');

    int attempts = 0;
    bool success = false;
    final fibonacci = [1, 2, 3, 5, 8]; // Backoff minutes

    while (!success && attempts < fibonacci.length) {
      try {
        // v6.3: Force a network time handshake on boot.
        // This ensures the board has a corrected clock before any session can start.
        await ApiService.syncTime();

        final isar = SessionManager.isar;

        // v6.3: Only clear STALE sessions (older than 2 hours)
        // This protects current session data during mid-class power-cycle recovery.
        final cutoff = DateTime.now().subtract(const Duration(hours: 2));
        await isar.writeTxn(() async {
          final staleSessions = await isar.activeSessions
              .filter()
              .scheduledEndTimeLessThan(cutoff)
              .findAll();
          await isar.activeSessions
              .deleteAll(staleSessions.map((s) => s.id).toList());
        });

        // Fallback full timetable sync — the Firestore listener is the
        // primary update path; this REST call is a safety net on cold boot.
        await globalDeviceRepository.syncTimetable(fullSync: true);
        await _pushHardwareTelemetry();

        success = true;
        _isDailyBootDone = true;
        Log.i('✅ [PreFlight] Daily Boot Sequence Complete.');
      } catch (e) {
        attempts++;
        if (attempts < fibonacci.length) {
          final waitMin = fibonacci[attempts - 1];
          Log.e(
              '❌ [PreFlight] Daily Boot Attempt $attempts Failed. Retrying in $waitMin minutes (Fibonacci)...');
          await Future.delayed(Duration(minutes: waitMin));
        }
      }
    }
  }

  /// Cancels any in-flight retry chain and starts a fresh warm-up immediately.
  /// Used at T-0 when the class has started and preflight hasn't succeeded yet.
  /// The [onSuccess] callback, if provided, fires on both the immediate call
  /// AND any subsequent retry success (it is carried through the retry chain).
  Future<Map<String, dynamic>?> forceWarmUp(String slotId,
      {void Function(Map<String, dynamic> result)? onSuccess}) async {
    _retryTimer?.cancel();
    _isWarmUpInProgress = false;
    Log.i('🔥 [PreFlight] Forcing warm-up for slot: $slotId');
    return runPerSessionWarmUp(slotId, onSuccess: onSuccess);
  }

  /// Phase 2: The "Per-Session" Warm-Up (T-3:00 Window)
  /// v6.2: Atomic Ignition - No keys until OTP entry.
  ///
  /// The [onSuccess] callback is threaded through the retry chain so that
  /// the caller (IdleScreen._triggerWarmUp) receives the result even when a
  /// delayed retry succeeds — not just the initial attempt.
  Future<Map<String, dynamic>?> runPerSessionWarmUp(String slotId,
      {bool isRetry = false,
      void Function(Map<String, dynamic> result)? onSuccess}) async {
    if (_isWarmUpInProgress && !isRetry) return null;

    if (!isRetry) {
      _warmUpRetryCount = 0;
      _retryTimer?.cancel();
    }

    _isWarmUpInProgress = true;
    _warmUpRetryCount++;

    Log.i(
        '🔥 [PreFlight] Attempt $_warmUpRetryCount: Warm-Up for slot: $slotId');

    try {
      // 1. API Handshake (Context-only) with RTT tracking
      final requestSentAt = DateTime.now();
      final result =
          await ApiService.getPreFlight(slotId, retryCount: _warmUpRetryCount);
      final responseReceivedAt = DateTime.now();

      final serverTs = result['server_timestamp'] as int;
      final sessionId = result['pre_allocated_session_id'] as String;

      // 2. Cryptographic Clock Synchronization (RTT-compensated)
      TimeSyncService.synchronizeWithServer(
          requestSentAt, responseReceivedAt, serverTs);

      Log.i('✅ [PreFlight] Warm-Up Successful. Context loaded for $sessionId');
      _isWarmUpInProgress = false;
      if (onSuccess != null) onSuccess(result);
      return result;
    } catch (e) {
      Log.e('❌ [PreFlight] Warm-Up Attempt $_warmUpRetryCount Failed: $e');

      if (_warmUpRetryCount >= _maxWarmUpRetries) {
        Log.w('🚫 [PreFlight] Max retries ($_maxWarmUpRetries) reached. Giving up. Faculty may proceed manually.');
        _isWarmUpInProgress = false;
        return null;
      }

      final jitter = Random().nextInt(3);
      final nextRetryDelay = Duration(seconds: 20 + jitter);

      Log.i('⏳ [PreFlight] Retrying in ${nextRetryDelay.inSeconds}s...');

      _retryTimer = Timer(nextRetryDelay, () {
        runPerSessionWarmUp(slotId, isRetry: true, onSuccess: onSuccess);
      });

      return null;
    }
  }

  Future<void> _pushHardwareTelemetry() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final registration = await globalDeviceRepository.getRegistration();
      final boardId = registration?.smartBoardId ?? 'UNKNOWN';
      final data = {
        'boardId': boardId,
        'wifi_signal_dbm': -45,
        'available_storage_gb': 12.5,
        'app_version': packageInfo.version,
        'timestamp_ms': TimeSyncService.timeNow.millisecondsSinceEpoch,
      };
      await ApiService.sendHardwareTelemetry(data);
      Log.i('📡 [PreFlight] Hardware Telemetry pushed for $boardId.');
    } catch (e) {
      Log.w('⚠️ [PreFlight] Telemetry push failed: $e');
    }
  }
}
