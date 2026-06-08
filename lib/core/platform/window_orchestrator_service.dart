import 'dart:async';
import 'package:window_manager/window_manager.dart';
import '../config/firestore_schema.dart';
import 'kiosk_service.dart';
import 'notification_service.dart';
import '../../services/time_sync_service.dart';
import '../../services/firestore_rest_client.dart';
import '../utils/logger.dart';
import '../../main.dart';

class WindowOrchestratorService {
  static final WindowOrchestratorService _instance = WindowOrchestratorService._internal();
  factory WindowOrchestratorService() => _instance;
  WindowOrchestratorService._internal();

  Timer? _monitorTimer;

  /// Guards against timer stacking: if a tick is still running when the next
  /// 10s interval fires (e.g. due to slow DB queries over poor Wi-Fi), the
  /// overlapping tick is silently dropped. Two concurrent setMode calls would
  /// crash the Flutter engine on Windows.
  bool _isTickRunning = false;

  DateTime _lastTickDate = DateTime(0);
  bool _isFirstClassPreBootDone = false;

  final Set<String> _t3FiredSlots = {};
  final Set<String> _t0FiredSlots = {};
  final Set<String> _backPressureFiredSlots = {};
  final Set<String> _endOfClassFiredSlots = {};

  void start() {
    _monitorTimer?.cancel();
    // Increased from 60s to 10s so T-3 / T-0 window events fire with
    // sub-minute precision — critical for restoring from minimized state.
    _monitorTimer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
    _tick();
  }

  void stop() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> _tick() async {
    if (_isTickRunning) return;
    _isTickRunning = true;
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
        _endOfClassFiredSlots.clear();
        _lastTickDate = now;
      }

      // ── Fullscreen health check (replaces KioskService's separate 10s
      //     watchdog timer).  Single source of truth for window state so
      //     concurrent platform-channel calls cannot race and crash the
      //     Flutter engine on Windows.
      await KioskService.ensureFullscreen();

      final todaySlots = await globalDeviceRepository.getTodayTimeline();
      if (todaySlots.isEmpty) return;

      // ── First-class pre-boot at T-3 (not T-10) ──────────────────────────
      if (!_isFirstClassPreBootDone) {
        final firstSlot = todaySlots.first;
        final firstStart = _parseTime(firstSlot.startTime, now);
        final diffSec = firstStart.difference(now).inSeconds;

        if (diffSec <= 180 && diffSec >= 0) {
          Log.i('🚀 [Orchestrator] T-3 First Class Pre-Boot — Restoring window.');
          await KioskService.setMode(KioskMode.fullscreen);
          _isFirstClassPreBootDone = true;
        }
      }

      // ── Next-slot checks (T-3 / T-0) ────────────────────────────────────
      final timeStr = _formatHHMM(now);
      final nextSlot = todaySlots
          .where((s) => s.startTime.compareTo(timeStr) > 0)
          .firstOrNull;

      if (nextSlot != null) {
        final nextStart = _parseTime(nextSlot.startTime, now);
        final diffSec = nextStart.difference(now).inSeconds;
        final slotKey = nextSlot.slotId;

        // T-3 window: restore window + notification (if currently minimized)
        if (diffSec <= 180 && diffSec > 0 && !_t3FiredSlots.contains(slotKey)) {
          _t3FiredSlots.add(slotKey);
          Log.i('📺 [Orchestrator] T-3 Slot[$slotKey] — Restoring window (diffSec=$diffSec).');
          await KioskService.setMode(KioskMode.fullscreen);
          final isMinimized = await windowManager.isMinimized();
          if (isMinimized) {
            await NotificationService.showWarning(
              'Class Starting Soon',
              '${nextSlot.courseName} starts in ~3 minutes. Please return to SmartBoard.',
            );
          }
        }

        // T-0: ensure window is restored + show OTP card (safety net —
        // IdleScreen handles the card via its own 10s timer).
        if (diffSec <= 0 && !_t0FiredSlots.contains(slotKey)) {
          _t0FiredSlots.add(slotKey);
          Log.i('🚨 [Orchestrator] T-0 Slot[$slotKey] — Ensuring window is restored.');
          await KioskService.setMode(KioskMode.fullscreen);
          final isMinimized = await windowManager.isMinimized();
          if (isMinimized) {
            await NotificationService.showWarning(
              'Class Started',
              '${nextSlot.courseName} has started. Please return to SmartBoard.',
            );
          }
        }
      }

      // ── Back-to-back pressure (T-10 to next class while current is active) ──
      final currentSlot = await globalDeviceRepository.getCurrentSlot();
      if (currentSlot != null && nextSlot != null) {
        final nextStart = _parseTime(nextSlot.startTime, now);
        final diffSec = nextStart.difference(now).inSeconds;
        final pressureKey = '${currentSlot.slotId}_pressure';

        if (diffSec <= 600 && diffSec > 0 && !_backPressureFiredSlots.contains(pressureKey)) {
          _backPressureFiredSlots.add(pressureKey);
          Log.w('⚠️ [Orchestrator] Back-to-back pressure: Next class (${nextSlot.courseName}) in ~${diffSec ~/ 60} min.');
          await NotificationService.showWarning(
            'Attendance Deadline',
            'Next class "${nextSlot.courseName}" starts in ~${diffSec ~/ 60} minutes. Please complete current attendance.',
          );
        }
      }

      // ── End-of-class check (T-5, no attendance taken) ────────────────────
      if (currentSlot != null) {
        final slotEnd = _parseTime(currentSlot.endTime, now);
        final diffSec = slotEnd.difference(now).inSeconds;
        final endKey = '${currentSlot.slotId}_end';

        if (diffSec <= 300 && diffSec > 0 && !_endOfClassFiredSlots.contains(endKey)) {
          _endOfClassFiredSlots.add(endKey);
          try {
            final registration = await globalDeviceRepository.getRegistration();
            if (registration != null) {
              final boardId = registration.smartBoardId;
              final activeSessions = await FirestoreRestClient.runQuery(
                collection: FirestoreSchema.activeSessions,
                where: {FirestoreSchema.fieldSmartBoardId: boardId, FirestoreSchema.fieldStatus: FirestoreSchema.statusActive},
                limit: 1,
              );

              bool attendeeFound = false;
              if (activeSessions.isNotEmpty) {
                final sessionId = activeSessions.first[FirestoreSchema.fieldDocId]?.toString();
                if (sessionId != null) {
                  final attendees = await FirestoreRestClient.runQuery(
                    collection: FirestoreSchema.attendees,
                    where: {FirestoreSchema.fieldSessionId: sessionId},
                    limit: 1,
                  );
                  attendeeFound = attendees.isNotEmpty;
                }
              }

              if (!attendeeFound) {
                Log.w('🚨 [Orchestrator] Class ending in ~${diffSec ~/ 60} min — No attendance taken. Restoring window.');
                await KioskService.setMode(KioskMode.fullscreen);
                await NotificationService.showWarning(
                  'Attendance Required',
                  '"${currentSlot.courseName}" ends in ~${diffSec ~/ 60} minutes. Please take attendance now.',
                );
              }
            }
          } catch (e) {
            Log.w('[Orchestrator] End-of-class check failed: $e');
          }
        }
      }
    } catch (e) {
      Log.e('❌ [Orchestrator] Tick failed: $e');
    } finally {
      _isTickRunning = false;
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
