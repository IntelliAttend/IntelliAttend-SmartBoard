import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/utils/logger.dart';
import 'session_state_service.dart';
import 'time_sync_service.dart';

class PresentStudent {
  final String studentId;
  final String? studentEmail;
  final String studentName;
  final String status;
  final int trustScore;
  final String markedBy;
  final DateTime recordedAt;

  PresentStudent({
    required this.studentId,
    this.studentEmail,
    required this.studentName,
    required this.status,
    this.trustScore = 100,
    this.markedBy = 'qr_scan',
    required this.recordedAt,
  });

  factory PresentStudent.fromJson(Map<String, dynamic> json) {
    return PresentStudent(
      studentId: json['student_id'] as String,
      studentEmail: json['student_email'] as String?,
      studentName: json['student_name'] as String? ?? '',
      status: json['status'] as String? ?? 'PRESENT',
      trustScore: json['trust_score'] as int? ?? 100,
      markedBy: json['marked_by']?.toString() ?? 'qr_scan',
      recordedAt: json['recorded_at'] != null
          ? DateTime.parse(json['recorded_at'] as String)
          : TimeSyncService.timeNow,
    );
  }
}

class AttendanceMarkedEvent {
  final String studentId;
  final String? studentEmail;
  final String studentName;
  final String markedBy;
  final String status;
  final int trustScore;
  final DateTime recordedAt;

  AttendanceMarkedEvent({
    required this.studentId,
    this.studentEmail,
    required this.studentName,
    this.markedBy = 'qr_scan',
    required this.status,
    required this.trustScore,
    required this.recordedAt,
  });

  factory AttendanceMarkedEvent.fromJson(Map<String, dynamic> json) {
    return AttendanceMarkedEvent(
      studentId: json['student_id'] as String,
      studentEmail: json['student_email'] as String?,
      studentName: json['student_name'] as String? ?? '',
      markedBy: json['marked_by'] as String? ?? 'qr_scan',
      status: json['status'] as String? ?? 'PRESENT',
      trustScore: json['trust_score'] as int? ?? 0,
      recordedAt: json['recorded_at'] != null
          ? DateTime.parse(json['recorded_at'] as String)
          : TimeSyncService.timeNow,
    );
  }
}

class FullStateSync {
  final String sessionId;
  final int totalPresent;
  final int totalStudents;
  final List<PresentStudent> presentStudents;

  FullStateSync({
    required this.sessionId,
    required this.totalPresent,
    required this.totalStudents,
    required this.presentStudents,
  });
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

class StudentVerifiedEvent {
  final String studentId;
  final String seat;

  StudentVerifiedEvent({
    required this.studentId,
    required this.seat,
  });

  factory StudentVerifiedEvent.fromJson(Map<String, dynamic> json) {
    return StudentVerifiedEvent(
      studentId: json['student_id'] as String,
      seat: json['seat'] as String? ?? '',
    );
  }
}

class AttendanceUpdatedEvent {
  final int present;
  final int absent;

  AttendanceUpdatedEvent({required this.present, required this.absent});

  factory AttendanceUpdatedEvent.fromJson(Map<String, dynamic> json) {
    return AttendanceUpdatedEvent(
      present: json['present'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
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
  String? _boardId;
  String? _accessToken;
  StreamSubscription? _messageSubscription;

  bool _isWaitingForFullSync = false;
  final List<AttendanceMarkedEvent> _pendingAttendanceEvents = [];

  final StreamController<FullStateSync> _syncController =
      StreamController<FullStateSync>.broadcast();
  final StreamController<AttendanceMarkedEvent> _attendanceController =
      StreamController<AttendanceMarkedEvent>.broadcast();
  final StreamController<SessionEndedEvent> _sessionEndedController =
      StreamController<SessionEndedEvent>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<StudentVerifiedEvent> _studentVerifiedController =
      StreamController<StudentVerifiedEvent>.broadcast();
  final StreamController<AttendanceUpdatedEvent> _attendanceUpdatedController =
      StreamController<AttendanceUpdatedEvent>.broadcast();

  Stream<FullStateSync> get onFullStateSync => _syncController.stream;
  Stream<AttendanceMarkedEvent> get onAttendanceMarked =>
      _attendanceController.stream;
  Stream<SessionEndedEvent> get onSessionEnded =>
      _sessionEndedController.stream;
  Stream<bool> get onConnectionState => _connectionStateController.stream;
  Stream<StudentVerifiedEvent> get onStudentVerified =>
      _studentVerifiedController.stream;
  Stream<AttendanceUpdatedEvent> get onAttendanceUpdated =>
      _attendanceUpdatedController.stream;
  bool get isConnected => _channel != null;

  final SessionStateService _sessionState = SessionStateService();

  WebsocketService(this._host);

  Future<void> connectSmartBoard(String boardId, String accessToken) async {
    if (_disposed) return;
    _accessToken = accessToken;
    _boardId = boardId;
    _sessionId = null;
    _reconnectAttempt = 0;
    await _doConnect();
  }

  Future<void> connectAttendance(String sessionId, String accessToken) async {
    if (_disposed) return;
    _accessToken = accessToken;
    _sessionId = sessionId;
    _reconnectAttempt = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed) return;

    final token = _accessToken;
    if (token == null || token.isEmpty) {
      Log.w('[WS] No access token available scheduling reconnect');
      _scheduleReconnect();
      return;
    }

    try {
      String queryParams;
      if (_sessionId != null) {
        queryParams = 'session_id=$_sessionId';
      } else if (_boardId != null) {
        queryParams = 'board_id=$_boardId';
      } else {
        Log.w('[WS] No board ID or session ID available');
        _scheduleReconnect();
        return;
      }
      final wsUrl = '$_host/ws?$queryParams&token=$token';
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
      _sessionState.setConnected(true);
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

      if (type == 'pong' || type == 'heartbeat') return;

      switch (type) {
        case 'full_state_sync':
          _handleFullStateSync(message);
          break;
        case 'ATTENDANCE_MARKED':
          _handleAttendanceMarked(message);
          break;
        case 'session_ended':
          _handleSessionEnded(message);
          break;
        case 'session_activated':
          Log.i('[WS] session_activated: ${message['session_id']} status=${message['status']}');
          break;

        case 'session_preparing':
          Log.i('[WS] session_preparing: ${message['session_id']}');
          _sessionState.applyState(SessionState(
            sessionId: message['session_id'] as String,
            state: 'PREPARING',
            courseName: message['course_name'] as String?,
            facultyName: message['faculty_name'] as String?,
            sectionId: message['section_id'] as String?,
            startTime: message['start_time'] as String?,
          ));
          break;

        case 'session_igniting':
          Log.i('[WS] session_igniting: ${message['session_id']}');
          _sessionState.applyState(SessionState(
            sessionId: message['session_id'] as String,
            state: 'IGNITING',
            courseName: message['course_name'] as String?,
            facultyName: message['faculty_name'] as String?,
          ));
          break;

        case 'attendance_open':
          Log.i('[WS] attendance_open: ${message['session_id']}');
          _sessionState.applyState(SessionState(
            sessionId: message['session_id'] as String,
            state: 'ACTIVE',
            version: message['version'] as int? ?? 0,
            sessionSecretHalf1: message['session_secret_half1'] as String?,
            websocketToken: message['websocket_token'] as String?,
          ));
          break;

        case 'attendance_updated':
          final event = AttendanceUpdatedEvent.fromJson(message);
          _sessionState.updateCounts(event.present, event.absent);
          _attendanceUpdatedController.add(event);
          Log.i('[WS] attendance_updated: ${event.present} present ${event.absent} absent');
          break;

        case 'student_verified':
          final event = StudentVerifiedEvent.fromJson(message);
          _sessionState.notifyStudentVerified(event.seat);
          _studentVerifiedController.add(event);
          Log.i('[WS] student_verified: ${event.studentId} seat=${event.seat}');
          break;

        case 'attendance_closed':
          Log.i('[WS] attendance_closed');
          _sessionState.applyState(SessionState(
            sessionId: _sessionState.currentState.sessionId,
            state: 'CLOSED',
            presentCount: message['present'] as int? ?? _sessionState.currentState.presentCount,
          ));
          break;

        default:
          Log.d('[WS] Unknown message type: $type');
      }
    } catch (e) {
      Log.w('[WS] Failed to parse message: $e $rawMessage');
    }
  }

  void _handleFullStateSync(Map<String, dynamic> message) {
    final roster = message['roster'] as List<dynamic>?;
    final presentList = message['present_students'] as List<dynamic>?;
    final sourceList = roster ?? presentList ?? [];
    final students = sourceList
        .map((e) => PresentStudent.fromJson(e as Map<String, dynamic>))
        .toList();
    final presentCount = students.where((s) => s.status.toUpperCase() == 'PRESENT').length;
    final totalStudents = message['total_students'] as int? ?? students.length;
    final totalPresent = message['total_present'] as int? ?? presentCount;
    final sessionId = message['session_id'] as String? ?? _sessionId ?? '';
    _syncController.add(FullStateSync(
      sessionId: sessionId,
      totalPresent: totalPresent,
      totalStudents: totalStudents,
      presentStudents: students,
    ));
    if (_isWaitingForFullSync) {
      _isWaitingForFullSync = false;
      for (final pending in _pendingAttendanceEvents) {
        _attendanceController.add(pending);
      }
      _pendingAttendanceEvents.clear();
    }
    Log.i('[WS] full_state_sync: $totalPresent present / $totalStudents total');
  }

  void _handleAttendanceMarked(Map<String, dynamic> message) {
    final event = AttendanceMarkedEvent.fromJson(message);
    if (_isWaitingForFullSync) {
      _pendingAttendanceEvents.add(event);
    } else {
      _attendanceController.add(event);
    }
    Log.i('[WS] ATTENDANCE_MARKED: ${event.studentId}');
  }

  void _handleSessionEnded(Map<String, dynamic> message) {
    final event = SessionEndedEvent.fromJson(message);
    _sessionEndedController.add(event);
    _sessionState.applyState(SessionState(
      sessionId: event.sessionId,
      state: 'CLOSED',
    ));
    Log.i('[WS] session_ended: ${event.sessionId} status=${event.status}');
  }

  void _scheduleReconnect() {
    if (_disposed || (_boardId == null && _sessionId == null)) return;

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
    _sessionState.setConnected(false);
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
    _studentVerifiedController.close();
    _attendanceUpdatedController.close();
  }
}
