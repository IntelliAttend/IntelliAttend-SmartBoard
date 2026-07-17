import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/websocket_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../utils/logger.dart';
import 'kiosk_service.dart';

enum PowerCommandStatus { none, pendingShutdown, executing, cancelled }

class PowerCommandState {
  final PowerCommandStatus status;
  final int secondsRemaining;
  final int totalSeconds;
  final String? reason;
  final String? commandId;
  final String commandType;

  const PowerCommandState({
    this.status = PowerCommandStatus.none,
    this.secondsRemaining = 0,
    this.totalSeconds = 0,
    this.reason,
    this.commandId,
    this.commandType = 'shutdown',
  });
}

class PowerCommandService {
  static const String _pendingKey = 'pending_power_command';

  static final PowerCommandService _instance = PowerCommandService._internal();
  factory PowerCommandService() => _instance;
  PowerCommandService._internal();

  WebsocketService? _wsService;

  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  String? _currentCommandId;
  String? _reason;
  String _currentCommand = 'shutdown';

  final StreamController<PowerCommandState> _stateController =
      StreamController<PowerCommandState>.broadcast();

  Stream<PowerCommandState> get onStateChanged => _stateController.stream;
  int _totalDelaySeconds = 0;

  PowerCommandState get currentState => PowerCommandState(
    status: _currentCommandId != null
        ? PowerCommandStatus.pendingShutdown
        : PowerCommandStatus.none,
    secondsRemaining: _secondsRemaining,
    totalSeconds: _totalDelaySeconds,
    reason: _reason,
    commandId: _currentCommandId,
    commandType: _currentCommand,
  );

  void setWebsocketService(WebsocketService? ws) {
    _wsService = ws;
  }

  Future<void> init() async {
    final pending = await _loadPendingCommand();
    if (pending != null) {
      Log.w('[PowerCmd] Clearing stale pending command from previous session');
      await _clearPendingCommand();
      return;
    }
  }

  void handleSystemCommand(SystemCommandEvent event) {
    if (event.command == 'cancel_shutdown') {
      _cancelShutdown(event.commandId);
      return;
    }

    if (_currentCommandId != null && event.commandId == _currentCommandId) {
      Log.i('[PowerCmd] Duplicate command ignored: ${event.commandId}');
      return;
    }

    if (event.command == 'shutdown' || event.command == 'restart') {
      _currentCommand = event.command;
      _currentCommandId = event.commandId;
      _reason = event.reason;
      _secondsRemaining = event.delaySeconds.clamp(5, 600);
      _totalDelaySeconds = _secondsRemaining;
      _emitState();

      _ensureFullscreen();
      _startCountdown();
      _persistCommand(0);

      _sendAck('received');
      Log.w('[PowerCmd] ${event.command.toUpperCase()} initiated — ${_secondsRemaining}s countdown');
    } else {
      Log.w('[PowerCmd] Unknown command: ${event.command}');
    }
  }

  void cancelFromLocal() {
    if (_currentCommandId == null) return;
    _cancelShutdown(_currentCommandId);
    _sendAck('cancelled_local');
    Log.i('[PowerCmd] Shutdown cancelled by local user');
  }

  void _cancelShutdown(String? commandId) {
    if (_currentCommandId == null || (commandId != null && _currentCommandId != commandId)) {
      return;
    }

    _countdownTimer?.cancel();
    _countdownTimer = null;
    _currentCommandId = null;
    _reason = null;
    _secondsRemaining = 0;
    _emitState();

    _clearPendingCommand();

    if (Platform.isWindows) {
      try {
        Process.run('shutdown', ['/a']);
        Log.i('[PowerCmd] Windows shutdown aborted via shutdown /a');
      } catch (e) {
        Log.w('[PowerCmd] Failed to abort Windows shutdown: $e');
      }
    }

    _sendAck('cancelled');
    Log.i('[PowerCmd] Shutdown cancelled for command $commandId');
  }

  void _ensureFullscreen() {
    if (!kIsWeb) {
      unawaited(KioskService.setMode(KioskMode.fullscreen));
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsRemaining--;
      _emitState();

      if (_secondsRemaining <= 0) {
        timer.cancel();
        _countdownTimer = null;
        _executeShutdown();
      }
    });
  }

  Future<void> _executeShutdown() async {
    final cmd = _currentCommand;
    _currentCommandId = null;
    _reason = null;
    _secondsRemaining = 0;
    _emitState();

    _sendAck('executed');
    _clearPendingCommand();

    Log.w('[PowerCmd] Executing $cmd NOW');
    try {
      if (Platform.isWindows) {
        final args = cmd == 'restart' ? ['/r', '/t', '0'] : ['/s', '/t', '0'];
        await Process.run('shutdown', args);
      } else if (Platform.isLinux) {
        final args = cmd == 'restart' ? ['-r', 'now'] : ['-h', 'now'];
        await Process.run('shutdown', args);
      } else if (Platform.isMacOS) {
        final args = cmd == 'restart' ? ['restart', 'now'] : ['shutdown', '-h', 'now'];
        await Process.run('sudo', ['shutdown', ...args]);
      }
    } catch (e) {
      Log.e('[PowerCmd] Shutdown command failed: $e');
    }
  }

  void _sendAck(String status) {
    if (_wsService == null) return;
    _wsService!.send({
      'type': 'system_command_ack',
      'command_id': _currentCommandId ?? '',
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _emitState() {
    _stateController.add(PowerCommandState(
      status: _currentCommandId != null
          ? PowerCommandStatus.pendingShutdown
          : PowerCommandStatus.none,
      secondsRemaining: _secondsRemaining,
      totalSeconds: _totalDelaySeconds,
      reason: _reason,
      commandId: _currentCommandId,
      commandType: _currentCommand,
    ));
  }

  Future<void> _persistCommand(int elapsedSeconds) async {
    try {
      final data = jsonEncode({
        'command': _currentCommand,
        'command_id': _currentCommandId,
        'reason': _reason,
        'delay_seconds': _secondsRemaining + elapsedSeconds,
        'elapsed': elapsedSeconds,
        'issued_at': DateTime.now().toIso8601String(),
      });
      await SecureStorageService.write(_pendingKey, data);
    } catch (e) {
      Log.w('[PowerCmd] Failed to persist pending command: $e');
    }
  }

  Future<Map<String, dynamic>?> _loadPendingCommand() async {
    try {
      final raw = await SecureStorageService.read(_pendingKey);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      data['issued_at'] = DateTime.parse(data['issued_at'] as String);
      return data;
    } catch (e) {
      Log.w('[PowerCmd] Failed to load pending command: $e');
      return null;
    }
  }

  Future<void> _clearPendingCommand() async {
    try {
      await SecureStorageService.delete(_pendingKey);
    } catch (e) {
      Log.w('[PowerCmd] Failed to clear pending command: $e');
    }
  }

  void dispose() {
    _countdownTimer?.cancel();
    _stateController.close();
  }
}
