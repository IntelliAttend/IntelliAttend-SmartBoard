import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/rate_limiter.dart';

void main() {
  const testKey = 'test_key';

  setUp(() {
    RateLimiter.reset(testKey);
  });

  group('RateLimiter', () {
    test('allows first attempt', () {
      expect(RateLimiter.isAllowed(testKey), isTrue);
    });

    test('blocks after max attempts within window', () {
      for (int i = 0; i < 5; i++) {
        RateLimiter.recordAttempt(testKey);
      }
      expect(RateLimiter.isAllowed(testKey), isFalse);
    });

    test('allows again after reset', () {
      for (int i = 0; i < 5; i++) {
        RateLimiter.recordAttempt(testKey);
      }
      expect(RateLimiter.isAllowed(testKey), isFalse);

      RateLimiter.reset(testKey);
      expect(RateLimiter.isAllowed(testKey), isTrue);
    });

    test('getDelay returns zero when no attempts recorded', () {
      expect(RateLimiter.getDelay(testKey), Duration.zero);
    });

    test('getDelay returns exponential backoff', () {
      // Record attempts and check delay grows exponentially
      // 0 → 0s, 1 → 1s, 2 → 2s, 3 → 4s, 4 → 8s, 5 → 16s
      final delays = [0, 1, 2, 4, 8, 16];
      for (int i = 0; i < delays.length; i++) {
        expect(RateLimiter.getDelay(testKey),
            Duration(seconds: delays[i]));
        RateLimiter.recordAttempt(testKey);
      }
    });

    test('different keys have independent state', () {
      const otherKey = 'other_key';

      for (int i = 0; i < 5; i++) {
        RateLimiter.recordAttempt(testKey);
      }
      expect(RateLimiter.isAllowed(testKey), isFalse);
      expect(RateLimiter.isAllowed(otherKey), isTrue);
    });
  });
}
