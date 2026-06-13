import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/repositories/device_repository.dart';
import 'api_service.dart';
import 'time_sync_service.dart';
import '../core/utils/logger.dart';
import '../core/state/board_state_machine.dart';
import '../main.dart';
import '../presentation/screens/registration_screen.dart';

class HeartbeatSessionInfo {
  final String? sessionId;
  final String? status;

  HeartbeatSessionInfo({this.sessionId, this.status});

  bool get isActive => status == 'active' && (sessionId?.isNotEmpty ?? false);
  bool get isCompleted => status == 'completed';
  bool get isEmpty => sessionId == null && status == null;
}

class HeartbeatService {
  static Timer? _timer;
  static DateTime? _startedAt;
  static String? _cachedVersion;
  static IDeviceRepository? _deviceRepository;

  static bool _started = false;
  static int _consecutiveNullSessions = 0;
  static const int _maxNullSessionsBeforeForceEnd = 2;

  static String screenState = 'unknown';

  static final List<String> _pendingTerminations = [];

  static void enqueuePendingTermination(String sessionId) {
    if (!_pendingTerminations.contains(sessionId)) {
      _pendingTerminations.add(sessionId);
      Log.w('[Heartbeat] Enqueued pending termination for $sessionId');
    }
  }

  static final StreamController<HeartbeatSessionInfo> _sessionController =
      StreamController<HeartbeatSessionInfo>.broadcast();
  static Stream<HeartbeatSessionInfo> get onSessionUpdate =>
      _sessionController.stream;

  static Future<void> start(IDeviceRepository deviceRepository) async {
    _deviceRepository = deviceRepository;

    if (_started) {
      Log.d('[Heartbeat] Already running — repository reference updated.');
      return;
    }
    _started = true;

    _startedAt ??= TimeSyncService.timeNow;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _cachedVersion = 'unknown';
    }

    _send();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _send());
    Log.i('[Heartbeat] Started — immediate beat, then every 5 m (version: $_cachedVersion).');
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _consecutiveNullSessions = 0;
    Log.i('[Heartbeat] Stopped.');
  }

  static void dispose() {
    _sessionController.close();
  }

  static Future<void> _send() async {
    for (final pendingId in List<String>.from(_pendingTerminations)) {
      try {
        await ApiService.terminateSession(pendingId);
        _pendingTerminations.remove(pendingId);
        Log.i('[Heartbeat] Pending termination succeeded for $pendingId');
      } catch (e) {
        Log.w('[Heartbeat] Pending termination retry failed for $pendingId: $e');
      }
    }

    final registration = await _deviceRepository?.getRegistration();
    if (registration == null) {
      Log.d('[Heartbeat] No registration — skipping heartbeat.');
      return;
    }

    final uptime = _startedAt != null
        ? TimeSyncService.timeNow.difference(_startedAt!).inSeconds
        : 0;

    try {
      final result = await ApiService.sendHeartbeatV2(
        smartBoardId: registration.smartBoardId,
        screenState: screenState,
        uptimeSeconds: uptime,
        appVersion: _cachedVersion ?? 'unknown',
      );

      Log.d('[Heartbeat] Raw response keys: ${result.keys.join(', ')}');

      // Try both flat and nested response structures so a server schema
      // change doesn't silently cause null-session force-ends.
      Map<String, dynamic>? sessionData = result['session'];
      if (sessionData == null && result['data'] is Map) {
        sessionData = (result['data'] as Map)['session'];
        if (sessionData != null) {
          Log.i('[Heartbeat] Resolved session from result.data.session (nested format).');
        }
      }
      if (sessionData is Map<String, dynamic>) {
        _consecutiveNullSessions = 0;
        final info = HeartbeatSessionInfo(
          sessionId: sessionData['session_id']?.toString(),
          status: sessionData['status']?.toString(),
        );
        _sessionController.add(info);
        _applySessionToStateMachine(info);
      } else if (sessionData == null) {
        _consecutiveNullSessions++;
        final isServerError = result['status'] == 'error';
        if (_consecutiveNullSessions < _maxNullSessionsBeforeForceEnd &&
            !isServerError) {
          Log.w('[Heartbeat] session: null (#$_consecutiveNullSessions) — waiting for next beat');
          return;
        }
        _sessionController.add(HeartbeatSessionInfo());
        final machine = BoardStateMachine();
        if (machine.currentState == BoardState.attendance) {
          Log.w('[Heartbeat] $_consecutiveNullSessions consecutive null sessions — force-ending');
          machine.forceTransitionTo(BoardState.summary);
        }
      }
    } catch (e) {
      if (e is ApiException &&
          (e.statusCode == 401 || e.statusCode == 404)) {
        Log.e('[Heartbeat] Auth lost or device revoked. Forcing logout...');
        await stop();
        await _deviceRepository?.clearRegistration();

        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RegistrationScreen()),
          (route) => false,
        );
        return;
      }

      Log.w('[Heartbeat] Send failed (will retry in 5m): $e');
    }
  }

  static void _applySessionToStateMachine(HeartbeatSessionInfo info) {
    final machine = BoardStateMachine();
    final current = machine.currentState;

    if (info.isActive && current == BoardState.idle) {
      Log.i('[Heartbeat] Active session exists — triggering PRE-FLIGHT');
      machine.transitionTo(BoardState.preFlight);
    } else if (info.isCompleted && current == BoardState.attendance) {
      Log.i('[Heartbeat] Session completed — transitioning to SUMMARY');
      machine.transitionTo(BoardState.summary);
    } else if (info.isEmpty && current == BoardState.attendance) {
      Log.w('[Heartbeat] Session null on server — force-ending');
      machine.forceTransitionTo(BoardState.summary);
    }
  }
}
