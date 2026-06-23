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
import '../../services/totp_engine.dart';
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

class _SessionOrchestratorScreenState extends State<SessionOrchestratorScreen>
    with WidgetsBindingObserver {
  StreamSubscription? _stateSubscription;
  StreamSubscription? _boardStateSubscription;
  final SessionStateService _sessionState = SessionStateService();
  final BoardStateMachine _boardState = BoardStateMachine();

  BoardState _currentRenderState = BoardState.idle;

  // Runtime session objects — populated on ACTIVE transition
  WebsocketService? _wsService;
  String _wsAccessToken = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _runBootSequence();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      Log.i('[Orchestrator] App resumed — recovering state from server');
      _recoverState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSubscription?.cancel();
    _boardStateSubscription?.cancel();
    _wsService?.disconnect();
    super.dispose();
  }

  Future<void> _recoverState() async {
    try {
      final stateResponse = await ApiService.getCurrentState();
      if (!mounted) return;
      if (stateResponse.isNotEmpty && stateResponse['state'] != null) {
        final stateStr = stateResponse['state'] as String;
        final half1 = stateResponse['session_secret_half1'] as String?;
        final recoveredWsToken = stateResponse['websocket_token'] as String?;

        if (stateStr == 'ACTIVE' || stateStr == 'CLOSED') {
          final sessionId = stateResponse['session_id'] as String? ?? '';
          String? secret;

          if (half1 != null) {
            secret = await _deriveSecretFromHalf1(half1);
          } else {
            secret = await SecureStorageService.getSessionSecret(sessionId);
          }

          if (secret != null && stateStr == 'ACTIVE') {
            final engine = TotpEngine(sessionId: sessionId, sessionSecret: secret);
            _sessionState.storeSessionSecrets(secret, engine, recoveredWsToken);
          }
        }

        _sessionState.applyFromRecovery(stateResponse);
      }
    } catch (e) {
      Log.w('[Orchestrator] State recovery failed: $e');
    }
  }

  Future<void> _runBootSequence() async {
    if (!mounted) return;

    try {
      await KioskService.setMode(KioskMode.fullscreen);

      if (AppConfig.enableVideoBreaks) {
        await ApiService.syncTime().catchError((_) => 0);
      }

      await _recoverState();

      final websocketToken = _sessionState.websocketAccessToken ?? '';

      try {
        _wsService = WebsocketService(AppConfig.baseUrl);
        await _wsService!.connectSmartBoard(
          widget.registration.smartBoardId,
          websocketToken,
        );
      } catch (e) {
        Log.w('[Orchestrator] WS connect failed: $e');
      }
    } catch (e) {
      Log.w('[Orchestrator] Boot recovery failed: $e');
    }

    _stateSubscription = _sessionState.onStateChanged.listen((state) {
      if (!mounted) return;
      _handleStateChange(state);
    });

    _boardStateSubscription = _boardState.stateStream.listen((newState) {
      if (!mounted) return;
      setState(() => _currentRenderState = newState);
    });

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
    if (_sessionState.totpEngine != null) return;

    String? secret = _sessionState.sessionSecret;
    secret ??= await SecureStorageService.getSessionSecret(state.sessionId);
    if (secret == null && state.sessionSecretHalf1 != null) {
      secret = await _deriveSecretFromHalf1(state.sessionSecretHalf1!);
    }
    if (secret == null) {
      Log.w('[Orchestrator] Cannot prepare ACTIVE — no session secret');
      return;
    }

    final engine = TotpEngine(sessionId: state.sessionId, sessionSecret: secret);
    _sessionState.storeSessionSecrets(secret, engine, state.websocketToken);

    final accessToken = state.websocketToken ?? '';
    _wsAccessToken = accessToken;

    if (_wsService != null && accessToken.isNotEmpty && state.sessionId.isNotEmpty) {
      try {
        await _wsService!.connectAttendance(state.sessionId, accessToken);
      } catch (e) {
        Log.w('[Orchestrator] Attendance WS connect failed: $e');
      }
    }
  }

  void _returnToIdle() {
    _sessionState.reset();
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
        final engine = _sessionState.totpEngine;
        if (engine == null) {
          return const SizedBox();
        }
        return AttendanceScreen(
          sessionId: state.sessionId,
          totpEngine: engine,
          websocketService: _wsService ?? WebsocketService(AppConfig.baseUrl),
          accessToken: _wsAccessToken,
          initialPresentCount: state.presentCount,
          capacity: widget.registration.capacity,
          courseName: state.courseName ?? 'Class',
          facultyName: state.facultyName ?? 'Professor',
          sectionId: state.sectionId,
          roomName: state.roomName ?? widget.registration.roomName,
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
