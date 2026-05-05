
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
  late String roomId;

  late String hardwareId; // Storing the WIN_UUID_... here
  late String roomName;
  late String building;
  late String department;
  late int capacity;
  late DateTime registrationDate;
  
  // v5.4 Cryptographic Trust: API Key for authentication
  String? apiKey; // Long-lived key issued by server during registration
  String? accessToken; // Short-lived JWT
  int? tokenExpiryMs; // When the access token expires
  String? refreshToken; // For obtaining new access tokens
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
}
