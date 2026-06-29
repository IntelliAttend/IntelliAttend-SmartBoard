import 'package:isar/isar.dart';

part 'isar_schemas.g.dart';

// ─── Active Session ─────────────────────────────────────────────────────────


@collection
class ActiveSession {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String sessionId;

  late DateTime scheduledEndTime;
  late String facultyName;
  late String courseName;
  late String sectionId;

  List<String> verifiedStudentIds = [];

  late int rosterCount;

  List<int> presentIndices = [];
  List<int> absentIndices = [];
}


// ─── Device Registration ─────────────────────────────────────────────────────


@collection
class DeviceRegistration {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String smartBoardId;

  String? classroomId;

  late String hardwareId;
  late String roomName;
  late String building;
  late String department;
  late int capacity;
  late DateTime registrationDate;
}


// ─── Queued Scan (offline vault) ─────────────────────────────────────────────


@collection
class QueuedScan {
  Id id = Isar.autoIncrement;

  @Index()
  late String sessionId;

  late String studentId;
  late String scannedTotpHash;
  late DateTime scanTimestamp;
}


// ─── Day name helpers ────────────────────────────────────────────────────────


/// Maps Isar dayOfWeek (1-7) to human-readable names.
const List<String> dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];


// ─── Timetable Entry ─────────────────────────────────────────────────────────


@collection
class TimetableEntry {
  Id id = Isar.autoIncrement;

  @Index()
  late int dayOfWeek; // 1-7 (Mon-Sun)

  @Index()
  late String startTime; // e.g., "09:00"

  late String endTime; // e.g., "10:00"
  late String courseName;
  late String facultyName;
  late String sectionId;
  String slotId = '';

  // Hydration-enriched fields
  String courseCode = '';
  String subjectCode = '';
  String subjectName = '';
  String sectionName = '';
  List<String> facultyEmails = [];
  String roomNumber = '';
  String slotType = 'regular';
  String classType = 'Lecture';
}


// ─── Hydration Profile (board identity) ──────────────────────────────────────


@collection
class HydrationProfile {
  Id id = Isar.autoIncrement;

  late String boardId;
  late String boardName;
  late String roomId;
  String? roomNumber;
  String? building;
  String? floor;
  String? institutionId;
  String? institutionName;
  String? timezone;
  late bool isRegistered;
}


// ─── Hydration Roster (student per section+course) ───────────────────────────


@collection
class HydrationRoster {
  Id id = Isar.autoIncrement;

  @Index()
  late String rosterKey; // "{section_id}_{course_code}"

  late String studentId;
  late String name;
  String? rollNumber;
}


// ─── Completed Session ───────────────────────────────────────────────────────


@collection
class CompletedSession {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String slotId;

  late String sessionId;
  late DateTime completedAt;
  late String courseName;
  late String facultyName;
  late int attendeeCount;
}
