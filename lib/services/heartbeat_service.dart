import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/auth/token_manager.dart';
import '../core/config/app_config.dart';
import '../core/utils/logger.dart';
import '../core/state/board_state_machine.dart';
import '../data/repositories/device_repository.dart';
import '../models/remote_config.dart';
import 'api_service.dart';
import 'session_state_service.dart';
import 'remote_config_service.dart';
import 'time_sync_service.dart';
import 'update_checker.dart';

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
  static const int _maxNullSessionsBeforeForceEnd = 3;
  static bool _wsConnected = false;

  static int _heartbeatCount = 0;

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
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _send());
    Log.i('[Heartbeat] Started — immediate beat, then every 15 s (version: $_cachedVersion).');
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _consecutiveNullSessions = 0;
    Log.i('[Heartbeat] Stopped.');
  }

  static bool get wsConnected => _wsConnected;

  static void setWsConnected(bool connected) {
    _wsConnected = connected;
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

    // Proactive token refresh — keeps the ID token fresh within its 5 min
    // buffer window.  Every 3rd beat (~15 min) forces a network-level
    // rotation to actively correct NTP clock drift while the classroom is
    // idle.
    _heartbeatCount++;
    try {
      await TokenManager().getValidToken(
        forceRefresh: _heartbeatCount % 3 == 0,
      );
    } catch (e) {
      Log.w('[Heartbeat] Token refresh failed; will retry next beat: $e');
    }

    // §3 — When WebSocket is connected, skip the full HTTP heartbeat
    // but still fetch config periodically to receive update manifests.
    if (_wsConnected) {
      // Fetch config every ~60 seconds (4th beat cycle) to ensure
      // update manifests arrive even when WS is the primary channel.
      if (_heartbeatCount % 4 == 0) {
        try {
          final configData = await ApiService.getBoardConfig();
          if (configData != null && configData.isNotEmpty) {
            final config = RemoteConfig.fromJson(configData);
            final applied = await RemoteConfigService.applyConfig(config);
            if (applied) {
              Log.i('[Heartbeat] WS-connected config refresh: v${config.configVersion}');
              if (config.update != null) {
                unawaited(UpdateChecker.checkNow());
              }
            }
          }
        } catch (e) {
          Log.d('[Heartbeat] WS config fetch failed (non-critical): $e');
        }
      } else {
        Log.d('[Heartbeat] WS connected — skipping HTTP heartbeat');
      }
      return;
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
        if (machine.currentState == BoardState.active) {
          Log.w('[Heartbeat] $_consecutiveNullSessions consecutive null sessions — force-ending');
          machine.forceTransitionTo(BoardState.closed);
        }
      }

      // Parse remote config from heartbeat response.
      // The server includes a `config` block with feature flags, UI overrides,
      // and optionally a forced-update manifest. We apply it immediately so
      // feature flags take effect within 15 seconds.
      final configData = result['config'] as Map<String, dynamic>?;
      if (configData != null && configData.isNotEmpty) {
        // Fix relative download URL in force_update manifest
        final forceUpdate = configData['force_update'] as Map<String, dynamic>?;
        if (forceUpdate != null && forceUpdate['download_url']?.toString().startsWith('/') == true) {
          forceUpdate['download_url'] = '${AppConfig.baseUrl}${forceUpdate['download_url']}';
        }
        final config = RemoteConfig.fromJson(configData);
        final applied = await RemoteConfigService.applyConfig(config);
        if (applied) {
          Log.i('[Heartbeat] Applied remote config v${config.configVersion}');
          // If the new config carries an update manifest, check immediately.
          unawaited(UpdateChecker.checkNow());
        }
      }
    } catch (e) {
      if (e is ApiException &&
          (e.statusCode == 401 || e.statusCode == 404)) {
        Log.w('[Heartbeat] Server rejected heartbeat (${e.statusCode}) — operating in offline mode. Board remains registered locally.');
        return;
      }

      Log.w('[Heartbeat] Send failed (will retry in 15s): $e');
      return;
    }

    // After successful heartbeat, trigger a lightweight re-hydration check.
    // The HydrationService compares manifest_hash; if unchanged it returns
    // immediately without any Isar writes.
    try {
      final reg = await _deviceRepository?.getRegistration();
      if (reg != null) {
        await _deviceRepository?.hydrateFromServer();
      }
    } catch (e) {
      Log.d('[Heartbeat] Re-hydration check failed (non-critical): $e');
    }
  }

  static void _applySessionToStateMachine(HeartbeatSessionInfo info) {
    final machine = BoardStateMachine();
    final current = machine.currentState;

    // FIX: If SessionStateService already has an active session (from local
    // crash recovery or normal OTP flow), do NOT override the board state.
    // The board should stay on IdleScreen with the session arrow visible.
    final sessionState = SessionStateService().currentState;
    if (sessionState.isActive) {
      Log.d('[Heartbeat] SessionStateService has active session — skipping state override');
      return;
    }

    if (info.isActive && current == BoardState.idle) {
      Log.d('[Heartbeat] Active session exists on server — board stays idle');
    } else if (info.isActive && current == BoardState.active) {
      Log.d('[Heartbeat] Session active on server, board already active — no change');
    } else if (info.isCompleted && current == BoardState.active) {
      Log.i('[Heartbeat] Session completed — transitioning to CLOSED');
      machine.transitionTo(BoardState.closed);
    } else if (info.isEmpty && current == BoardState.active) {
      Log.w('[Heartbeat] Session null on server — force-ending');
      machine.forceTransitionTo(BoardState.closed);
    }
  }
}
