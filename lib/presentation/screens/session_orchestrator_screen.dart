import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/utils/logger.dart';
import '../../core/config/app_config.dart';
import '../../core/state/board_state_machine.dart';
import '../../core/platform/kiosk_service.dart';
import '../../models/isar_schemas.dart';
import '../../services/session_state_service.dart';
import '../../services/session_manager.dart';
import '../../services/websocket_service.dart';
import '../../services/api_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../main.dart' show globalDeviceRepository;
import 'idle_screen.dart';
import 'igniting_screen.dart';
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


  @override
  void initState() {
    super.initState();
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
      // before hitting the network.
      final recovered = await _tryLocalSessionRecovery();
      if (!recovered) {
        final stateResponse = await ApiService.getCurrentState();
        if (stateResponse.isNotEmpty && stateResponse['state'] != null) {
          _sessionState.applyFromRecovery(stateResponse);
        }
      }

      // Connect the WebSocket. If local recovery succeeded, this connects
      // in board mode for monitoring; the attendance WS was already connected
      // inside _tryLocalSessionRecovery(). If recovery failed, this is the
      // primary path — board mode will auto-discover the active session via
      // _handleBoardConnected → getActiveSession → join_session.
      if (_wsService != null) {
        try {
          await _wsService!.connectSmartBoard(
            widget.registration.smartBoardId,
          );
        } catch (e) {
          Log.w('[Orchestrator] WS connect failed: $e');
        }
      }
    } catch (e) {
      Log.w('[Orchestrator] Boot recovery failed: $e');
    }

    if (mounted) {
      setState(() {
        _currentRenderState = _boardState.currentState;
      });
    }
  }

  Future<bool> _tryLocalSessionRecovery() async {
    try {
      final session = await SessionManager.getResumeableSession();
      if (session == null) {
        Log.d('[Orchestrator] No resumable session in Isar');
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
        // FIX: _wsService is now initialized before this method is called,
        // so connectAttendance() will actually connect. Previously it was
        // null here, making this a no-op and leaving the board orphaned.
        if (_wsService != null) {
          try {
            await _wsService!.connectAttendance(session.sessionId);
            Log.i('[Orchestrator] Attendance WebSocket connected for session ${session.sessionId}');
          } catch (e) {
            Log.w('[Orchestrator] Attendance WS connect failed during recovery: $e');
            // Fallback: if attendance WS fails, the board-mode connect
            // in _runBootSequence will attempt auto-join via getActiveSession().
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
      _prepareActiveSession(state);
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

  void _returnToIdle() {
    _sessionState.reset();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _boardStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentRenderState) {
      case BoardState.idle:
        return IdleScreen(
          registration: widget.registration,
          completedSession: widget.completedSession,
        );
      case BoardState.igniting:
        final state = _sessionState.currentState;
        return IgnitingScreen(
          courseName: state.courseName ?? 'Class',
          facultyName: state.facultyName ?? 'Professor',
          roomName: widget.registration.roomName,
          capacity: widget.registration.capacity,
          smartBoardId: widget.registration.smartBoardId,
        );
      case BoardState.active:
        final state = _sessionState.currentState;
        return AttendanceScreen(
          sessionId: state.sessionId,
          initialPresentCount: state.presentCount,
          capacity: widget.registration.capacity,
          courseName: state.courseName ?? 'Class',
          facultyName: state.facultyName ?? 'Professor',
          roomName: state.roomName ?? widget.registration.roomName,
          boardId: widget.registration.smartBoardId,
          onNavigateBack: _returnToIdle,
        );
      case BoardState.closed:
        final state = _sessionState.currentState;
        return SummaryScreen(
          sessionId: state.sessionId,
          presentCount: state.presentCount,
          totalCapacity: widget.registration.capacity,
          courseName: state.courseName ?? 'Class',
          facultyName: state.facultyName ?? 'Professor',
          onReturnToIdle: _returnToIdle,
        );
    }
  }
}
