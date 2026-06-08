import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/utils/logger.dart';
import '../core/security/firebase_rest_auth.dart';
import 'time_sync_service.dart';

class PresentStudent {
  final String studentId;
  final String studentName;
  final String status;
  final DateTime recordedAt;

  PresentStudent({
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.recordedAt,
  });

  factory PresentStudent.fromJson(Map<String, dynamic> json) {
    return PresentStudent(
      studentId: json['student_id'] as String,
      studentName: json['student_name'] as String? ?? '',
      status: json['status'] as String? ?? 'PRESENT',
      recordedAt: json['recorded_at'] != null
          ? DateTime.parse(json['recorded_at'] as String)
          : TimeSyncService.timeNow,
    );
  }
}

class AttendanceMarkedEvent {
  final String studentId;
  final String studentName;
  final String status;
  final int trustScore;
  final DateTime recordedAt;

  AttendanceMarkedEvent({
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.trustScore,
    required this.recordedAt,
  });

  factory AttendanceMarkedEvent.fromJson(Map<String, dynamic> json) {
    return AttendanceMarkedEvent(
      studentId: json['student_id'] as String,
      studentName: json['studentName'] as String? ?? '',
      status: json['status'] as String? ?? 'PRESENT',
      trustScore: json['trust_score'] as int? ?? 0,
      recordedAt: json['recorded_at'] != null
          ? DateTime.parse(json['recorded_at'] as String)
          : TimeSyncService.timeNow,
    );
  }
}

class SessionEndedEvent {
  final String sessionId;
  final String status;
  final DateTime timestamp;

  SessionEndedEvent({
    required this.sessionId,
    required this.status,
    required this.timestamp,
  });

  factory SessionEndedEvent.fromJson(Map<String, dynamic> json) {
    return SessionEndedEvent(
      sessionId: json['session_id'] as String,
      status: json['status'] as String? ?? 'ended',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : TimeSyncService.timeNow,
    );
  }
}

class WebsocketService {
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration pingInterval = Duration(seconds: 30);

  final String _host;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  String? _sessionId;
  StreamSubscription? _messageSubscription;

  bool _isWaitingForFullSync = false;
  final List<AttendanceMarkedEvent> _pendingAttendanceEvents = [];

  final StreamController<List<PresentStudent>> _syncController =
      StreamController<List<PresentStudent>>.broadcast();
  final StreamController<AttendanceMarkedEvent> _attendanceController =
      StreamController<AttendanceMarkedEvent>.broadcast();
  final StreamController<SessionEndedEvent> _sessionEndedController =
      StreamController<SessionEndedEvent>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  Stream<List<PresentStudent>> get onFullStateSync => _syncController.stream;
  Stream<AttendanceMarkedEvent> get onAttendanceMarked =>
      _attendanceController.stream;
  Stream<SessionEndedEvent> get onSessionEnded =>
      _sessionEndedController.stream;
  Stream<bool> get onConnectionState => _connectionStateController.stream;
  bool get isConnected => _channel != null;

  WebsocketService(this._host);

  Future<String?> _obtainTicket() async {
    final idToken = await FirebaseRestAuth.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      Log.e('[WS] No Firebase ID token available for ticket request');
      return null;
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };

    try {
      final response = await http.post(
        Uri.parse('$_host/api/v1/websocket/ticket'),
        headers: headers,
      );

      if (response.statusCode == 401) {
        final freshToken = await FirebaseRestAuth.getIdToken(forceRefresh: true);
        if (freshToken != null) {
          headers['Authorization'] = 'Bearer $freshToken';
          final retryResponse = await http.post(
            Uri.parse('$_host/api/v1/websocket/ticket'),
            headers: headers,
          );
          if (retryResponse.statusCode == 200) {
            final data = jsonDecode(retryResponse.body);
            return data['ticket'] as String?;
          }
        }
        Log.e('[WS] Ticket acquisition failed with 401 after refresh');
        return null;
      }

      if (response.statusCode != 200) {
        Log.e('[WS] Ticket acquisition failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      return data['ticket'] as String?;
    } catch (e) {
      Log.e('[WS] Ticket request failed: $e');
      return null;
    }
  }

  Future<void> connect(String sessionId) async {
    if (_disposed) return;
    // Idempotent: skip if already connecting to the same session
    if (_sessionId == sessionId && _channel != null) return;
    _sessionId = sessionId;
    _reconnectAttempt = 0;

    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed || _sessionId == null) return;

    final ticket = await _obtainTicket();
    if (ticket == null) {
      Log.w('[WS] No ticket obtained — scheduling reconnect');
      _scheduleReconnect();
      return;
    }

    try {
      final wsUrl = '$_host/api/v1/websocket/session/$_sessionId?ticket=$ticket';
      final wsUri = Uri.parse(wsUrl)
          .replace(scheme: wsUrl.startsWith('https') ? 'wss' : 'ws');

      _channel = WebSocketChannel.connect(wsUri);
      Timer? connectTimer;
      connectTimer = Timer(connectTimeout, () {
        if (_channel != null && !_disposed) {
          Log.e('[WS] Connection timed out after ${connectTimeout.inSeconds}s');
          _cleanup();
          _scheduleReconnect();
        }
      });

      _isWaitingForFullSync = true;
      _connectionStateController.add(true);
      _reconnectAttempt = 0;
      _startPingTimer();

      _messageSubscription = _channel!.stream.listen(
        (msg) {
          connectTimer?.cancel();
          _handleMessage(msg);
        },
        onError: (error) {
          connectTimer?.cancel();
          Log.w('[WS] Connection error: $error');
          _cleanup();
          _scheduleReconnect();
        },
        onDone: () {
          connectTimer?.cancel();
          Log.w('[WS] Connection closed');
          _cleanup();
          if (!_disposed) _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      Log.e('[WS] Connection failed: $e');
      _cleanup();
      _scheduleReconnect();
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      try {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (e) {
        Log.d('[WS] Ping send failed: $e');
      }
    });
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final Map<String, dynamic> message = jsonDecode(rawMessage as String);
      final type = message['type'] as String?;

      if (type == 'pong') return;

      switch (type) {
        case 'full_state_sync':
          final students = (message['present_students'] as List<dynamic>?)
                  ?.map((e) =>
                      PresentStudent.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [];
          _syncController.add(students);
          if (_isWaitingForFullSync) {
            _isWaitingForFullSync = false;
            for (final pending in _pendingAttendanceEvents) {
              _attendanceController.add(pending);
            }
            _pendingAttendanceEvents.clear();
          }
          Log.i('[WS] full_state_sync: ${students.length} present');
          break;

        case 'ATTENDANCE_MARKED':
          final event = AttendanceMarkedEvent.fromJson(message);
          if (_isWaitingForFullSync) {
            _pendingAttendanceEvents.add(event);
          } else {
            _attendanceController.add(event);
          }
          Log.i('[WS] ATTENDANCE_MARKED: ${event.studentId}');
          break;

        case 'session_ended':
          final event = SessionEndedEvent.fromJson(message);
          _sessionEndedController.add(event);
          Log.i('[WS] session_ended: ${event.sessionId} status=${event.status}');
          break;

        default:
          Log.d('[WS] Unknown message type: $type');
      }
    } catch (e) {
      Log.w('[WS] Failed to parse message: $e — $rawMessage');
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _sessionId == null) return;

    _reconnectTimer?.cancel();
    _reconnectAttempt++;

    final delay = _reconnectAttempt <= 4
        ? Duration(seconds: 1 << (_reconnectAttempt - 1))
        : const Duration(seconds: 15);

    Log.i('[WS] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempt)');
    _reconnectTimer = Timer(delay, () => _doConnect());
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _isWaitingForFullSync = false;
    _pendingAttendanceEvents.clear();
    _connectionStateController.add(false);
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanup();
  }

  void dispose() {
    _pingTimer?.cancel();
    disconnect();
    _syncController.close();
    _attendanceController.close();
    _sessionEndedController.close();
    _connectionStateController.close();
  }
}
