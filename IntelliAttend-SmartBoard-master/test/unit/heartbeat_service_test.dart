import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/services/heartbeat_service.dart';

void main() {
  group('HeartbeatSessionInfo', () {
    test('isActive when status is active and sessionId exists', () {
      final info = HeartbeatSessionInfo(
        sessionId: 'sess_CS101_20260522',
        status: 'active',
      );
      expect(info.isActive, isTrue);
      expect(info.isCompleted, isFalse);
      expect(info.isEmpty, isFalse);
    });

    test('isCompleted when status is completed', () {
      final info = HeartbeatSessionInfo(
        sessionId: 'sess_CS101_20260522',
        status: 'completed',
      );
      expect(info.isActive, isFalse);
      expect(info.isCompleted, isTrue);
      expect(info.isEmpty, isFalse);
    });

    test('isEmpty when both sessionId and status are null', () {
      final info = HeartbeatSessionInfo();
      expect(info.isActive, isFalse);
      expect(info.isCompleted, isFalse);
      expect(info.isEmpty, isTrue);
    });

    test('isActive is false when sessionId is null even if status is active', () {
      final info = HeartbeatSessionInfo(status: 'active');
      expect(info.isActive, isFalse);
    });

    test('isActive is false when status is active but sessionId is empty', () {
      final info = HeartbeatSessionInfo(sessionId: '', status: 'active');
      expect(info.isActive, isFalse);
    });

    test('not active for unknown status', () {
      final info = HeartbeatSessionInfo(
        sessionId: 'sess_abc',
        status: 'pre_allocated',
      );
      expect(info.isActive, isFalse);
    });
  });
}
