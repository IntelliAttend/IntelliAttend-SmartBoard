import 'package:flutter_test/flutter_test.dart';

/// Lightweight stand-in for TimetableEntry (Isar model) so widget tests
/// don't need a running Isar instance.  Keeps only the fields the
/// footer / TimelineSlot actually read.
class FakeEntry {
  final String slotId;
  final String startTime;
  final String endTime;
  final String courseName;
  final String slotType;
  final bool isBreak;
  final int dayOfWeek;

  const FakeEntry({
    required this.slotId,
    required this.startTime,
    required this.endTime,
    required this.courseName,
    this.slotType = 'regular',
    this.isBreak = false,
    this.dayOfWeek = 1,
  });
}

/// Mirrors the exact filter used in idle_screen.dart _buildFooter.
List<FakeEntry> footerFilter(List<FakeEntry> entries) {
  return entries
      .where((e) =>
          !e.isBreak &&
          e.slotType != 'tutorial' &&
          e.slotType != 'library')
      .toList();
}

/// Mirrors the exact filter used in timetable_cache.dart currentSlot.
FakeEntry? currentSlotFilter(List<FakeEntry> entries, int currentMinutes) {
  for (final entry in entries) {
    if (entry.isBreak) continue;
    if (entry.slotType == 'tutorial' || entry.slotType == 'library') continue;
    final sp = entry.startTime.split(':');
    final ep = entry.endTime.split(':');
    if (sp.length != 2 || ep.length != 2) continue;
    final startMins = int.parse(sp[0]) * 60 + int.parse(sp[1]);
    final endMins = int.parse(ep[0]) * 60 + int.parse(ep[1]);
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

/// Simulates a full weekday timetable (Mon–Fri style).
List<FakeEntry> _sampleTimetable() => const [
      // P1 – theory
      FakeEntry(
          slotId: 'p1', startTime: '09:30', endTime: '10:20',
          courseName: 'Data Structures', slotType: 'regular', dayOfWeek: 1),
      // Bio Break
      FakeEntry(
          slotId: 'break1', startTime: '10:20', endTime: '10:30',
          courseName: 'Bio Break', isBreak: true, dayOfWeek: 1),
      // P2 – theory
      FakeEntry(
          slotId: 'p2', startTime: '10:30', endTime: '11:20',
          courseName: 'Algorithms', slotType: 'regular', dayOfWeek: 1),
      // P3 – lab (THIS IS THE CRITICAL ONE)
      FakeEntry(
          slotId: 'p3lab', startTime: '11:20', endTime: '12:10',
          courseName: 'OS Lab', slotType: 'lab', dayOfWeek: 1),
      // Lunch Break
      FakeEntry(
          slotId: 'lunch', startTime: '12:10', endTime: '12:50',
          courseName: 'Lunch Break', isBreak: true, dayOfWeek: 1),
      // P4 – theory
      FakeEntry(
          slotId: 'p4', startTime: '12:50', endTime: '13:40',
          courseName: 'Networks', slotType: 'regular', dayOfWeek: 1),
      // P5 – tutorial (should be EXCLUDED from footer)
      FakeEntry(
          slotId: 'tut1', startTime: '13:40', endTime: '14:30',
          courseName: 'Tutorial', slotType: 'tutorial', dayOfWeek: 1),
      // P6 – library (should be EXCLUDED from footer)
      FakeEntry(
          slotId: 'lib1', startTime: '14:30', endTime: '15:20',
          courseName: 'Library', slotType: 'library', dayOfWeek: 1),
    ];

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 1 — Footer filter: slot type inclusion / exclusion
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  group('Footer filter — slot type inclusion', () {
    test('regular slots are included', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      expect(result.any((e) => e.slotId == 'p1'), isTrue,
          reason: 'P1 (regular) must appear in footer');
      expect(result.any((e) => e.slotId == 'p2'), isTrue,
          reason: 'P2 (regular) must appear in footer');
      expect(result.any((e) => e.slotId == 'p4'), isTrue,
          reason: 'P4 (regular) must appear in footer');
    });

    test('lab slots are included', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      expect(result.any((e) => e.slotId == 'p3lab'), isTrue,
          reason: 'P3 (lab) must appear in footer — this was the bug');
    });

    test('break slots are excluded', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      expect(result.any((e) => e.slotId == 'break1'), isFalse,
          reason: 'Bio Break must NOT appear in footer');
      expect(result.any((e) => e.slotId == 'lunch'), isFalse,
          reason: 'Lunch Break must NOT appear in footer');
    });

    test('tutorial slots are excluded', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      expect(result.any((e) => e.slotId == 'tut1'), isFalse,
          reason: 'Tutorial must NOT appear in footer');
    });

    test('library slots are excluded', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      expect(result.any((e) => e.slotId == 'lib1'), isFalse,
          reason: 'Library must NOT appear in footer');
    });

    test('footer shows correct count for a mixed day', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      // P1, P2, P3(lab), P4 = 4 class slots; breaks, tutorial, library excluded
      expect(result.length, 4,
          reason: 'Footer must show exactly 4 class/lab slots');
    });

    test('footer shows correct slot order (sorted by start time)', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      expect(result[0].slotId, 'p1');
      expect(result[1].slotId, 'p2');
      expect(result[2].slotId, 'p3lab');
      expect(result[3].slotId, 'p4');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 2 — currentSlot: time-based matching (mirrors TimetableCache)
  // ───────────────────────────────────────────────────────────────────────────
  group('currentSlot — time matching', () {
    final entries = _sampleTimetable();

    test('returns P1 at 09:30', () {
      final slot = currentSlotFilter(entries, 9 * 60 + 30);
      expect(slot?.slotId, 'p1');
    });

    test('returns P1 at 10:19 (just before end)', () {
      final slot = currentSlotFilter(entries, 10 * 60 + 19);
      expect(slot?.slotId, 'p1');
    });

    test('returns P2 at 10:30', () {
      final slot = currentSlotFilter(entries, 10 * 60 + 30);
      expect(slot?.slotId, 'p2');
    });

    test('returns P3 lab at 11:30', () {
      final slot = currentSlotFilter(entries, 11 * 60 + 30);
      expect(slot?.slotId, 'p3lab',
          reason: 'Lab slots must be matched by currentSlot');
    });

    test('returns P4 at 13:00', () {
      final slot = currentSlotFilter(entries, 13 * 60 + 0);
      expect(slot?.slotId, 'p4');
    });

    test('returns null during lunch break (12:20)', () {
      final slot = currentSlotFilter(entries, 12 * 60 + 20);
      expect(slot, isNull,
          reason: 'currentSlot must not return break slots');
    });

    test('returns null during tutorial (14:00)', () {
      final slot = currentSlotFilter(entries, 14 * 60 + 0);
      expect(slot, isNull,
          reason: 'currentSlot must not return tutorial slots');
    });

    test('returns null during library (15:00)', () {
      final slot = currentSlotFilter(entries, 15 * 60 + 0);
      expect(slot, isNull,
          reason: 'currentSlot must not return library slots');
    });

    test('returns null before first class (08:00)', () {
      final slot = currentSlotFilter(entries, 8 * 60 + 0);
      expect(slot, isNull);
    });

    test('returns null after last class (16:00)', () {
      final slot = currentSlotFilter(entries, 16 * 60 + 0);
      expect(slot, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 4 — Edge cases
  // ───────────────────────────────────────────────────────────────────────────
  group('Edge cases', () {
    test('empty timetable produces empty footer', () {
      final result = footerFilter([]);
      expect(result, isEmpty);
    });

    test('all-break day produces empty footer', () {
      final entries = [
        const FakeEntry(slotId: 'b1', startTime: '09:00', endTime: '10:00',
            courseName: 'Break', isBreak: true),
        const FakeEntry(slotId: 'b2', startTime: '10:00', endTime: '11:00',
            courseName: 'Break', isBreak: true),
      ];
      final result = footerFilter(entries);
      expect(result, isEmpty);
    });

    test('all-tutorial day produces empty footer', () {
      final entries = [
        const FakeEntry(slotId: 't1', startTime: '09:00', endTime: '10:00',
            courseName: 'Tutorial', slotType: 'tutorial'),
      ];
      final result = footerFilter(entries);
      expect(result, isEmpty);
    });

    test('unknown slot type is included (future-proofing)', () {
      final entries = [
        const FakeEntry(slotId: 'x1', startTime: '09:00', endTime: '10:00',
            courseName: 'Workshop', slotType: 'workshop'),
      ];
      final result = footerFilter(entries);
      expect(result.length, 1,
          reason: 'Unknown slot types should not be excluded by the filter');
    });

    test('currentSlot handles midnight wrap (23:00–01:00)', () {
      final entries = [
        const FakeEntry(slotId: 'night', startTime: '23:00', endTime: '01:00',
            courseName: 'Night Class', slotType: 'regular'),
      ];
      expect(currentSlotFilter(entries, 23 * 60 + 30)?.slotId, 'night');
      expect(currentSlotFilter(entries, 0 * 60 + 30)?.slotId, 'night');
      expect(currentSlotFilter(entries, 1 * 60 + 0), isNull);
    });

    test('P1 appears first in footer (sorted by startTime)', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      expect(result.first.slotId, 'p1',
          reason: 'P1 must be the first slot shown in footer');
    });

    test('lab slot appears between regular slots in correct position', () {
      final entries = _sampleTimetable();
      final result = footerFilter(entries);
      // P1(09:30), P2(10:30), P3lab(11:20), P4(12:50)
      expect(result[2].slotId, 'p3lab',
          reason: 'Lab P3 must appear between P2 and P4');
      expect(result[2].courseName, 'OS Lab');
    });
  });
}
