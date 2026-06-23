import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/services/websocket_service.dart';

void main() {
  group('PresentStudent - JSON parsing', () {
    test('parses full data correctly', () {
      final json = {
        'student_id': 'stu_001',
        'student_name': 'Alice',
        'status': 'PRESENT',
        'recorded_at': '2026-05-22T10:15:30.123Z',
      };
      final student = PresentStudent.fromJson(json);
      expect(student.studentId, equals('stu_001'));
      expect(student.studentName, equals('Alice'));
      expect(student.status, equals('PRESENT'));
      expect(student.recordedAt, isNotNull);
    });

    test('handles missing optional fields', () {
      final json = {
        'student_id': 'stu_002',
      };
      final student = PresentStudent.fromJson(json);
      expect(student.studentId, equals('stu_002'));
      expect(student.studentName, equals(''));
      expect(student.status, equals('PRESENT'));
    });
  });

  group('AttendanceMarkedEvent - JSON parsing', () {
    test('parses full data correctly', () {
      final json = {
        'type': 'ATTENDANCE_MARKED',
        'student_id': 'stu_042',
        'studentName': 'Rahul K',
        'status': 'PRESENT',
        'trust_score': 92,
        'recorded_at': '2026-05-22T10:15:30.123Z',
      };
      final event = AttendanceMarkedEvent.fromJson(json);
      expect(event.studentId, equals('stu_042'));
      expect(event.studentName, equals('Rahul K'));
      expect(event.status, equals('PRESENT'));
      expect(event.trustScore, equals(92));
    });

    test('handles missing fields with defaults', () {
      final json = {
        'student_id': 'stu_999',
      };
      final event = AttendanceMarkedEvent.fromJson(json);
      expect(event.studentId, equals('stu_999'));
      expect(event.trustScore, equals(0));
      expect(event.studentName, equals(''));
    });
  });

  group('SessionEndedEvent - JSON parsing', () {
    test('parses full data correctly', () {
      final json = {
        'type': 'session_ended',
        'session_id': 'sess_CS101_20260522',
        'status': 'completed',
        'timestamp': '2026-05-22T11:30:00Z',
      };
      final event = SessionEndedEvent.fromJson(json);
      expect(event.sessionId, equals('sess_CS101_20260522'));
      expect(event.status, equals('completed'));
      expect(event.timestamp, isNotNull);
    });

    test('handles missing timestamp', () {
      final json = {
        'session_id': 'sess_abc',
      };
      final event = SessionEndedEvent.fromJson(json);
      expect(event.sessionId, equals('sess_abc'));
      expect(event.status, equals('ended'));
    });
  });
}
