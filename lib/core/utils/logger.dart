import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

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
      'logger': 'intelliattend',
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
  static final Logger _logger = Logger(
    filter: _RedactingFilter(),
    printer: kReleaseMode ? _JsonPrinter() : PrettyPrinter(
      methodCount: 0,
      errorMethodCount: kReleaseMode ? 0 : 8,
      lineLength: 80,
      colors: !kReleaseMode,
      printEmojis: !kReleaseMode,
      printTime: !kReleaseMode,
    ) as LogPrinter,
    output: _RedactingOutput(),
  );

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
