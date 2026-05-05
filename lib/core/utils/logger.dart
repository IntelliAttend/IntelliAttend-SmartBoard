import 'package:logger/logger.dart';

/// A professional logging wrapper for the IntelliAttend project.
/// Standardizes log formatting and provides level-based filtering.
class Log {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0, 
      errorMethodCount: 8, 
      lineLength: 80, 
      colors: true, 
      printEmojis: true, 
      printTime: true, 
    ),
  );

  /// DEBUG: Fine-grained informational events that are most useful to debug an application.
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// INFO: Informational messages that highlight the progress of the application at coarse-grained level.
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// WARNING: Potentially harmful situations.
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// ERROR: Error events that might still allow the application to continue running.
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// FATAL: Very severe error events that will presumably lead the application to abort.
  static void f(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
}
