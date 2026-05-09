import 'dart:collection';

class RateLimiter {
  RateLimiter._();

  static final Map<String, _RateLimitState> _states = HashMap();

  static const int _maxAttempts = 5;
  static const Duration _windowDuration = Duration(minutes: 15);

  static _RateLimitState _getState(String key) {
    _states.putIfAbsent(key, () => _RateLimitState());
    return _states[key]!;
  }

  static bool isAllowed(String key) {
    final state = _getState(key);
    state._prune();
    return state._attempts.length < _maxAttempts;
  }

  static Duration getDelay(String key) {
    final state = _getState(key);
    state._prune();
    final count = state._attempts.length;
    if (count == 0) return Duration.zero;
    return Duration(seconds: 1 << (count - 1));
  }

  static void recordAttempt(String key) {
    final state = _getState(key);
    state._attempts.add(DateTime.now());
  }

  static void reset(String key) {
    _states.remove(key);
  }
}

class _RateLimitState {
  final List<DateTime> _attempts = [];

  void _prune() {
    final cutoff = DateTime.now().subtract(RateLimiter._windowDuration);
    _attempts.removeWhere((t) => t.isBefore(cutoff));
  }
}
