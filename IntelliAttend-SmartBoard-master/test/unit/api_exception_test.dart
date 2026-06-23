import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/services/api_service.dart';

void main() {
  group('ApiException', () {
    test('stores userMessage and statusCode', () {
      final ex = ApiException('Not found', 404);
      expect(ex.userMessage, 'Not found');
      expect(ex.statusCode, 404);
    });

    test('toString returns userMessage', () {
      final ex = ApiException('Server error', 500);
      expect(ex.toString(), 'Server error');
    });
  });

  group('UnregisteredException', () {
    test('has status code 404', () {
      final ex = UnregisteredException('Device not registered');
      expect(ex.statusCode, 404);
      expect(ex.userMessage, 'Device not registered');
    });
  });

  group('UnauthorizedException', () {
    test('has status code 401', () {
      final ex = UnauthorizedException('Invalid credentials');
      expect(ex.statusCode, 401);
      expect(ex.userMessage, 'Invalid credentials');
    });
  });
}
