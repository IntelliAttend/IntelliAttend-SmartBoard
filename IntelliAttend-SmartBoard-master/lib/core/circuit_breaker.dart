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

  /// Called whenever state transitions occur (open → halfOpen → closed).
  /// Used by ApiService to broadcast connectivity changes to the UI.
  void Function(CircuitState state)? onStateChanged;

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
        _setState(CircuitState.halfOpen);
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

  void _setState(CircuitState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
  }

  void _onSuccess() {
    if (_state == CircuitState.halfOpen) {
      Log.i('[CB] $name → closed (trial call succeeded)');
    }
    _failureCount = 0;
    _setState(CircuitState.closed);
  }

  void _onFailure() {
    _failureCount++;
    _lastFailure = DateTime.now();
    if (_state == CircuitState.halfOpen || _failureCount >= failureThreshold) {
      Log.w('[CB] $name → open ($_failureCount failures)');
      _setState(CircuitState.open);
    }
  }

  void reset() {
    _failureCount = 0;
    _lastFailure = null;
    _setState(CircuitState.closed);
  }
}
