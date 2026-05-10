import 'utils/logger.dart';

enum CircuitState { closed, open, halfOpen }

class CircuitBreakerOpenException implements Exception {
  final String name;
  CircuitBreakerOpenException(this.name);

  @override
  String toString() => 'Circuit breaker open for [$name]';
}

class CircuitBreaker {
  final String name;
  final int failureThreshold;
  final Duration cooldown;

  int _failureCount = 0;
  DateTime? _lastFailure;
  CircuitState _state = CircuitState.closed;

  CircuitBreaker({
    required this.name,
    this.failureThreshold = 5,
    this.cooldown = const Duration(seconds: 60),
  });

  CircuitState get state => _state;
  int get failureCount => _failureCount;

  Future<T> call<T>(Future<T> Function() fn) async {
    if (_state == CircuitState.open) {
      if (_lastFailure != null &&
          DateTime.now().difference(_lastFailure!) >= cooldown) {
        _state = CircuitState.halfOpen;
        Log.d('[CB] $name → half-open (cooldown elapsed)');
      } else {
        throw CircuitBreakerOpenException(name);
      }
    }

    try {
      final result = await fn();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  void _onSuccess() {
    if (_state == CircuitState.halfOpen) {
      Log.i('[CB] $name → closed (trial call succeeded)');
    }
    _failureCount = 0;
    _state = CircuitState.closed;
  }

  void _onFailure() {
    _failureCount++;
    _lastFailure = DateTime.now();
    if (_state == CircuitState.halfOpen || _failureCount >= failureThreshold) {
      _state = CircuitState.open;
      Log.w('[CB] $name → open ($_failureCount failures)');
    }
  }

  void reset() {
    _failureCount = 0;
    _lastFailure = null;
    _state = CircuitState.closed;
  }
}
