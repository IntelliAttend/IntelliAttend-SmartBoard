import 'dart:async';
import '../core/utils/logger.dart';
import '../core/state/board_state_machine.dart';
import 'totp_engine.dart';

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
  final String? roomName;
  final String? startTime;
  final String? sessionSecretHalf1;
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
    this.roomName,
    this.startTime,
    this.sessionSecretHalf1,
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
      roomName: json['room_name'] as String?,
      startTime: json['start_time'] as String?,
      sessionSecretHalf1: json['session_secret_half1'] as String?,
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
    String? roomName,
    String? startTime,
    String? sessionSecretHalf1,
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
      roomName: roomName ?? this.roomName,
      startTime: startTime ?? this.startTime,
      sessionSecretHalf1: sessionSecretHalf1 ?? this.sessionSecretHalf1,
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
  TotpEngine? _totpEngine;
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
  TotpEngine? get totpEngine => _totpEngine;
  String? get websocketAccessToken => _websocketAccessToken;

  void storeSessionSecrets(String secret, TotpEngine engine, String? wsToken) {
    _sessionSecret = secret;
    _totpEngine = engine;
    _websocketAccessToken = wsToken;
  }

  void applyState(SessionState newState) {
    if (!_shouldApply(newState)) return;

    _sessionState = newState;
    if (newState.websocketToken != null) {
      _websocketAccessToken = newState.websocketToken;
    }
    _syncBoardStateMachine(newState.state);
    _stateController.add(newState);
    Log.i('[SessionState] Applied: ${newState.state} sid=${newState.sessionId} v=${newState.version}');
  }

  void applyFromRecovery(Map<String, dynamic> json) {
    final serverState = SessionState.fromJson(json);
    if (!_shouldApply(serverState)) return;

    _sessionState = serverState;
    if (serverState.websocketToken != null) {
      _websocketAccessToken = serverState.websocketToken;
    }
    _syncBoardStateMachine(serverState.state, force: true);
    _stateController.add(serverState);
    Log.i('[SessionState] Recovered: ${serverState.state} sid=${serverState.sessionId} v=${serverState.version}');
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
    _totpEngine = null;
    _websocketAccessToken = null;
    BoardStateMachine().reset();
    _stateController.add(_sessionState);
    Log.i('[SessionState] Reset to IDLE');
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

  void _syncBoardStateMachine(String state, {bool force = false}) {
    final machine = BoardStateMachine();
    switch (state) {
      case 'PREPARING':
        if (force) {
          machine.forceTransitionTo(BoardState.preparing);
        } else {
          machine.transitionTo(BoardState.preparing);
        }
        break;
      case 'IGNITING':
        if (force) {
          machine.forceTransitionTo(BoardState.igniting);
        } else {
          machine.transitionTo(BoardState.igniting);
        }
        break;
      case 'ACTIVE':
        if (force) {
          machine.forceTransitionTo(BoardState.active);
        } else {
          machine.transitionTo(BoardState.active);
        }
        break;
      case 'CLOSED':
        if (force) {
          machine.forceTransitionTo(BoardState.closed);
        } else {
          machine.transitionTo(BoardState.closed);
        }
        break;
      default:
        if (force) {
          machine.forceTransitionTo(BoardState.idle);
        } else {
          machine.transitionTo(BoardState.idle);
        }
    }
  }

  void dispose() {
    _stateController.close();
    _studentVerifiedController.close();
    _connectionStateController.close();
  }
}
