import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/state/board_state_machine.dart';
import 'package:intelliattend_smartboard/services/session_state_service.dart';
import 'package:intelliattend_smartboard/services/websocket_service.dart';

void main() {
  group('Attendance session workflow contract', () {
    late SessionStateService sessionStateService;
    late BoardStateMachine boardStateMachine;

    setUp(() {
      sessionStateService = SessionStateService();
      boardStateMachine = BoardStateMachine();
      sessionStateService.reset();
      boardStateMachine.reset();
    });

    test('hydrates ACTIVE state and preserves websocket token for reconnect', () {
      sessionStateService.applyFromRecovery({
        'session_id': 'sess_abc',
        'state': 'ACTIVE',
        'version': 42,
        'present': 23,
        'absent': 37,
        'total_students': 60,
        'course_name': 'Data Structures',
        'faculty_name': 'Dr. Rao',
        'section_id': 'CSE-A',
        'room_name': '4208',
        'websocket_token': 'ws-token-123',
      });

      expect(sessionStateService.currentState.sessionId, 'sess_abc');
      expect(sessionStateService.currentState.state, 'ACTIVE');
      expect(sessionStateService.currentState.presentCount, 23);
      expect(sessionStateService.currentState.absentCount, 37);
      expect(sessionStateService.currentState.totalStudents, 60);
      expect(sessionStateService.websocketAccessToken, 'ws-token-123');
      expect(boardStateMachine.currentState, BoardState.active);
    });

    test('ignites, activates, and closes in server order only', () {
      sessionStateService.applyFromRecovery({
        'session_id': 'sess_abc',
        'state': 'PREPARING',
        'version': 1,
      });
      expect(boardStateMachine.currentState, BoardState.preparing);

      sessionStateService.applyFromRecovery({
        'session_id': 'sess_abc',
        'state': 'IGNITING',
        'version': 2,
        'session_secret_half1': 'half1',
      });
      expect(boardStateMachine.currentState, BoardState.igniting);

      sessionStateService.applyFromRecovery({
        'session_id': 'sess_abc',
        'state': 'ACTIVE',
        'version': 3,
        'websocket_token': 'token-active',
      });
      expect(boardStateMachine.currentState, BoardState.active);
      expect(sessionStateService.websocketAccessToken, 'token-active');

      sessionStateService.applyFromRecovery({
        'session_id': 'sess_abc',
        'state': 'CLOSED',
        'version': 4,
        'present': 54,
        'absent': 6,
      });
      expect(boardStateMachine.currentState, BoardState.closed);
      expect(sessionStateService.currentState.presentCount, 54);
      expect(sessionStateService.currentState.absentCount, 6);
    });

    test('ignores stale recovery payloads and keeps the current live state', () {
      sessionStateService.applyFromRecovery({
        'session_id': 'sess_abc',
        'state': 'ACTIVE',
        'version': 7,
        'present': 5,
        'absent': 55,
        'websocket_token': 'token-live',
      });

      sessionStateService.applyFromRecovery({
        'session_id': 'sess_abc',
        'state': 'IGNITING',
        'version': 6,
        'websocket_token': 'token-stale',
      });

      expect(sessionStateService.currentState.state, 'ACTIVE');
      expect(sessionStateService.currentState.presentCount, 5);
      expect(sessionStateService.websocketAccessToken, 'token-live');
      expect(boardStateMachine.currentState, BoardState.active);
    });

    test('parses websocket broadcast payloads used by the live roster', () {
      final syncStudent = PresentStudent.fromJson({
        'student_id': '123',
        'student_email': 'student@example.edu',
        'student_name': 'Student A',
        'status': 'PRESENT',
        'trust_score': 100,
        'marked_by': 'qr_scan',
        'recorded_at': '2026-06-22T10:20:00.000Z',
      });
      expect(syncStudent.studentId, '123');
      expect(syncStudent.studentEmail, 'student@example.edu');
      expect(syncStudent.status, 'PRESENT');

      final marked = AttendanceMarkedEvent.fromJson({
        'type': 'ATTENDANCE_MARKED',
        'student_id': '123',
        'student_email': 'student@example.edu',
        'student_name': 'Student A',
        'status': 'PRESENT',
        'trust_score': 100,
        'marked_by': 'manual_faculty',
        'recorded_at': '2026-06-22T10:20:05.000Z',
      });
      expect(marked.markedBy, 'manual_faculty');
      expect(marked.status, 'PRESENT');

      final ended = SessionEndedEvent.fromJson({
        'type': 'session_ended',
        'session_id': 'sess_abc',
        'status': 'completed',
        'timestamp': '2026-06-22T10:22:00.000Z',
      });
      expect(ended.sessionId, 'sess_abc');
      expect(ended.status, 'completed');
    });
  });
}