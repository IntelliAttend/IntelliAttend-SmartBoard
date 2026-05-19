
import 'package:isar/isar.dart';

part 'isar_schemas.g.dart';

@collection
class ActiveSession {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String sessionId;

  late DateTime scheduledEndTime;
  late String facultyName;
  late String courseName;
  late String sectionId;

  // Stores IDs of students who have successfully scanned
  // Used for instant UI repaint on crash recovery
  List<String> verifiedStudentIds = [];
  
  // Grid config for responsive layout
  late int rosterCount;
}

@collection
class DeviceRegistration {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String smartBoardId; // e.g., "IASB-4208" - Physical ID for registration

  String? classroomId;      // e.g., "room_4208" - Logical ID for database queries

  late String hardwareId;   // Hardware fingerprint
  late String roomName;     // Display name (e.g., "Hall 402")
  late String building;
  late String department;
  late int capacity;
  late DateTime registrationDate;
  
}

@collection
class QueuedScan {
  Id id = Isar.autoIncrement;

  @Index()
  late String sessionId;

  late String studentId;
  late String scannedTotpHash;
  late DateTime scanTimestamp;
}

/// Maps Isar dayOfWeek (1-7) to human-readable names.
const List<String> dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

@collection
class TimetableEntry {
  Id id = Isar.autoIncrement;
  
  @Index()
  late int dayOfWeek; // 1-7 (Mon-Sun)
  
  @Index()
  late String startTime; // e.g., "09:00"
  
  late String endTime;   // e.g., "10:00"
  late String courseName;
  late String facultyName;
  late String sectionId;
  String slotId = '';      // Document ID from Firestore
}
