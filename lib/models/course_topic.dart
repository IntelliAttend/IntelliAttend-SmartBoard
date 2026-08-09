/// A single topic within a syllabus unit, with completion status.
///
/// Mirrors the Faculty Mobile App's CourseTopic model and aligns with
/// the server's syllabus progress / topic completion responses.
class CourseTopic {
  final String name;
  final bool isCompleted;
  final int unitNumber;
  final String unitTitle;
  final String unitId;

  const CourseTopic({
    required this.name,
    this.isCompleted = false,
    this.unitNumber = 0,
    this.unitTitle = '',
    this.unitId = '',
  });

  factory CourseTopic.fromJson(Map<String, dynamic> json) {
    return CourseTopic(
      name: json['name'] as String? ?? json['topic_name'] as String? ?? '',
      isCompleted: json['is_completed'] as bool? ?? json['completed'] as bool? ?? false,
      unitNumber: json['unit_number'] as int? ?? 0,
      unitTitle: json['unit_title'] as String? ?? '',
      unitId: json['unit_id'] as String? ?? '',
    );
  }

  /// Build a list of [CourseTopic] from the syllabus units and topic completions.
  ///
  /// [units] – from `GET /api/v2/syllabus/subjects/{code}` → `units` array.
  /// [completions] – from `GET /api/v2/syllabus/subjects/{code}/completion`.
  static List<CourseTopic> fromSyllabus({
    required List<Map<String, dynamic>> units,
    required List<Map<String, dynamic>> completions,
  }) {
    // Index completions by "unitId_topicIndex" for O(1) lookup.
    final compSet = <String>{};
    for (final c in completions) {
      final unitId = c['syllabus_unit_id'] as String? ?? '';
      final idx = c['topic_index'] as int? ?? -1;
      if (c['is_completed'] == true) {
        compSet.add('${unitId}_$idx');
      }
    }

    final topics = <CourseTopic>[];
    for (final unit in units) {
      final unitId = unit['id'] as String? ?? '';
      final unitNumber = unit['unit_number'] as int? ?? 0;
      final unitTitle = unit['title'] as String? ?? 'Unit $unitNumber';
      final topicNames = (unit['topics'] as List<dynamic>? ?? [])
          .map((t) => t.toString())
          .toList();

      for (int i = 0; i < topicNames.length; i++) {
        topics.add(CourseTopic(
          name: topicNames[i],
          isCompleted: compSet.contains('${unitId}_$i'),
          unitNumber: unitNumber,
          unitTitle: unitTitle,
          unitId: unitId,
        ));
      }
    }
    return topics;
  }
}
