/// Centralised Firestore collection and field name references.
///
/// Every hardcoded string that names a Firestore collection, field, or
/// well-known value should live here so a schema rename by the server team
/// requires exactly one change site.
class FirestoreSchema {
  // ── Collections ──────────────────────────────────────────────────────────

  static String get timetableSlots => 'timetable_slots';
  static String get notifications => 'notifications';
  static String get activeSessions => 'ActiveSessions';
  static String get attendees => 'attendees';
  static String get students => 'students';
  static String get configCollection => 'config';

  // ── Field names (alphabetical) ───────────────────────────────────────────

  // synthetic doc ID injected by FirestoreRestClient
  static String get fieldDocId => '__id';

  static String get fieldBody => 'body';
  static String get fieldClassId => 'class_id';
  static String get fieldCreatedAt => 'created_at';
  static String get fieldDayOfWeek => 'day_of_week';
  static String get fieldEmail => 'email';
  static String get fieldEndTime => 'end_time';
  static String get fieldFacultyEmails => 'faculty_emails';
  static String get fieldFacultyId => 'faculty_id';
  static String get fieldName => 'name';
  static String get fieldRead => 'read';
  static String get fieldRollNumber => 'roll_number';
  static String get fieldSectionId => 'section_id';
  static String get fieldSessionId => 'session_id';
  static String get fieldSmartBoardId => 'smart_board_id';
  static String get fieldStartTime => 'start_time';
  static String get fieldStatus => 'status';
  static String get fieldStudentId => 'student_id';
  static String get fieldSubjectName => 'subject_name';
  static String get fieldTimestamp => 'timestamp';
  static String get fieldTitle => 'title';
  static String get fieldType => 'type';

  // ── Well-known field values ──────────────────────────────────────────────

  static String get statusActive => 'active';
  static String get statusEnded => 'ended';
}
