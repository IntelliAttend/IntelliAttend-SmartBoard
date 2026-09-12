import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/utils/logger.dart';
import '../../core/config/app_config.dart';
import '../../core/state/board_state_machine.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/platform/notification_service.dart';
import '../../models/isar_schemas.dart';
import '../../models/session_context.dart';
import '../../services/session_state_service.dart';
import '../../services/session_manager.dart';
import '../../services/websocket_service.dart';
import '../../services/api_service.dart';
import '../../services/heartbeat_service.dart';
import '../../services/timetable_cache.dart';
import '../../core/security/secure_storage_service.dart';
import '../../main.dart' show globalDeviceRepository;
import 'idle_screen.dart';
import 'attendance_screen.dart';
import 'summary_screen.dart';

class SessionOrchestratorScreen extends StatefulWidget {
  final DeviceRegistration registration;
  final bool completedSession;

  const SessionOrchestratorScreen({
    super.key,
    required this.registration,
    this.completedSession = false,
  });

  @override
  State<SessionOrchestratorScreen> createState() =>
      _SessionOrchestratorScreenState();
}

class _SessionOrchestratorScreenState extends State<SessionOrchestratorScreen> {
  StreamSubscription? _stateSubscription;
  StreamSubscription? _boardStateSubscription;
  final SessionStateService _sessionState = SessionStateService();
  final BoardStateMachine _boardState = BoardStateMachine();

  BoardState _currentRenderState = BoardState.idle;

  // Runtime session objects — populated on ACTIVE transition
  WebsocketService? _wsService;
  String? _cachedSlotId;

  /// Authoritative session data — owned by this orchestrator, passed through
  /// constructors to child screens. Never replaced wholesale; updated via
  /// [SessionContext.copyWith] so data is never lost during state transitions.
  SessionContext? _sessionContext;

  /// §8.4 — Session whose server termination gave up after max retries.
  /// Surfaces a persistent banner so the teacher knows the server may still
  /// consider the session active. Auto-dismisses after a grace period.
  String? _terminationFailedSessionId;


  @override
  void initState() {
    super.initState();
    // Listen for retry exhaustion — show notification if server termination
    // fails after 10 retries (2.5 min of network failures).
    HeartbeatService.onRetryExhausted = _handleRetryExhausted;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _runBootSequence();
    });
  }

  Future<void> _runBootSequence() async {
    if (!mounted) return;

    try {
      await KioskService.setMode(KioskMode.fullscreen);

      if (AppConfig.enableVideoBreaks) {
        await ApiService.syncTime().catchError((_) => 0);
      }

      _stateSubscription = _sessionState.onStateChanged.listen((state) {
        if (!mounted) return;
        _handleStateChange(state);
      });

      _boardStateSubscription = _boardState.stateStream.listen((newState) {
        if (!mounted) return;
        setState(() => _currentRenderState = newState);
      });

      // FIX: Create the WebSocket service BEFORE local recovery so that
      // _tryLocalSessionRecovery() can connect in attendance mode on success.
      // Previously _wsService was null during recovery, making the
      // connectAttendance() call a no-op and leaving the board orphaned.
      try {
        _wsService = WebsocketService(AppConfig.baseUrl);
        _wsService!.setDeviceRepository(globalDeviceRepository);
      } catch (e) {
        Log.w('[Orchestrator] WS init failed: $e');
      }

      // Local-first session recovery: check Isar for a resumable session
      // before hitting the network. Guard with timeout so a hung Isar or
      // SecureStorage call never blocks the WS connect below.
      bool recovered = false;
      try {
        recovered = await _tryLocalSessionRecovery()
            .timeout(const Duration(seconds: 8), onTimeout: () {
          Log.w('[Orchestrator] Local session recovery timed out after 8s');
          return false;
        });
      } catch (e) {
        Log.w('[Orchestrator] Local session recovery error: $e');
      }
      if (!recovered) {
        try {
          final stateResponse = await ApiService.getCurrentState();
          if (stateResponse.isNotEmpty && stateResponse['state'] != null) {
            _sessionState.applyFromRecovery(stateResponse);
          }
        } catch (e) {
          Log.w('[Orchestrator] getCurrentState failed: $e');
        }
      }
    } catch (e) {
      Log.w('[Orchestrator] Boot recovery failed: $e');
    }

    // ALWAYS connect WebSocket — even if recovery failed. This is the
    // primary path for board-mode auto-discovery via getActiveSession.
    // Moved outside the try-catch so it can never be skipped.
    if (_wsService != null) {
      try {
        await _wsService!.connectSmartBoard(
          widget.registration.smartBoardId,
        );
      } catch (e) {
        Log.w('[Orchestrator] WS connect failed: $e');
      }
    }

    if (mounted) {
      setState(() {
        _currentRenderState = _boardState.currentState;
      });
    }
  }

  Future<bool> _tryLocalSessionRecovery() async {
    try {
      final currentSlot = TimetableCache().currentSlot;
      final session = await SessionManager.getResumeableSession(
        currentSlotId: currentSlot?.slotId,
      );
      if (session == null) {
        Log.d('[Orchestrator] No resumable session in Isar');
        return false;
      }

      // Validate: if session has a slotId and it doesn't match the current
      // timetable slot, discard it — it's from a previous period.
      if (session.slotId.isNotEmpty &&
          currentSlot != null &&
          session.slotId != currentSlot.slotId) {
        Log.w('[Orchestrator] Stale session slot ${session.slotId} != current ${currentSlot.slotId} — clearing');
        await SessionManager.clearSession(session.sessionId);
        return false;
      }

      Log.i('[Orchestrator] Found resumable session: ${session.sessionId} — attempting recovery');

      final secret = await SecureStorageService.getSessionSecret(session.sessionId);
      if (secret == null) {
        Log.w('[Orchestrator] Session secret not found in SecureStorage — cannot recover');
        return false;
      }

      final restored = await _sessionState.restoreFromLocal(
        sessionId: session.sessionId,
        sessionSecret: secret,
        courseName: session.courseName,
        facultyName: session.facultyName,
        sectionId: session.sectionId,
      );

      if (restored) {
        Log.i('[Orchestrator] Session recovered successfully — resuming attendance');
        if (_wsService != null) {
          try {
            await _wsService!.connectAttendance(session.sessionId);
            Log.i('[Orchestrator] Attendance WebSocket connected for session ${session.sessionId}');
          } catch (e) {
            Log.w('[Orchestrator] Attendance WS connect failed during recovery: $e');
          }
        } else {
          Log.w('[Orchestrator] _wsService is null — attendance WS not connected');
        }
      }

      return restored;
    } catch (e) {
      Log.w('[Orchestrator] Local session recovery failed: $e');
      return false;
    }
  }

  void _handleStateChange(SessionState state) {
    if (state.isActive) {
      _cachedSlotId = TimetableCache().currentSlot?.slotId;
      // Create or update the authoritative SessionContext from the
      // SessionState. This is the single source of truth for all child screens.
      _sessionContext = SessionContext.fromState(state, slotId: _cachedSlotId);
      _prepareActiveSession(state);
    } else if (state.isClosed && _sessionContext != null) {
      // Server sent CLOSED — update context but preserve accumulated data.
      _sessionContext = _sessionContext!.copyWith(
        state: 'CLOSED',
        version: state.version,
      );
    }
  }

  Future<void> _prepareActiveSession(SessionState state) async {
    String? secret = _sessionState.sessionSecret;
    secret ??= await SecureStorageService.getSessionSecret(state.sessionId);
    if (secret == null) {
      Log.w('[Orchestrator] Cannot prepare ACTIVE — no session secret');
      return;
    }

    _sessionState.storeSessionSecrets(secret, state.websocketToken);

    if (_wsService != null && state.sessionId.isNotEmpty) {
      try {
        await _wsService!.connectAttendance(state.sessionId);
      } catch (e) {
        Log.w('[Orchestrator] Attendance WS connect failed: $e');
      }
    }
  }

  Future<void> _returnToIdle() async {
    // Clean up Isar session before resetting state to prevent phantom sessions
    // on next boot (crash recovery would otherwise find lifecycle='active').
    final currentSessionId = _sessionState.currentState.sessionId;
    if (currentSessionId.isNotEmpty) {
      try {
        await SessionManager.markSessionCompleted(currentSessionId);
        await SessionManager.clearSession(currentSessionId);
      } catch (e) {
        Log.w('[Orchestrator] Failed to cleanup Isar session on back navigation: $e');
      }
    }
    _cachedSlotId = null;
    _sessionContext = null;
    _sessionState.reset();
  }

  @override
  void dispose() {
    HeartbeatService.onRetryExhausted = null;
    _stateSubscription?.cancel();
    _boardStateSubscription?.cancel();
    _wsService?.disconnect();
    super.dispose();
  }

  void _handleRetryExhausted(String sessionId) {
    if (!mounted) return;
    Log.e('[Orchestrator] Session termination failed after max retries: $sessionId');
    // §8.4 — Surface this to the teacher: the server was never confirmed as
    // having ended the session. Informational (board already transitioned);
    // never destructive. Auto-dismisses after 30s.
    unawaited(_notifyTerminationFailed(sessionId));
    setState(() => _terminationFailedSessionId = sessionId);
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _terminationFailedSessionId == sessionId) {
        setState(() => _terminationFailedSessionId = null);
      }
    });
  }

  Future<void> _notifyTerminationFailed(String sessionId) async {
    try {
      await NotificationService.showWarning(
        'Session termination failed',
        'SmartBoard could not confirm session end with the server. '
        'If the session still appears active, contact support.',
      );
    } catch (e) {
      Log.w('[Orchestrator] Termination-failure notification error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    late Widget screen;
    switch (_currentRenderState) {
      case BoardState.idle:
        screen = IdleScreen(
          registration: widget.registration,
          completedSession: widget.completedSession,
        );
        break;
      case BoardState.active:
        final state = _sessionState.currentState;
        // Build or update SessionContext with latest state data.
        // The context is the authoritative source — child screens read from it,
        // not from the global SessionStateService singleton.
        _sessionContext ??= SessionContext(
          sessionId: state.sessionId,
          slotId: _cachedSlotId,
        );
        _sessionContext = _sessionContext!.copyWith(
          presentCount: state.presentCount,
          absentCount: state.absentCount,
          totalStudents: state.totalStudents,
          courseName: state.courseName,
          facultyName: state.facultyName,
          roomName: state.roomName,
          courseCode: state.courseCode,
        );
        screen = AttendanceScreen(
          sessionContext: _sessionContext!,
          capacity: widget.registration.capacity,
          roomName: state.roomName ?? widget.registration.roomName,
          boardId: widget.registration.smartBoardId,
          onNavigateBack: _returnToIdle,
        );
        break;
      case BoardState.closed:
        // Sync context from SessionStateService — AttendanceScreen may have
        // called updateCounts() with final attendance data before transitioning.
        // This ensures SummaryScreen receives accurate presentCount even if
        // the session_ended WS event didn't carry count data.
        final state = _sessionState.currentState;
        _sessionContext = (_sessionContext ?? SessionContext(sessionId: state.sessionId)).copyWith(
          state: 'CLOSED',
          version: state.version,
          presentCount: state.presentCount,
          absentCount: state.absentCount,
        );
        screen = SummaryScreen(
          sessionContext: _sessionContext,
          totalCapacity: widget.registration.capacity,
          onReturnToIdle: _returnToIdle,
        );
        break;
    }

    // §8.4 — Overlay a dismissible banner when a server termination gave up
    // after max retries. Non-intrusive: never a modal, auto-dismisses.
    final failedSessionId = _terminationFailedSessionId;
    if (failedSessionId == null) return screen;
    return Stack(
      children: [
        screen,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _buildTerminationFailedBanner(failedSessionId),
        ),
      ],
    );
  }

  Widget _buildTerminationFailedBanner(String sessionId) {
    return Material(
      color: const Color(0xFFB45309), // amber-700
      elevation: 4,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Session $sessionId could not be closed on the server. '
                  'If it still appears active please contact support.',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: () {
                  if (mounted) setState(() => _terminationFailedSessionId = null);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
