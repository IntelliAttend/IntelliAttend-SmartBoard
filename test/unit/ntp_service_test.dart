
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/network/ntp_service.dart';

void main() {
  group('NtpSyncService Logic', () {
    test('Should yield adjusted time using skew', () {
      final service = NtpSyncService();
      
      // Manually set skew to 10 seconds for testing logic
      service.clockSkew = const Duration(seconds: 10);
      
      final DateTime adjusted = service.adjustedTime;
      final DateTime local = DateTime.now();
      
      // Adjusted should be ~10s ahead of local
      expect(adjusted.difference(local).inSeconds, closeTo(10, 1));
    });
  });
}
