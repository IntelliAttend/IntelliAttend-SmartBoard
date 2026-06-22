import '../core/config/api_schema.dart';
import 'api_service.dart';
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

/// Service for fetching student data from the backend REST API.
class StudentService {
  static final StudentService _instance = StudentService._internal();
  factory StudentService() => _instance;
  StudentService._internal();

  /// Cache of students by section ID to avoid repeated API calls.
  final Map<String, List<StudentInfo>> _sectionCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Fetch all students for a given section from the backend.
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
      final docs = await ApiService.getStudentsBySection(sectionId);

      final students = docs.map((doc) {
        final rollNumber = doc[ApiSchema.fieldRollNumber]?.toString() ?? '';
        final name = doc[ApiSchema.fieldName]?.toString() ?? 'Unknown';
        final email = doc[ApiSchema.fieldEmail]?.toString() ?? '';
        final docSectionId = doc[ApiSchema.fieldSectionId]?.toString() ?? sectionId;
        final classId = doc[ApiSchema.fieldClassId]?.toString() ?? '';
        final status = doc[ApiSchema.fieldStatus]?.toString() ?? ApiSchema.statusActive;

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
      return cached ?? [];
    }
  }

  /// Fetch students by class ID.
  Future<List<StudentInfo>> getStudentsByClass(String classId) async {
    try {
      Log.d('[StudentService] Fetching students for class: $classId');
      final docs = await ApiService.getStudentsByClass(classId);

      return docs.map((doc) {
        return StudentInfo(
          rollNumber: doc[ApiSchema.fieldRollNumber]?.toString() ?? '',
          name: doc[ApiSchema.fieldName]?.toString() ?? 'Unknown',
          email: doc[ApiSchema.fieldEmail]?.toString() ?? '',
          sectionId: doc[ApiSchema.fieldSectionId]?.toString() ?? '',
          classId: doc[ApiSchema.fieldClassId]?.toString() ?? classId,
          status: doc[ApiSchema.fieldStatus]?.toString() ?? ApiSchema.statusActive,
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
