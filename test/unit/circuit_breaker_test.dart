import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/circuit_breaker.dart';

void main() {
  group('CircuitBreaker', () {
    late CircuitBreaker cb;

    setUp(() {
      cb = CircuitBreaker(
        name: 'test',
        failureThreshold: 3,
        cooldown: const Duration(seconds: 60),
      );
    });

    test('starts closed', () {
      expect(cb.state, CircuitState.closed);
      expect(cb.failureCount, 0);
    });

    test('passes through successful calls', () async {
      final result = await cb.call(() async => 'ok');
      expect(result, 'ok');
      expect(cb.state, CircuitState.closed);
    });

    test('opens after threshold failures', () async {
      for (int i = 0; i < 3; i++) {
        try {
          await cb.call(() async => throw Exception('fail'));
        } catch (_) {}
      }
      expect(cb.state, CircuitState.open);
      expect(cb.failureCount, 3);
    });

    test('throws CircuitBreakerOpenException when open', () async {
      for (int i = 0; i < 3; i++) {
        try {
          await cb.call(() async => throw Exception('fail'));
        } catch (_) {}
      }

      await expectLater(
        () => cb.call(() async => 'should not reach'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });

    test('resets on success after half-open', () async {
      for (int i = 0; i < 3; i++) {
        try {
          await cb.call(() async => throw Exception('fail'));
        } catch (_) {}
      }
      expect(cb.state, CircuitState.open);

      // Manually force half-open (simulating cooldown)
      cb = CircuitBreaker(
        name: 'test',
        failureThreshold: 3,
        cooldown: const Duration(milliseconds: 1),
      );
      for (int i = 0; i < 3; i++) {
        try {
          await cb.call(() async => throw Exception('fail'));
        } catch (_) {}
      }
      expect(cb.state, CircuitState.open);

      // Wait for cooldown
      await Future.delayed(const Duration(milliseconds: 2));

      final result = await cb.call(() async => 'recovered');
      expect(result, 'recovered');
      expect(cb.state, CircuitState.closed);
    });

    test('reset() clears state', () async {
      for (int i = 0; i < 3; i++) {
        try {
          await cb.call(() async => throw Exception('fail'));
        } catch (_) {}
      }
      expect(cb.state, CircuitState.open);

      cb.reset();
      expect(cb.state, CircuitState.closed);
      expect(cb.failureCount, 0);

      final result = await cb.call(() async => 'ok');
      expect(result, 'ok');
    });
  });
}
