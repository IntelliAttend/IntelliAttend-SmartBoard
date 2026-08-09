import '../core/utils/logger.dart';
import '../models/course_topic.dart';
import '../models/syllabus_unit.dart';
import 'api_service.dart';

/// Service layer for syllabus / curriculum data.
///
/// Wraps [ApiService] syllabus calls and returns typed models. All methods
/// are static singletons — no instantiation needed.
class SyllabusService {
  SyllabusService._();

  /// Fetch the full syllabus for a subject merged with per-unit progress.
  ///
  /// Returns a list of [SyllabusUnit] sorted by unit number, with topic
  /// names from the syllabus and completion stats from the progress endpoint.
  static Future<List<SyllabusUnit>> getUnitsWithProgress(
    String courseCode,
    String sectionId, {
    String regulation = 'R22',
  }) async {
    try {
      final syllabusFuture = ApiService.getSubjectSyllabus(courseCode, regulation: regulation);
      final progressFuture = ApiService.getSyllabusProgress(courseCode, sectionId);

      final syllabus = await syllabusFuture;
      final progress = await progressFuture;

      final rawUnits = (syllabus['units'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final progressUnits = (progress['units'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      // Index progress by unit_number for quick lookup.
      final progressByNum = <int, Map<String, dynamic>>{};
      for (final pu in progressUnits) {
        progressByNum[pu['unit_number'] as int? ?? 0] = pu;
      }

      final units = <SyllabusUnit>[];
      for (final raw in rawUnits) {
        final unit = SyllabusUnit.fromSyllabusJson(raw);
        final prog = progressByNum[unit.unitNumber];
        if (prog != null) {
          units.add(unit.mergeProgress(SyllabusUnit.fromProgressJson(prog)));
        } else {
          units.add(unit);
        }
      }

      units.sort((a, b) => a.unitNumber.compareTo(b.unitNumber));
      return units;
    } catch (e) {
      Log.e('[SyllabusService] Failed to load units with progress: $e');
      return [];
    }
  }

  /// Build [CourseTopic] list from syllabus + completion data.
  static Future<List<CourseTopic>> getTopics(
    String courseCode,
    String sectionId, {
    String regulation = 'R22',
  }) async {
    try {
      final syllabusFuture = ApiService.getSubjectSyllabus(courseCode, regulation: regulation);
      final completionsFuture = ApiService.getTopicCompletions(courseCode, sectionId);

      final syllabus = await syllabusFuture;
      final completions = await completionsFuture;

      final units = (syllabus['units'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      return CourseTopic.fromSyllabus(units: units, completions: completions);
    } catch (e) {
      Log.e('[SyllabusService] Failed to load topics: $e');
      return [];
    }
  }

  /// Fetch just the syllabus subject name (for display).
  static Future<String> getSubjectName(
    String courseCode, {
    String regulation = 'R22',
  }) async {
    try {
      final data = await ApiService.getSubjectSyllabus(
        courseCode,
        regulation: regulation,
      );
      return data['name'] as String? ?? courseCode;
    } catch (e) {
      Log.e('[SyllabusService] Failed to load subject name: $e');
      return courseCode;
    }
  }
}
