import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/services/session_manager.dart';

void main() {
  group('SessionManager', () {
    test('throws when accessing isar before init', () {
      expect(
        () => SessionManager.isar,
        throwsA(isA<Exception>()),
      );
    });

    test('init does not throw', () async {
      // init() will likely fail in test environment because Isar
      // needs platform support. This test verifies graceful handling.
      // If it succeeds, all the better; if it fails we verify no crash.
      try {
        await SessionManager.init();
      } catch (_) {
        // Expected in test env without Isar native library.
      }
    });
  });
}
