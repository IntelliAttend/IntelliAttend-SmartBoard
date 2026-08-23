import 'dart:async';
import 'package:window_manager/window_manager.dart';
import 'kiosk_service.dart';
import 'notification_service.dart';
import '../../services/time_sync_service.dart';
import '../../services/api_service.dart';
import '../../services/session_state_service.dart';
import '../../services/session_manager.dart';
import '../state/board_state_machine.dart';
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

  final Set<String> _t0FiredSlots = {};
  final Set<String> _t1FiredSlots = {};
  final Set<String> _backPressureFiredSlots = {};
  final Set<String> _endOfClassFiredSlots = {};

  /// Tracks which slots have had attendance completed locally.
  /// Replaces Firestore queries in the T-5 check — zero network cost.
  final Set<String> _attendanceTakenSlots = {};

  /// Tracks which slots have already been auto-closed to prevent duplicate API calls.
  final Set<String> _autoClosedSlots = {};

  /// Called by IdleScreen when OTP submission succeeds.
  /// Marks the slot as attended so the T-5 warning is suppressed.
  void markAttendanceTaken(String slotId) {
    _attendanceTakenSlots.add(slotId);
    Log.i('[Orchestrator] Attendance marked for slot $slotId');
  }

  /// Returns true if attendance has been marked for the given slot.
  /// Used by IdleScreen to decide whether to skip the 2-min cooldown.
  bool hasTakenAttendance(String slotId) => _attendanceTakenSlots.contains(slotId);

  /// Called during cooldown to reset all attendance tracking so the next
  /// class starts with a clean slate.
  void resetAttendanceTracking() {
    _attendanceTakenSlots.clear();
    _autoClosedSlots.clear();
    _t0FiredSlots.clear();
    _t1FiredSlots.clear();
    _backPressureFiredSlots.clear();
    _endOfClassFiredSlots.clear();
    Log.i('[Orchestrator] All attendance & slot tracking reset for cooldown.');
  }

  void start() {
    _monitorTimer?.cancel();
    // 10s interval so T-0 / T-1 events fire with sub-minute precision —
    // critical for auto-terminate when app is minimized.
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
        _t0FiredSlots.clear();
        _t1FiredSlots.clear();
        _backPressureFiredSlots.clear();
        _endOfClassFiredSlots.clear();
        _autoClosedSlots.clear();
        _lastTickDate = now;
      }

      // ── Fullscreen health check (replaces KioskService's separate 10s
      //     watchdog timer).  Single source of truth for window state so
      //     concurrent platform-channel calls cannot race and crash the
      //     Flutter engine on Windows.
      await KioskService.ensureFullscreen();

      final allTodaySlots = await globalDeviceRepository.getTodayTimeline();
      if (allTodaySlots.isEmpty) return;
      // Filter to only regular class/lab slots — skip breaks, tutorial, library
      final todaySlots = allTodaySlots.where((s) => !s.isBreak && s.slotType != 'tutorial' && s.slotType != 'library').toList();
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

      // ── Next-slot checks (T-1 auto-terminate / T-0) ────────────────────
      final timeStr = _formatHHMM(now);
      final nextSlot = todaySlots
          .where((s) => s.startTime.compareTo(timeStr) > 0)
          .firstOrNull;

      if (nextSlot != null) {
        final nextStart = _parseTime(nextSlot.startTime, now);
        final diffSec = nextStart.difference(now).inSeconds;
        final slotKey = nextSlot.slotId;

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

      // ── T-1: Auto-terminate when minimized (1 min before slot end) ─────
      // Only fires if app is minimized — don't interrupt active marking.
      if (currentSlot != null) {
        final slotEnd = _parseTime(currentSlot.endTime, now);
        final diffSec = slotEnd.difference(now).inSeconds;
        final t1Key = '${currentSlot.slotId}_t1';

        if (diffSec <= 60 && diffSec > 0 && !_t1FiredSlots.contains(t1Key)) {
          _t1FiredSlots.add(t1Key);

          final sessionState = SessionStateService().currentState;
          final boardState = BoardStateMachine().currentState;

          // Only fire if session is active AND board is NOT on AttendanceScreen
          if (sessionState.isActive && boardState != BoardState.active) {
            final isMinimized = await windowManager.isMinimized();
            if (isMinimized) {
              Log.i('[Orchestrator] T-1: Auto-terminating session ${sessionState.sessionId} — app minimized, slot ending in ${diffSec}s');
              await KioskService.setMode(KioskMode.fullscreen);

              // Force board to CLOSED immediately to show SummaryScreen
              BoardStateMachine().forceTransitionTo(BoardState.closed);

              // Terminate on server (best-effort, for cleanup)
              try {
                await ApiService.terminateSession(sessionState.sessionId);
              } catch (e) {
                Log.e('[Orchestrator] T-1 terminate API failed: $e');
              }
            } else {
              Log.i('[Orchestrator] T-1: Session ending in ${diffSec}s but app not minimized — skipping auto-terminate');
            }
          }
        }
      }

      // ── End-of-class check (T-5, no attendance taken) ────────────────────
      // Uses local _attendanceTakenSlots set — zero Firestore queries.
      if (currentSlot != null) {
        final slotEnd = _parseTime(currentSlot.endTime, now);
        final diffSec = slotEnd.difference(now).inSeconds;
        final endKey = '${currentSlot.slotId}_end';

        if (diffSec <= 300 && diffSec > 0 && !_endOfClassFiredSlots.contains(endKey)) {
          _endOfClassFiredSlots.add(endKey);

          final attendanceTaken = _attendanceTakenSlots.contains(currentSlot.slotId);
          if (!attendanceTaken) {
            Log.w('🚨 [Orchestrator] Class ending in ~${diffSec ~/ 60} min — No attendance taken (local check). Restoring window.');
            await KioskService.setMode(KioskMode.fullscreen);
            await NotificationService.showWarning(
              'Attendance Required',
              '"${currentSlot.courseName}" ends in ~${diffSec ~/ 60} minutes. Please take attendance now.',
            );
          }
        }

        // ── Auto-close session when slot endTime passes ──────────────────
        // Skip if T-1 already terminated this session.
        if (!_t1FiredSlots.contains('${currentSlot.slotId}_t1') &&
            now.isAfter(slotEnd) && !_autoClosedSlots.contains(currentSlot.slotId)) {
          _autoClosedSlots.add(currentSlot.slotId);
          final sessionState = SessionStateService().currentState;
          final boardState = BoardStateMachine().currentState;
          if (sessionState.isActive) {
            Log.i('[Orchestrator] Auto-closing session ${sessionState.sessionId} — slot ${currentSlot.slotId} ended');

            // If board is NOT on AttendanceScreen, force CLOSED immediately
            // so SummaryScreen appears without waiting for server round-trip.
            if (boardState != BoardState.active) {
              BoardStateMachine().forceTransitionTo(BoardState.closed);
            }

            // Terminate on server (best-effort)
            try {
              await ApiService.terminateSession(sessionState.sessionId);
            } catch (e) {
              Log.e('[Orchestrator] Auto-close API failed: $e');
            }
          }
        }
      }

      // ── Safety net: auto-terminate if currentSlot is null (break period)
      //    but a session is still active past its scheduled end time.
      //    This handles the case where getCurrentSlot() returns null because
      //    we're in a break/tutorial/library slot, but a session from the
      //    previous class was never ended.
      //    Guard: skip if BoardState is active — the user is on AttendanceScreen
      //    actively marking attendance; terminating would interrupt them.
      if (currentSlot == null) {
        final sessionState = SessionStateService().currentState;
        final boardState = BoardStateMachine().currentState;
        if (sessionState.isActive && boardState != BoardState.active) {
          // Look up the session's scheduled end time from Isar
          final session = await SessionManager.getResumeableSession();
          if (session != null && now.isAfter(session.scheduledEndTime)) {
            if (!_autoClosedSlots.contains(session.slotId)) {
              _autoClosedSlots.add(session.slotId);
              Log.i('[Orchestrator] Safety-net auto-closing session ${session.sessionId} — past scheduled end during break');

              // Force CLOSED immediately (board is already not on AttendanceScreen)
              BoardStateMachine().forceTransitionTo(BoardState.closed);

              try {
                await ApiService.terminateSession(session.sessionId);
              } catch (e) {
                Log.e('[Orchestrator] Safety-net auto-close API failed: $e');
              }
            }
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
