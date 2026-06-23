import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

String _dateTimeFormat(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  final s = time.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String _noDateTimeFormat(DateTime time) => '';

class _RedactingFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kReleaseMode && event.level.index < Level.warning.index) return false;
    return true;
  }
}

class _JsonPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final entry = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': event.level.toString(),
      'message': event.message.toString(),
      'service': 'smartboard',
      'version': Log._appVersion,
      'environment': kReleaseMode ? 'production' : 'development',
      'traceId': Log._generateTraceId(),
    };
    if (event.error != null) {
      entry['error'] = event.error.toString();
    }
    if (event.stackTrace != null) {
      entry['stackTrace'] = event.stackTrace.toString().split('\n').first;
    }
    return [jsonEncode(entry)];
  }
}

class _RedactingOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      final redacted = line
          .replaceAllMapped(
            RegExp(r'session_secret_[a-z0-9]+|eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'),
            (_) => '[REDACTED]',
          );
      debugPrint(redacted);
    }
  }
}

class Log {
  static String _appVersion = '';
  static int _traceIdCounter = 0;

  static final Logger _logger = Logger(
    filter: _RedactingFilter(),
    printer: kReleaseMode ? _JsonPrinter() : PrettyPrinter(
      methodCount: 0,
      errorMethodCount: kReleaseMode ? 0 : 8,
      lineLength: 80,
      colors: !kReleaseMode,
      printEmojis: !kReleaseMode,
      dateTimeFormat: !kReleaseMode ? _dateTimeFormat : _noDateTimeFormat,
    ) as LogPrinter,
    output: _RedactingOutput(),
  );

  static String _generateTraceId() {
    _traceIdCounter++;
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final seq = _traceIdCounter.toRadixString(16).padLeft(4, '0');
    return '$ts-$seq';
  }

  static void setAppVersion(String version) {
    _appVersion = version;
  }

  // ───── Smart / context-aware helpers ─────

  static final _lastLogMs = <String, int>{};
  static final _loggedOnce = <String>{};
  static final _lastValues = <String, dynamic>{};

  /// Logs at info level, but no more than once per [cooldownMs] for the
  /// given [key]. Useful for high-frequency loops that should only produce
  /// occasional output.
  static void iThrottled(String key, dynamic message, {int cooldownMs = 30000, dynamic error, StackTrace? stackTrace}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastLogMs[key];
    if (last != null && (now - last) < cooldownMs) return;
    _lastLogMs[key] = now;
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Logs at info level, but only the first time for the given [key] across
  /// the application lifetime. Resets on app restart.
  static void iOnce(String key, dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if (_loggedOnce.contains(key)) return;
    _loggedOnce.add(key);
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Logs at info level, but only when [value] differs from the last call
  /// for the same [key]. Ideal for state-transition logging inside builders
  /// or polling loops.
  static void iOnChange(String key, dynamic value, dynamic message, {dynamic error, StackTrace? stackTrace}) {
    final prev = _lastValues[key];
    if (prev == value) return;
    _lastValues[key] = value;
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  // ───── Standard methods ─────

  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  static void f(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
}
