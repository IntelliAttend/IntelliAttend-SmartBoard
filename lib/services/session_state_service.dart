import 'dart:async';
import '../core/utils/logger.dart';
import '../core/state/board_state_machine.dart';

class SessionState {
  final String sessionId;
  final String state;
  final int version;
  final int presentCount;
  final int absentCount;
  final int totalStudents;
  final String? courseName;
  final String? facultyName;
  final String? sectionId;
  final String? courseCode;
  final String? roomName;
  final String? startTime;
  final String? websocketToken;

  SessionState({
    required this.sessionId,
    required this.state,
    this.version = 0,
    this.presentCount = 0,
    this.absentCount = 0,
    this.totalStudents = 0,
    this.courseName,
    this.facultyName,
    this.sectionId,
    this.courseCode,
    this.roomName,
    this.startTime,
    this.websocketToken,
  });

  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      sessionId: json['session_id'] as String? ?? '',
      state: json['state'] as String? ?? 'IDLE',
      version: json['version'] as int? ?? 0,
      presentCount: json['present'] as int? ?? json['present_count'] as int? ?? 0,
      absentCount: json['absent'] as int? ?? json['absent_count'] as int? ?? 0,
      totalStudents: json['total_students'] as int? ?? json['total'] as int? ?? 0,
      courseName: json['course_name'] as String?,
      facultyName: json['faculty_name'] as String?,
      sectionId: json['section_id'] as String?,
      courseCode: json['course_code'] as String?,
      roomName: json['room_name'] as String?,
      startTime: json['start_time'] as String?,
      websocketToken: json['websocket_token'] as String?,
    );
  }

  SessionState copyWith({
    String? sessionId,
    String? state,
    int? version,
    int? presentCount,
    int? absentCount,
    int? totalStudents,
    String? courseName,
    String? facultyName,
    String? sectionId,
    String? courseCode,
    String? roomName,
    String? startTime,
    String? websocketToken,
  }) {
    return SessionState(
      sessionId: sessionId ?? this.sessionId,
      state: state ?? this.state,
      version: version ?? this.version,
      presentCount: presentCount ?? this.presentCount,
      absentCount: absentCount ?? this.absentCount,
      totalStudents: totalStudents ?? this.totalStudents,
      courseName: courseName ?? this.courseName,
      facultyName: facultyName ?? this.facultyName,
      sectionId: sectionId ?? this.sectionId,
      courseCode: courseCode ?? this.courseCode,
      roomName: roomName ?? this.roomName,
      startTime: startTime ?? this.startTime,
      websocketToken: websocketToken ?? this.websocketToken,
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'state': state,
    'version': version,
    'present': presentCount,
    'absent': absentCount,
    'total_students': totalStudents,
    if (courseName != null) 'course_name': courseName,
    if (facultyName != null) 'faculty_name': facultyName,
    if (sectionId != null) 'section_id': sectionId,
    if (courseCode != null) 'course_code': courseCode,
    if (roomName != null) 'room_name': roomName,
    if (startTime != null) 'start_time': startTime,
  };

  bool get isEmpty => sessionId.isEmpty;
  bool get isPreparing => state == 'PREPARING';
  bool get isIgniting => state == 'IGNITING';
  bool get isActive => state == 'ACTIVE';
  bool get isClosed => state == 'CLOSED';
  bool get isIdle => state == 'IDLE' || state.isEmpty;
}

class SessionStateService {
  SessionStateService._();

  static final SessionStateService _instance = SessionStateService._();
  factory SessionStateService() => _instance;

  SessionState _sessionState = SessionState(sessionId: '', state: 'IDLE');
  String? _sessionSecret;
  String? _websocketAccessToken;

  final StreamController<SessionState> _stateController =
      StreamController<SessionState>.broadcast();

  final StreamController<String> _studentVerifiedController =
      StreamController<String>.broadcast();

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  Stream<SessionState> get onStateChanged => _stateController.stream;
  Stream<String> get onStudentVerified => _studentVerifiedController.stream;
  Stream<bool> get onConnectionState => _connectionStateController.stream;

  SessionState get currentState => _sessionState;
  String? get sessionSecret => _sessionSecret;
  String? get websocketAccessToken => _websocketAccessToken;

  void storeSessionSecrets(String secret, String? wsToken) {
    _sessionSecret = secret;
    _websocketAccessToken = wsToken;
  }

  void applyState(SessionState newState) {
    if (!_shouldApply(newState)) return;

    _sessionState = newState;
    _syncBoardStateMachine(newState.state);
    _stateController.add(newState);
    Log.i('[SessionState] Applied: ${newState.state} sid=${newState.sessionId} v=${newState.version}');
  }

  void applyFromRecovery(Map<String, dynamic> json) {
    final serverState = SessionState.fromJson(json);
    if (!_shouldApply(serverState)) return;
    applyState(serverState);
  }

  void updateCounts(int present, int absent) {
    _sessionState = _sessionState.copyWith(
      presentCount: present,
      absentCount: absent,
    );
    _stateController.add(_sessionState);
  }

  void notifyStudentVerified(String seat) {
    _studentVerifiedController.add(seat);
  }

  void setConnected(bool connected) {
    _connectionStateController.add(connected);
  }

  void reset() {
    _sessionState = SessionState(sessionId: '', state: 'IDLE');
    _sessionSecret = null;
    _websocketAccessToken = null;
    BoardStateMachine().reset();
    _stateController.add(_sessionState);
    Log.i('[SessionState] Reset to IDLE');
  }

  Future<bool> restoreFromLocal({
    required String sessionId,
    required String? sessionSecret,
    required String courseName,
    required String facultyName,
    required String sectionId,
  }) async {
    if (sessionId.isEmpty || sessionSecret == null) {
      Log.w('[SessionState] Cannot restore — missing sessionId or secret');
      return false;
    }

    _sessionSecret = sessionSecret;
    _sessionState = SessionState(
      sessionId: sessionId,
      state: 'ACTIVE',
      // FIX: Use version 1 instead of default 0 so that subsequent WebSocket
      // state updates (which carry version >= 1) are not rejected by the
      // _shouldApply version check. Previously version 0 caused the WS
      // to silently drop valid state updates after local recovery.
      version: 1,
      courseName: courseName,
      facultyName: facultyName,
      sectionId: sectionId,
    );

    // FIX: Do NOT force BoardState.active here. After a crash+restart, the
    // board should stay on IdleScreen so the hanging lock arrow ("SESSION IN
    // PROGRESS") appears — matching the normal post-OTP flow. The IdleScreen's
    // _checkActiveSession() will detect the resumable session in Isar and set
    // _activeSession, which makes the arrow visible. The user taps the arrow
    // to open the session overlay and navigates to Attendance from there.

    _stateController.add(_sessionState);
    Log.i('[SessionState] Restored from local (board stays idle): sid=$sessionId course=$courseName');
    return true;
  }

  bool _shouldApply(SessionState incoming) {
    if (_sessionState.isEmpty) return true;

    if (_sessionState.sessionId != incoming.sessionId) {
      return true;
    }

    if (incoming.version <= _sessionState.version) {
      return false;
    }

    return true;
  }

  void _syncBoardStateMachine(String state) {
    final machine = BoardStateMachine();
    switch (state) {
      case 'PREPARING':
      case 'IGNITING':
        machine.transitionTo(BoardState.igniting);
        break;
      case 'ACTIVE':
        machine.transitionTo(BoardState.active);
        break;
      case 'CLOSED':
        machine.transitionTo(BoardState.closed);
        break;
      default:
        machine.transitionTo(BoardState.idle);
    }
  }

  void dispose() {
    _stateController.close();
    _studentVerifiedController.close();
    _connectionStateController.close();
  }
}
