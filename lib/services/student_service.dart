import 'firestore_rest_client.dart';
import '../core/utils/logger.dart';

/// Represents a student with their roll number and display info.
class StudentInfo {
  final String rollNumber;
  final String name;
  final String email;
  final String sectionId;
  final String classId;
  final String status;

  StudentInfo({
    required this.rollNumber,
    required this.name,
    required this.email,
    required this.sectionId,
    required this.classId,
    this.status = 'active',
  });

  @override
  String toString() => 'StudentInfo($rollNumber, $name)';
}

/// Service for fetching student data from Firestore.
///
/// Students are stored in the `students` collection with fields:
///   - roll_number (document ID)
///   - name
///   - email
///   - section_id
///   - class_id
///   - status
class StudentService {
  static final StudentService _instance = StudentService._internal();
  factory StudentService() => _instance;
  StudentService._internal();

  /// Cache of students by section ID to avoid repeated Firestore calls.
  final Map<String, List<StudentInfo>> _sectionCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Fetch all students for a given section from Firestore.
  ///
  /// Uses a 5-minute cache to avoid excessive API calls.
  /// Falls back to empty list on error (graceful degradation).
  Future<List<StudentInfo>> getStudentsBySection(String sectionId) async {
    // Check cache first
    final cached = _sectionCache[sectionId];
    final timestamp = _cacheTimestamps[sectionId];
    if (cached != null &&
        timestamp != null &&
        DateTime.now().difference(timestamp) < _cacheTtl) {
      Log.d('[StudentService] Using cached students for section: $sectionId (count: ${cached.length})');
      return cached;
    }

    try {
      Log.d('[StudentService] Fetching students for section: $sectionId');
      final docs = await FirestoreRestClient.runQuery(
        collection: 'students',
        where: {
          'section_id': sectionId,
          'status': 'active',
        },
      );

      final students = docs.map((doc) {
        final rollNumber = doc['__id']?.toString() ??
            doc['roll_number']?.toString() ??
            '';
        final name = doc['name']?.toString() ?? 'Unknown';
        final email = doc['email']?.toString() ?? '';
        final docSectionId = doc['section_id']?.toString() ?? sectionId;
        final classId = doc['class_id']?.toString() ?? '';
        final status = doc['status']?.toString() ?? 'active';

        return StudentInfo(
          rollNumber: rollNumber,
          name: name,
          email: email,
          sectionId: docSectionId,
          classId: classId,
          status: status,
        );
      }).toList();

      // Cache the result
      _sectionCache[sectionId] = students;
      _cacheTimestamps[sectionId] = DateTime.now();

      Log.i('[StudentService] Fetched ${students.length} students for section: $sectionId');
      return students;
    } catch (e) {
      Log.w('[StudentService] Failed to fetch students for section $sectionId: $e');
      // Return cached data if available, even if expired
      return cached ?? [];
    }
  }

  /// Fetch students by class ID.
  Future<List<StudentInfo>> getStudentsByClass(String classId) async {
    try {
      Log.d('[StudentService] Fetching students for class: $classId');
      final docs = await FirestoreRestClient.runQuery(
        collection: 'students',
        where: {
          'class_id': classId,
          'status': 'active',
        },
      );

      return docs.map((doc) {
        return StudentInfo(
          rollNumber: doc['__id']?.toString() ??
              doc['roll_number']?.toString() ??
              '',
          name: doc['name']?.toString() ?? 'Unknown',
          email: doc['email']?.toString() ?? '',
          sectionId: doc['section_id']?.toString() ?? '',
          classId: doc['class_id']?.toString() ?? classId,
          status: doc['status']?.toString() ?? 'active',
        );
      }).toList();
    } catch (e) {
      Log.w('[StudentService] Failed to fetch students for class $classId: $e');
      return [];
    }
  }

  /// Clear the student cache.
  void clearCache([String? sectionId]) {
    if (sectionId != null) {
      _sectionCache.remove(sectionId);
      _cacheTimestamps.remove(sectionId);
    } else {
      _sectionCache.clear();
      _cacheTimestamps.clear();
    }
  }

  /// Resolve a student's display name from their roll number.
  String getDisplayName(String rollNumber, List<StudentInfo> students) {
    final match = students.firstWhere(
      (s) => s.rollNumber.toUpperCase() == rollNumber.toUpperCase(),
      orElse: () => StudentInfo(
        rollNumber: rollNumber,
        name: rollNumber,
        email: '',
        sectionId: '',
        classId: '',
      ),
    );
    return match.name;
  }
}
