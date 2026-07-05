import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../../core/utils/logger.dart';
import '../../core/config/app_config.dart';
import '../../core/state/board_state_machine.dart';
import '../../core/platform/kiosk_service.dart';
import '../../core/platform/hardware_fingerprint_service.dart';
import '../../models/isar_schemas.dart';
import '../../services/session_state_service.dart';
import '../../services/websocket_service.dart';
import '../../services/api_service.dart';
import '../../core/security/secure_storage_service.dart';
import 'idle_screen.dart';
import 'preparing_screen.dart';
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

      // Subscribe to state changes BEFORE applying recovery so we don't
      // miss the initial event (broadcast streams don't replay).
      _stateSubscription = _sessionState.onStateChanged.listen((state) {
        if (!mounted) return;
        _handleStateChange(state);
      });

      _boardStateSubscription = _boardState.stateStream.listen((newState) {
        if (!mounted) return;
        setState(() => _currentRenderState = newState);
      });

      final stateResponse = await ApiService.getCurrentState();
      if (stateResponse.isNotEmpty && stateResponse['state'] != null) {
        _sessionState.applyFromRecovery(stateResponse);
      }

      try {
        _wsService = WebsocketService(AppConfig.baseUrl);
        await _wsService!.connectSmartBoard(
          widget.registration.smartBoardId,
        );
      } catch (e) {
        Log.w('[Orchestrator] WS connect failed: $e');
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

  Future<String?> _deriveSecretFromHalf1(String half1) async {
    try {
      final deviceId = await HardwareFingerprintService.getDeviceId();
      final half2 = Hmac(sha256, utf8.encode(deviceId))
          .convert(utf8.encode(half1))
          .toString()
          .substring(0, 16);
      return '$half1$half2';
    } catch (e) {
      Log.e('[Orchestrator] Secret derivation failed: $e');
      return null;
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
    if (secret == null && state.sessionSecretHalf1 != null) {
      secret = await _deriveSecretFromHalf1(state.sessionSecretHalf1!);
    }
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
      case BoardState.preparing:
        final state = _sessionState.currentState;
        return PreparingScreen(
          courseName: state.courseName ?? 'Class',
          facultyName: state.facultyName ?? 'Professor',
          roomName: widget.registration.roomName,
          sectionId: state.sectionId,
          startTime: state.startTime,
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
          websocketService: _wsService ?? WebsocketService(AppConfig.baseUrl),
          initialPresentCount: state.presentCount,
          capacity: widget.registration.capacity,
          courseName: state.courseName ?? 'Class',
          facultyName: state.facultyName ?? 'Professor',
          sectionId: state.sectionId,
          roomName: state.roomName ?? widget.registration.roomName,
          boardId: widget.registration.smartBoardId,
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
