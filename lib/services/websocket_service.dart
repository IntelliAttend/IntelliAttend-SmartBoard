import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/platform/power_command_service.dart';
import '../core/utils/logger.dart';
import '../models/notification_event.dart';
import 'api_service.dart';
import 'heartbeat_service.dart';
import 'notification_listener_service.dart';
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
    this.markedBy = 'smartboard',
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
    this.markedBy = 'smartboard',
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
  final String studentName;
  final String seat;
  final String status;

  StudentVerifiedEvent({
    required this.studentId,
    this.studentName = '',
    required this.seat,
    this.status = 'PRESENT',
  });

  bool get isPresent => status.toUpperCase() == 'PRESENT';
  bool get isAbsent => status.toUpperCase() == 'ABSENT';

  factory StudentVerifiedEvent.fromJson(Map<String, dynamic> json) {
    return StudentVerifiedEvent(
      studentId: json['student_id'] as String,
      studentName: json['student_name'] as String? ?? '',
      seat: json['seat'] as String? ?? '',
      status: (json['status'] as String? ?? 'PRESENT').toUpperCase(),
    );
  }
}

class SystemCommandEvent {
  final String commandId;
  final String command;
  final int delaySeconds;
  final String reason;

  SystemCommandEvent({
    required this.commandId,
    required this.command,
    required this.delaySeconds,
    required this.reason,
  });

  factory SystemCommandEvent.fromJson(Map<String, dynamic> json) {
    return SystemCommandEvent(
      commandId: json['command_id'] as String? ?? '',
      command: json['command'] as String? ?? '',
      delaySeconds: json['delay_seconds'] as int? ?? 0,
      reason: json['reason'] as String? ?? '',
    );
  }
}

class ScheduleUpdateEvent {
  final String type;
  final String action;
  final String slotId;
  final String courseCode;
  final String sectionId;
  final String roomId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String facultyId;
  final String slotType;
  final DateTime timestamp;
  final String? overrideDate;
  final String? newFacultyId;

  ScheduleUpdateEvent({
    required this.type,
    required this.action,
    required this.slotId,
    required this.courseCode,
    required this.sectionId,
    required this.roomId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.facultyId,
    required this.slotType,
    required this.timestamp,
    this.overrideDate,
    this.newFacultyId,
  });

  factory ScheduleUpdateEvent.fromJson(Map<String, dynamic> json) {
    return ScheduleUpdateEvent(
      type: json['type'] as String? ?? '',
      action: json['action'] as String? ?? '',
      slotId: json['slot_id'] as String? ?? '',
      courseCode: json['course_code'] as String? ?? '',
      sectionId: json['section_id'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      dayOfWeek: json['day_of_week'] as int? ?? 1,
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
      facultyId: json['faculty_id'] as String? ?? '',
      slotType: json['slot_type'] as String? ?? 'regular',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      overrideDate: json['override_date'] as String?,
      newFacultyId: json['new_faculty_id'] as String?,
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

class AttendanceSubmittedEvent {
  final String sessionId;
  final int presentCount;
  final int absentCount;
  final DateTime timestamp;

  AttendanceSubmittedEvent({
    required this.sessionId,
    required this.presentCount,
    required this.absentCount,
    required this.timestamp,
  });

  factory AttendanceSubmittedEvent.fromJson(Map<String, dynamic> json) {
    return AttendanceSubmittedEvent(
      sessionId: json['session_id'] as String,
      presentCount: json['present_count'] as int? ?? 0,
      absentCount: json['absent_count'] as int? ?? 0,
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
  String? _boardId;
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
  final StreamController<AttendanceSubmittedEvent> _attendanceSubmittedController =
      StreamController<AttendanceSubmittedEvent>.broadcast();
  final StreamController<SystemCommandEvent> _systemCommandController =
      StreamController<SystemCommandEvent>.broadcast();

  final StreamController<Map<String, dynamic>> _boardStatusController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<NotificationEvent> _notificationEventController =
      StreamController<NotificationEvent>.broadcast();

  final StreamController<ScheduleUpdateEvent> _scheduleUpdateController =
      StreamController<ScheduleUpdateEvent>.broadcast();

  Stream<NotificationEvent> get onNotificationEvent =>
      _notificationEventController.stream;

  Stream<ScheduleUpdateEvent> get onScheduleUpdate =>
      _scheduleUpdateController.stream;

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
  Stream<AttendanceSubmittedEvent> get onAttendanceSubmitted =>
      _attendanceSubmittedController.stream;
  Stream<SystemCommandEvent> get onSystemCommand =>
      _systemCommandController.stream;
  Stream<Map<String, dynamic>> get onBoardStatus =>
      _boardStatusController.stream;
  String? get boardId => _boardId;
  bool get isConnected => _channel != null;

  final SessionStateService _sessionState = SessionStateService();

  /// Device repository for re-hydration after schedule updates.
  /// Must be set via [setDeviceRepository] before schedule updates can trigger re-hydration.
  dynamic _deviceRepository;

  WebsocketService(this._host);

  /// Set the device repository for re-hydration support.
  void setDeviceRepository(dynamic repository) {
    _deviceRepository = repository;
  }

  Future<void> connectSmartBoard(String boardId, [String? accessToken]) async {
    if (_disposed) return;
    _boardId = boardId;
    _sessionId = null;
    _reconnectAttempt = 0;
    await _doConnect();
  }

  Future<void> connectAttendance(String sessionId, [String? accessToken]) async {
    if (_disposed) return;
    _sessionId = sessionId;
    _reconnectAttempt = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed) return;

    try {
      String path;
      if (_sessionId != null) {
        path = '/api/v1/websocket/session/$_sessionId';
      } else if (_boardId != null) {
        path = '/api/v1/websocket/board/$_boardId';
      } else {
        Log.w('[WS] No board ID or session ID available');
        _scheduleReconnect();
        return;
      }

      final ticketData = await ApiService.getWebSocketTicket();
      if (ticketData == null) {
        Log.w('[WS] Failed to obtain WebSocket ticket, scheduling reconnect');
        _scheduleReconnect();
        return;
      }
      final ticket = ticketData['ticket'] as String?;
      if (ticket == null || ticket.isEmpty) {
        Log.w('[WS] Invalid ticket from server, scheduling reconnect');
        _scheduleReconnect();
        return;
      }

      final wsUrl = '$_host$path?ticket=$ticket';
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
      HeartbeatService.setWsConnected(true);

      // Re-acknowledge dismissed notifications on reconnect (§4.3)
      if (_reconnectAttempt > 0) {
        NotificationListenerService().reAcknowledgeDismissed();
      }
      _reconnectAttempt = 0;
      _startPingTimer();

      PowerCommandService().setWebsocketService(this);

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

      // Wait for the WebSocket connection to be established.
      // In web_socket_channel 3.x, connection errors only surface
      // through the .ready future (not the public stream, due to
      // allowForeignErrors: false).  If we don't await .ready, the
      // unhandled Future error propagates to runZonedGuarded and
      // triggers KioskService.forceRelease(), breaking fullscreen.
      try {
        await _channel!.ready;
      } catch (e) {
        Log.e('[WS] Connection ready error: $e');
        _cleanup();
        _scheduleReconnect();
        return;
      }
    } catch (e) {
      Log.e('[WS] Connection failed: $e');
      _cleanup();
      _scheduleReconnect();
    }
  }

  void send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (e) {
      Log.w('[WS] Send failed: $e');
    }
  }

  void submitAttendance({
    required String sessionId,
    required List<String> presentEmails,
    required List<String> absentEmails,
  }) {
    send({
      'type': 'attendance_submit',
      'session_id': sessionId,
      'present_emails': presentEmails,
      'absent_emails': absentEmails,
    });
    Log.i('[WS] attendance_submit sent: ${presentEmails.length} present, ${absentEmails.length} absent');
  }

  void saveDraft({
    required String sessionId,
    required List<String> presentEmails,
    required List<String> absentEmails,
  }) {
    send({
      'type': 'attendance_save_draft',
      'session_id': sessionId,
      'present_emails': presentEmails,
      'absent_emails': absentEmails,
    });
    Log.i('[WS] attendance_save_draft sent: ${presentEmails.length} present, ${absentEmails.length} absent');
  }

  void sendTap({
    required String sessionId,
    required String studentId,
    required String status,
    required String boardId,
  }) {
    send({
      'type': 'attendance_tap',
      'session_id': sessionId,
      'student_id': studentId,
      'status': status,
      'board_id': boardId,
    });
    Log.i('[WS] attendance_tap sent: $studentId = $status');
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

      // Check for notification events (contract v1 format)
      final eventType = message['event_type'] as String?;
      if (eventType == 'notification') {
        _handleNotificationEvent(message);
        return;
      }

      final type = message['type'] as String?;

      if (type == 'pong' || type == 'heartbeat') return;

      if (type == 'board_connected') {
        _handleBoardConnected(message);
        return;
      }

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

        case 'board_status':
          Log.i('[WS] board_status: ${message['status']} board=${message['board_id']}');
          _boardStatusController.add(message);
          break;

        case 'attendance_submitted':
        case 'attendance_submit_ack':
          final event = AttendanceSubmittedEvent.fromJson(message);
          _attendanceSubmittedController.add(event);
          Log.i('[WS] $type: ${event.presentCount} present ${event.absentCount} absent');
          break;

        case 'attendance_submit_error':
          Log.e('[WS] attendance_submit_error: ${message['error']}');
          break;

        case 'attendance_tap_ack':
          Log.i('[WS] attendance_tap_ack: ${message['student_id']} success=${message['success']} status=${message['status']}');
          break;

        case 'attendance_save_draft_ack':
          Log.i('[WS] attendance_save_draft_ack: success=${message['success']}');
          break;

        case 'student_verified':
          final event = StudentVerifiedEvent.fromJson(message);
          _sessionState.notifyStudentVerified(event.seat);
          _studentVerifiedController.add(event);
          Log.i('[WS] student_verified: ${event.studentId} seat=${event.seat} status=${event.status}');
          break;

        case 'attendance_closed':
          Log.i('[WS] attendance_closed');
          _sessionState.applyState(SessionState(
            sessionId: _sessionState.currentState.sessionId,
            state: 'CLOSED',
            presentCount: message['present'] as int? ?? _sessionState.currentState.presentCount,
          ));
          break;

        case 'system_command':
          final event = SystemCommandEvent.fromJson(message);
          Log.w('[WS] system_command: ${event.command} id=${event.commandId} delay=${event.delaySeconds}s reason=${event.reason}');
          _systemCommandController.add(event);
          PowerCommandService().handleSystemCommand(event);
          break;

        case 'SCHEDULE_UPDATED':
        case 'FACULTY_REASSIGNED':
          _handleScheduleUpdate(message);
          break;

        default:
          Log.d('[WS] Unknown message type: $type');
      }
    } catch (e) {
      Log.w('[WS] Failed to parse message: $e $rawMessage');
    }
  }

  void _handleNotificationEvent(Map<String, dynamic> message) {
    try {
      final event = NotificationEvent.fromJson(message);
      Log.i('[WS] Notification event: ${event.payload.displayMode} '
          'id=${event.payload.notificationId} title=${event.payload.title}');

      // Route through the notification listener service
      NotificationListenerService().handleNotificationEvent(event);
      _notificationEventController.add(event);
    } catch (e) {
      Log.w('[WS] Failed to parse notification event: $e');
    }
  }

  void _handleScheduleUpdate(Map<String, dynamic> message) {
    try {
      final event = ScheduleUpdateEvent.fromJson(message);
      Log.i('[WS] Schedule update: ${event.type} action=${event.action} '
          'slot=${event.slotId} faculty=${event.facultyId} '
          '${event.newFacultyId != null ? "new_faculty=${event.newFacultyId}" : ""}');

      _scheduleUpdateController.add(event);

      // Trigger re-hydration to fetch updated timetable from server
      _triggerReHydration();
    } catch (e) {
      Log.w('[WS] Failed to parse schedule update: $e');
    }
  }

  void _triggerReHydration() {
    // Use Future.microtask to avoid blocking the WebSocket message handler
    Future.microtask(() async {
      try {
        // Import is done at the top of the file via device_repository
        // We need to access the Isar instance to re-hydrate
        // The DeviceRepository will be injected via the setDeviceRepository method
        if (_deviceRepository != null) {
          await _deviceRepository!.hydrateFromServer();
          Log.i('[WS] Re-hydration triggered after schedule update');
        } else {
          Log.w('[WS] DeviceRepository not set, cannot re-hydrate');
        }
      } catch (e) {
        Log.e('[WS] Re-hydration failed: $e');
      }
    });
  }

  void _handleBoardConnected(Map<String, dynamic> message) {
    final boardId = message['board_id'] as String? ?? '';
    Log.i('[WS] board_connected: $boardId — discovering active session');

    // §4 — Check for an active session and auto-join via WebSocket.
    ApiService.getActiveSession().then((session) {
      if (session['active'] == true) {
        final sid = session['session_id'] as String?;
        if (sid != null && sid.isNotEmpty) {
          Log.i('[WS] Active session found: $sid — sending join_session');
          send({'type': 'join_session', 'session_id': sid});
        }
      } else {
        Log.d('[WS] No active session on connect');
      }
    });
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

    // Cap at 60 reconnect attempts (~10 minutes), then give up.
    if (_reconnectAttempt > 60) {
      Log.e('[WS] Reconnect limit exhausted after $_reconnectAttempt attempts — giving up.');
      return;
    }

    // Exponential backoff: 1s, 2s, 4s, 8s, 15s, 15s, 30s, 30s, 60s cap
    Duration delay;
    if (_reconnectAttempt <= 4) {
      delay = Duration(seconds: 1 << (_reconnectAttempt - 1));
    } else if (_reconnectAttempt == 5) {
      delay = const Duration(seconds: 15);
    } else if (_reconnectAttempt <= 7) {
      delay = const Duration(seconds: 30);
    } else {
      delay = const Duration(seconds: 60);
    }

    // Add jitter (±25%) to prevent thundering herd
    final jitter = (delay.inMilliseconds * 0.25).toInt();
    final jitteredMs = delay.inMilliseconds + (jitter > 0 ? (DateTime.now().millisecondsSinceEpoch % (jitter * 2) - jitter) : 0);
    delay = Duration(milliseconds: jitteredMs.clamp(1000, 120000));

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
    HeartbeatService.setWsConnected(false);
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
    _attendanceSubmittedController.close();
    _systemCommandController.close();
    _boardStatusController.close();
    _notificationEventController.close();
    _scheduleUpdateController.close();
  }
}
