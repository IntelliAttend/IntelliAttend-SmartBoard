import '../services/session_state_service.dart';

/// Authoritative session data that flows through constructors.
///
/// The SmartBoard owns this object. Server events update it via [copyWith],
/// but the object itself is never replaced wholesale. This eliminates the
/// class of bugs where a WS `session_ended` event wipes session metadata
/// (presentCount, courseName, facultyName) because the SummaryScreen reads
/// from this object, not from a global singleton.
class SessionContext {
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
  final String? slotId;
  final String? sessionSecret;
  final String? websocketToken;
  final List<int>? previousPresentIndices;
  final List<int>? previousAbsentIndices;

  const SessionContext({
    required this.sessionId,
    this.state = 'ACTIVE',
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
    this.slotId,
    this.sessionSecret,
    this.websocketToken,
    this.previousPresentIndices,
    this.previousAbsentIndices,
  });

  /// Create from a [SessionState] (existing singleton) + slot context.
  factory SessionContext.fromState(
    SessionState state, {
    String? slotId,
    String? sessionSecret,
  }) {
    return SessionContext(
      sessionId: state.sessionId,
      state: state.state,
      version: state.version,
      presentCount: state.presentCount,
      absentCount: state.absentCount,
      totalStudents: state.totalStudents,
      courseName: state.courseName,
      facultyName: state.facultyName,
      sectionId: state.sectionId,
      courseCode: state.courseCode,
      roomName: state.roomName,
      startTime: state.startTime,
      slotId: slotId,
      sessionSecret: sessionSecret,
      websocketToken: state.websocketToken,
    );
  }

  SessionContext copyWith({
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
    String? slotId,
    String? sessionSecret,
    String? websocketToken,
    List<int>? previousPresentIndices,
    List<int>? previousAbsentIndices,
  }) {
    return SessionContext(
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
      slotId: slotId ?? this.slotId,
      sessionSecret: sessionSecret ?? this.sessionSecret,
      websocketToken: websocketToken ?? this.websocketToken,
      previousPresentIndices: previousPresentIndices ?? this.previousPresentIndices,
      previousAbsentIndices: previousAbsentIndices ?? this.previousAbsentIndices,
    );
  }

  bool get isEmpty => sessionId.isEmpty;
  bool get isActive => state == 'ACTIVE';
  bool get isClosed => state == 'CLOSED';

  /// Display name for the course, with fallback.
  String get displayCourseName => courseName ?? 'Class';

  /// Display name for the faculty, with fallback.
  String get displayFacultyName => facultyName ?? 'Professor';
}
