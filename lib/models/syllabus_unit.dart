/// A syllabus unit containing its topics and progress metadata.
///
/// Built from the server's `GET /api/v2/syllabus/subjects/{code}/progress`
/// and `GET /api/v2/syllabus/subjects/{code}` responses.
class SyllabusUnit {
  final String id;
  final int unitNumber;
  final String title;
  final List<String> topics;
  final int? hours;
  final int totalTopics;
  final int completedTopics;
  final double percentage;

  const SyllabusUnit({
    required this.id,
    required this.unitNumber,
    required this.title,
    this.topics = const [],
    this.hours,
    this.totalTopics = 0,
    this.completedTopics = 0,
    this.percentage = 0.0,
  });

  /// Build from the syllabus subject response (units array).
  factory SyllabusUnit.fromSyllabusJson(Map<String, dynamic> json) {
    return SyllabusUnit(
      id: json['id'] as String? ?? '',
      unitNumber: json['unit_number'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      topics: (json['topics'] as List<dynamic>? ?? [])
          .map((t) => t.toString())
          .toList(),
      hours: json['hours'] as int?,
    );
  }

  /// Build from the syllabus progress response (units array).
  factory SyllabusUnit.fromProgressJson(Map<String, dynamic> json) {
    return SyllabusUnit(
      id: json['unit_id'] as String? ?? '',
      unitNumber: json['unit_number'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      totalTopics: json['total_topics'] as int? ?? 0,
      completedTopics: json['completed_topics'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Merge a syllabus unit with its progress data.
  SyllabusUnit mergeProgress(SyllabusUnit progress) {
    return SyllabusUnit(
      id: id,
      unitNumber: unitNumber,
      title: title,
      topics: topics,
      hours: hours,
      totalTopics: progress.totalTopics > 0 ? progress.totalTopics : topics.length,
      completedTopics: progress.completedTopics,
      percentage: progress.percentage,
    );
  }

  bool get isComplete => totalTopics > 0 && completedTopics == totalTopics;
}
