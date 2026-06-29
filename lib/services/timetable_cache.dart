import 'package:flutter/foundation.dart';
import '../models/isar_schemas.dart';
import 'time_sync_service.dart';

class TimetableCache extends ChangeNotifier {
  static final TimetableCache _instance = TimetableCache._internal();
  factory TimetableCache() => _instance;
  TimetableCache._internal();

  List<TimetableEntry> _weeklyTimeline = [];
  bool _hasRealData = false;

  List<TimetableEntry> get weeklyTimeline =>
      List.unmodifiable(_useMockData ? _mockWeeklyTimeline : _weeklyTimeline);

  List<TimetableEntry> get todayTimeline {
    final dayOfWeek = TimeSyncService.timeNow.weekday;
    final source = _useMockData ? _mockWeeklyTimeline : _weeklyTimeline;
    final today = source
        .where((e) => e.dayOfWeek == dayOfWeek)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return today;
  }

  TimetableEntry? get currentSlot {
    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;

    for (final entry in todayTimeline) {
      final startParts = entry.startTime.split(':');
      final endParts = entry.endTime.split(':');
      if (startParts.length != 2 || endParts.length != 2) continue;

      final startMins =
          int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMins = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

      if (endMins < startMins) {
        if (currentMinutes >= startMins || currentMinutes < endMins) {
          return entry;
        }
      } else {
        if (currentMinutes >= startMins && currentMinutes < endMins) {
          return entry;
        }
      }
    }
    return null;
  }

  bool get _useMockData => _weeklyTimeline.isEmpty && !_hasRealData;

  List<TimetableEntry> get _mockWeeklyTimeline {
    final entries = <TimetableEntry>[];
    final mockSlots = _mockSlotDescriptors;

    for (int day = 1; day <= 7; day++) {
      for (int i = 0; i < mockSlots.length; i++) {
        final s = mockSlots[i];
        entries.add(TimetableEntry()
          ..dayOfWeek = day
          ..startTime = s.start
          ..endTime = s.end
          ..courseName = s.course
          ..facultyName = s.faculty
          ..sectionId = s.section
          ..slotId = 'mock_${day}_$i'
          ..courseCode = s.code
          ..subjectCode = s.code
          ..subjectName = s.course
          ..roomNumber = s.room
          ..slotType = 'regular'
          ..classType = 'Lecture');
      }
    }
    return entries;
  }

  static const _mockSlotDescriptors = [
    _SlotDescriptor('08:00', '09:00', 'Engineering Mathematics', 'Dr. Verma', 'sec-a', 'MATH101', 'Hall-101'),
    _SlotDescriptor('09:00', '10:00', 'Data Structures', 'Prof. Gupta', 'sec-a', 'CS201', 'Lab-201'),
    _SlotDescriptor('10:00', '11:00', 'Computer Networks', 'Dr. Patel', 'sec-b', 'CS301', 'Lab-202'),
    _SlotDescriptor('11:00', '12:00', 'Operating Systems', 'Prof. Singh', 'sec-a', 'CS302', 'Hall-102'),
    _SlotDescriptor('13:00', '14:00', 'Software Engineering', 'Dr. Gupta', 'sec-b', 'CS401', 'Lab-203'),
    _SlotDescriptor('14:00', '15:00', 'Database Systems', 'Prof. Kumar', 'sec-a', 'CS402', 'Lab-204'),
    _SlotDescriptor('15:00', '16:00', 'Machine Learning', 'Dr. Reddy', 'sec-b', 'CS501', 'Lab-205'),
    _SlotDescriptor('16:00', '17:00', 'Artificial Intelligence', 'Prof. Mehta', 'sec-a', 'CS502', 'Hall-103'),
  ];

  void updateAll(List<TimetableEntry> entries) {
    _weeklyTimeline = List.from(entries);
    _hasRealData = entries.isNotEmpty;
    notifyListeners();
  }
}

class _SlotDescriptor {
  final String start;
  final String end;
  final String course;
  final String faculty;
  final String section;
  final String code;
  final String room;

  const _SlotDescriptor(this.start, this.end, this.course, this.faculty,
      this.section, this.code, this.room);
}
