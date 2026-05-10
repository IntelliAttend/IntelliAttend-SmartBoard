import 'dart:async';
import 'package:window_manager/window_manager.dart';
import 'kiosk_service.dart';
import 'notification_service.dart';
import '../../services/time_sync_service.dart';
import '../utils/logger.dart';
import '../../main.dart';

class WindowOrchestratorService {
  static final WindowOrchestratorService _instance = WindowOrchestratorService._internal();
  factory WindowOrchestratorService() => _instance;
  WindowOrchestratorService._internal();

  Timer? _monitorTimer;

  DateTime _lastTickDate = DateTime(0);
  bool _isFirstClassPreBootDone = false;

  final Set<String> _t3FiredSlots = {};
  final Set<String> _t0FiredSlots = {};
  final Set<String> _backPressureFiredSlots = {};

  void start() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    _tick();
  }

  void stop() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> _tick() async {
    try {
      final now = TimeSyncService.timeNow;

      if (now.day != _lastTickDate.day ||
          now.month != _lastTickDate.month ||
          now.year != _lastTickDate.year) {
        Log.i('📅 [Orchestrator] New day detected. Resetting all daily flags.');
        _isFirstClassPreBootDone = false;
        _t3FiredSlots.clear();
        _t0FiredSlots.clear();
        _backPressureFiredSlots.clear();
        _lastTickDate = now;
      }

      final todaySlots = await globalDeviceRepository.getTodayTimeline();
      if (todaySlots.isEmpty) return;

      if (!_isFirstClassPreBootDone) {
        final firstSlot = todaySlots.first;
        final firstStart = _parseTime(firstSlot.startTime, now);
        final diffToFirst = firstStart.difference(now).inMinutes;

        if (diffToFirst <= 10 && diffToFirst >= 0) {
          Log.i('🚀 [Orchestrator] T-10 First Class Pre-Boot — Bringing window to foreground.');
          await KioskService.setMode(KioskMode.locked);
          _isFirstClassPreBootDone = true;
        }
      }

      final timeStr = _formatHHMM(now);
      final nextSlot = todaySlots
          .where((s) => s.startTime.compareTo(timeStr) > 0)
          .firstOrNull;

      if (nextSlot != null) {
        final nextStart = _parseTime(nextSlot.startTime, now);
        final diffMin = nextStart.difference(now).inMinutes;
        final slotKey = nextSlot.slotId;

        if (diffMin <= 3 && diffMin > 0 && !_t3FiredSlots.contains(slotKey)) {
          _t3FiredSlots.add(slotKey);
          final isMinimized = await windowManager.isMinimized();
          if (isMinimized) {
            Log.i('🔔 [Orchestrator] T-3 Slot[$slotKey] — App is minimized. Sending OS notification.');
            await NotificationService.showWarning(
              'Class Starting Soon',
              '${nextSlot.courseName} starts in ~3 minutes. Please return to SmartBoard.',
            );
          } else {
            Log.i('📺 [Orchestrator] T-3 Slot[$slotKey] — App is visible. Session ID fetch is in progress.');
          }
        }

        if (diffMin <= 0 && !_t0FiredSlots.contains(slotKey)) {
          _t0FiredSlots.add(slotKey);
          Log.i('🚨 [Orchestrator] T-0 Slot[$slotKey] — FORCING window takeover to locked mode.');
          await KioskService.setMode(KioskMode.locked);
        }
      }

      final currentSlot = await globalDeviceRepository.getCurrentSlot();
      if (currentSlot != null && nextSlot != null) {
        final nextStart = _parseTime(nextSlot.startTime, now);
        final diffToNext = nextStart.difference(now).inMinutes;
        final pressureKey = '${currentSlot.slotId}_pressure';

        if (diffToNext <= 10 && diffToNext > 0 && !_backPressureFiredSlots.contains(pressureKey)) {
          _backPressureFiredSlots.add(pressureKey);
          Log.w('⚠️ [Orchestrator] Back-to-back pressure: Next class (${nextSlot.courseName}) in ~$diffToNext min.');
          await NotificationService.showWarning(
            'Attendance Deadline',
            'Next class "${nextSlot.courseName}" starts in ~$diffToNext minutes. Please complete current attendance.',
          );
        }
      }

    } catch (e) {
      Log.e('❌ [Orchestrator] Tick failed: $e');
    }
  }

  DateTime _parseTime(String timeStr, DateTime reference) {
    final parts = timeStr.split(':');
    return DateTime(
      reference.year, reference.month, reference.day,
      int.parse(parts[0]), int.parse(parts[1]),
    );
  }

  String _formatHHMM(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
