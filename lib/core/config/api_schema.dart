/// Backend REST API field name references.
///
/// Every JSON key used in communication with the backend lives here so a
/// schema rename requires exactly one change site.
class ApiSchema {
  // ── Timetable ──────────────────────────────────────────────────────────────

  static String get fieldSlotId => 'id';
  static String get fieldDayOfWeek => 'day_of_week';
  static String get fieldStartTime => 'start_time';
  static String get fieldEndTime => 'end_time';
  static String get fieldSubjectName => 'subject_name';
  static String get fieldFacultyId => 'faculty_id';
  static String get fieldFacultyEmails => 'faculty_emails';
  static String get fieldSectionId => 'section_id';
  static String get fieldSmartBoardId => 'smart_board_id';

  // ── Students ───────────────────────────────────────────────────────────────

  static String get fieldRollNumber => 'roll_number';
  static String get fieldName => 'name';
  static String get fieldEmail => 'email';
  static String get fieldClassId => 'class_id';
  static String get fieldStatus => 'status';

  // ── Notifications ──────────────────────────────────────────────────────────

  static String get fieldTitle => 'title';
  static String get fieldBody => 'body';
  static String get fieldType => 'type';
  static String get fieldTimestamp => 'timestamp';
  static String get fieldPriority => 'priority';
  static String get fieldRead => 'read';
  static String get fieldCreatedAt => 'created_at';
  static String get fieldAttachmentUrl => 'attachment_url';
  static String get fieldAttachmentName => 'attachment_name';
  static String get fieldAttachmentType => 'attachment_type';
  static String get fieldAttachmentSize => 'attachment_size';
  static String get fieldPrecautionarySteps => 'precautionary_steps';
  static String get fieldLocation => 'location';
  static String get fieldSafeExit => 'safe_exit';
  static String get fieldAssemblyPoint => 'assembly_point';

  // ── Common response wrapper ────────────────────────────────────────────────

  static String get responseData => 'data';

  // ── Well-known field values ────────────────────────────────────────────────

  static String get statusActive => 'active';
}
