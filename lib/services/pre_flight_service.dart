import 'dart:async';
import 'package:isar/isar.dart';
import 'api_service.dart';
import '../main.dart';
import 'session_manager.dart';
import 'time_sync_service.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/platform/system_metrics_service.dart';
import 'dart:math';

class SlotWarmUpState {
  int retryCount = 0;
  bool exhausted = false;
  bool inProgress = false;
  Timer? retryTimer;
  Timer? recoveryPollTimer;
  DateTime? lastAttempt;

  /// Monotonically increasing generation counter for this slot.
  /// Incremented every time a new warm-up is triggered so stale
  /// async callbacks from previous attempts are silently dropped.
  int generation = 0;

  void reset() {
    retryCount = 0;
    exhausted = false;
    inProgress = false;
    retryTimer?.cancel();
    retryTimer = null;
    recoveryPollTimer?.cancel();
    recoveryPollTimer = null;
    lastAttempt = null;
    generation++;
  }

  void dispose() {
    retryTimer?.cancel();
    recoveryPollTimer?.cancel();
  }
}

class PreFlightService {
  static final PreFlightService _instance = PreFlightService._internal();
  factory PreFlightService() => _instance;
  PreFlightService._internal();

  static const int _maxWarmUpRetries = 3;
  static const Duration _recoveryPollInterval = Duration(seconds: 60);

  final Map<String, SlotWarmUpState> _slotStates = {};

  bool _isDailyBootDone = false;
  Timer? _countdownTimer;
  bool _telemetryPushedForCurrentSlot = false;
  String? _lastTelemetrySlotId;

  DateTime _lastProcessedDate = DateTime(0);

  SlotWarmUpState _stateFor(String slotId) {
    return _slotStates.putIfAbsent(slotId, () => SlotWarmUpState());
  }

  /// Resets warm-up state for [slotId] so it gets a fresh retry budget.
  /// Called on slot transition (when a new class becomes the current slot).
  void resetForSlot(String slotId) {
    final existing = _slotStates[slotId];
    if (existing != null) {
      Log.i('[PreFlight] Resetting warm-up state for slot: $slotId');
      existing.reset();
    }
  }

  bool isWarmUpExhausted(String slotId) {
    return _stateFor(slotId).exhausted;
  }

  void startCountdownWatcher() {
    _countdownTimer?.cancel();
    _countdownTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _checkCountdown());
    _checkCountdown();
  }

  Future<void> _checkCountdown() async {
    try {
      final now = TimeSyncService.timeNow;

      if (now.day != _lastProcessedDate.day ||
          now.month != _lastProcessedDate.month ||
          now.year != _lastProcessedDate.year) {
        Log.i(
            '[PreFlight] New day detected. Resetting all daily flags and slot states.');
        for (final state in _slotStates.values) {
          state.dispose();
        }
        _slotStates.clear();
        _isDailyBootDone = false;
        _telemetryPushedForCurrentSlot = false;
        _lastTelemetrySlotId = null;
        _lastProcessedDate = now;
      }

      final todaySlots = await globalDeviceRepository.getTodayTimeline();
      final timeStr =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      final nextSlot = todaySlots
          .where((s) => s.startTime.compareTo(timeStr) > 0)
          .firstOrNull;
      if (nextSlot == null) return;

      final startTimeParts = nextSlot.startTime.split(':');
      final startDateTime = DateTime(now.year, now.month, now.day,
          int.parse(startTimeParts[0]), int.parse(startTimeParts[1]));
      final diffMin = startDateTime.difference(now).inMinutes;

      Log.i(
          '[PreFlight] Next class: ${nextSlot.courseName} in $diffMin minutes.');

      if (_lastTelemetrySlotId != nextSlot.slotId) {
        _telemetryPushedForCurrentSlot = false;
        _lastTelemetrySlotId = nextSlot.slotId;
      }

      if (diffMin <= 10 && diffMin > 3) {
        _triggerStatusCheck(nextSlot.slotId);
      }

      // Warm-up at T-3 is handled by IdleScreen._checkUpcomingClass (10s
      // timer), which passes the onSuccess/onStatusChange callbacks needed
      // to update the UI to "READY". Skipping here prevents the countdown
      // watcher from consuming the slot's retry budget without callbacks.
    } catch (e) {
      Log.w('[PreFlight] Countdown check failed: $e');
    }
  }

  Future<void> _triggerStatusCheck(String slotId) async {
    if (_telemetryPushedForCurrentSlot) {
      Log.d('[PreFlight] Telemetry already pushed for this slot.');
      return;
    }
    Log.i(
        '[PreFlight] T-10 Window Detected. Status 1 Handshake for $slotId...');
    try {
      await ApiService.syncTime();
      await _pushHardwareTelemetry();
      _telemetryPushedForCurrentSlot = true;
      Log.i('[PreFlight] Status 1 Handshake Successful.');
    } catch (e) {
      Log.e('[PreFlight] Status 1 failed (will retry in 1 minute): $e');
    }
  }

  Future<void> runDailyBoot() async {
    if (_isDailyBootDone) return;

    final jitterSeconds = Random().nextInt(61) - 30;
    Log.i('[PreFlight] Daily Boot with ${jitterSeconds}s jitter...');
    await Future.delayed(Duration(seconds: jitterSeconds.abs()));

    Log.i('[PreFlight] Starting Daily Boot Sequence...');

    int attempts = 0;
    bool success = false;
    final fibonacci = [1, 2, 3, 5, 8];

    while (!success && attempts < fibonacci.length) {
      try {
        await ApiService.syncTime();

        final isar = SessionManager.isar;

        final cutoff =
            TimeSyncService.timeNow.subtract(const Duration(hours: 2));
        await isar.writeTxn(() async {
          final staleSessions = await isar.activeSessions
              .filter()
              .scheduledEndTimeLessThan(cutoff)
              .findAll();
          await isar.activeSessions
              .deleteAll(staleSessions.map((s) => s.id).toList());
        });

        await _pushHardwareTelemetry();

        success = true;
        _isDailyBootDone = true;
        Log.i('[PreFlight] Daily Boot Complete.');
      } catch (e) {
        attempts++;
        if (attempts < fibonacci.length) {
          final waitMin = fibonacci[attempts - 1];
          Log.e(
              '[PreFlight] Daily Boot Attempt $attempts Failed. Retrying in $waitMin min...');
          await Future.delayed(Duration(minutes: waitMin));
        }
      }
    }
  }

  Future<Map<String, dynamic>?> forceWarmUp(String slotId,
      {void Function(Map<String, dynamic> result)? onSuccess,
      void Function(String status)? onStatusChange,
      void Function(String error)? onError}) async {
    final state = _stateFor(slotId);
    state.retryTimer?.cancel();
    state.recoveryPollTimer?.cancel();
    state.retryCount = 0;
    state.exhausted = false;
    state.inProgress = false;
    Log.i('[PreFlight] Forcing warm-up for slot: $slotId');
    return runPerSessionWarmUp(slotId,
        onSuccess: onSuccess, onStatusChange: onStatusChange, onError: onError);
  }

  Future<Map<String, dynamic>?> runPerSessionWarmUp(String slotId,
      {bool isRetry = false,
      void Function(Map<String, dynamic> result)? onSuccess,
      void Function(String status)? onStatusChange,
      void Function(String error)? onError}) async {
    final state = _stateFor(slotId);

    if (state.inProgress && !isRetry) return null;

    if (!isRetry) {
      state.retryCount = 0;
      state.exhausted = false;
      state.retryTimer?.cancel();
      state.generation++;
    }

    final capturedGeneration = state.generation;

    state.inProgress = true;
    state.retryCount++;

    if (onStatusChange != null) onStatusChange('connecting');

    Log.i('[PreFlight] Attempt ${state.retryCount}: Warm-Up for slot: $slotId');

    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final result =
          await ApiService.getPreFlight(slotId, retryCount: state.retryCount);
      final t3 = DateTime.now().millisecondsSinceEpoch;

      final serverTs = (result['server_timestamp'] ?? result['server_timestamp_ms'] ?? 0) as int;

      TimeSyncService.synchronizeWithServerLegacy(
          DateTime.fromMillisecondsSinceEpoch(t0), DateTime.fromMillisecondsSinceEpoch(t3), serverTs);

      if (capturedGeneration != state.generation) {
        Log.d('[PreFlight] Stale warm-up success ignored for $slotId (gen $capturedGeneration != ${state.generation})');
        state.inProgress = false;
        return null;
      }

      Log.i('[PreFlight] Warm-Up Successful for slot: $slotId');
      state.inProgress = false;
      state.exhausted = false;
      if (onSuccess != null) onSuccess(result);
      return result;
    } catch (e) {
      Log.e('[PreFlight] Warm-Up Attempt ${state.retryCount} Failed: $e');

      if (capturedGeneration != state.generation) {
        Log.d('[PreFlight] Stale warm-up failure ignored for $slotId (gen $capturedGeneration != ${state.generation})');
        state.inProgress = false;
        return null;
      }

      if (state.retryCount >= _maxWarmUpRetries) {
        // All retries exhausted — notify UI of failure and start recovery polling.
        if (onStatusChange != null) onStatusChange('none');
        if (onError != null) onError(e.toString());
        Log.w(
            '[PreFlight] Max retries reached for $slotId. Starting recovery polling.');
        state.inProgress = false;
        state.exhausted = true;
        _startRecoveryPolling(slotId,
            onSuccess: onSuccess, onStatusChange: onStatusChange, onError: onError);
        return null;
      }

      // Retries remain — keep status as 'connecting' so the UI shows
      // "WARMING UP..." instead of flashing "PENDING" between attempts.
      if (onError != null) onError(e.toString());

      final delay = Duration(seconds: 30 * (1 << (state.retryCount - 1)));
      final jitter = Random().nextInt(5);
      final nextRetryDelay = delay + Duration(seconds: jitter);

      Log.i(
          '[PreFlight] Retrying in ${nextRetryDelay.inSeconds}s (attempt ${state.retryCount})...');

      state.retryTimer = Timer(nextRetryDelay, () {
        runPerSessionWarmUp(slotId,
            isRetry: true,
            onSuccess: onSuccess,
            onStatusChange: onStatusChange,
            onError: onError);
      });

      return null;
    }
  }

  void _startRecoveryPolling(String slotId,
      {void Function(Map<String, dynamic> result)? onSuccess,
      void Function(String status)? onStatusChange,
      void Function(String error)? onError}) async {
    final state = _stateFor(slotId);
    state.recoveryPollTimer?.cancel();

    Log.i(
        '[PreFlight] Recovery polling started for slot: $slotId (every ${_recoveryPollInterval.inSeconds}s)');

    state.recoveryPollTimer = Timer.periodic(_recoveryPollInterval, (_) async {
      final now = TimeSyncService.timeNow;

      final todaySlots = await globalDeviceRepository.getTodayTimeline();
      final slot = todaySlots.where((s) => s.slotId == slotId).firstOrNull;

      if (slot == null || now.isAfter(_parseSlotEnd(slot))) {
        Log.i('[PreFlight] Slot $slotId has ended. Stopping recovery polling.');
        state.recoveryPollTimer?.cancel();
        state.recoveryPollTimer = null;
        return;
      }

      final alive = await ApiService.boardReady();
      if (alive) {
        Log.i(
            '[PreFlight] Server is back online for slot $slotId. Re-triggering warm-up.');
        state.recoveryPollTimer?.cancel();
        state.recoveryPollTimer = null;
        state.exhausted = false;
        state.retryCount = 0;
        runPerSessionWarmUp(slotId,
            onSuccess: onSuccess, onStatusChange: onStatusChange, onError: onError);
      } else {
        Log.d('[PreFlight] Recovery poll for $slotId — server still down.');
      }
    });
  }

  DateTime _parseSlotEnd(TimetableEntry slot) {
    final now = TimeSyncService.timeNow;
    final parts = slot.endTime.split(':');
    return DateTime(
        now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  Future<void> _pushHardwareTelemetry() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final registration = await globalDeviceRepository.getRegistration();
      final boardId = registration?.smartBoardId ?? 'UNKNOWN';
      final metrics = await SystemMetricsService.collect();
      final data = {
        'boardId': boardId,
        'cpu_load_percent': metrics.cpuLoadPercent,
        'memory_usage_mb': metrics.memoryUsageMb,
        'network_latency_ms': metrics.networkLatencyMs,
        'app_version': packageInfo.version,
        'timestamp_ms': TimeSyncService.timeNow.millisecondsSinceEpoch,
      };
      await ApiService.sendHardwareTelemetry(data);
      Log.i('[PreFlight] Hardware Telemetry pushed for $boardId.');
    } catch (e) {
      Log.w('[PreFlight] Telemetry push failed: $e');
    }
  }
}
