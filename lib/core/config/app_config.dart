import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

/// Centralized configuration manager for IntelliAttend.
/// Handles environment variables and validates system requirements.
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  /// The Cloud API Gateway URL
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'https://api-dev.balaseetharamanjaneyulu.com';

  /// The Local "Brain" API URL
  static String get localApiUrl => dotenv.env['LOCAL_API_URL'] ?? 'http://127.0.0.1:8000/v1/board/telemetry';

  /// Validates that all required environment variables are present.
  /// Throws an [Exception] if critical configuration is missing.
  static void validate() {
    Log.i('🔍 [AppConfig] Validating environment configuration...');
    
    final requiredKeys = [
      'API_BASE_URL',
      'LOCAL_API_URL',
    ];

    List<String> missingKeys = [];
    for (var key in requiredKeys) {
      if (!dotenv.env.containsKey(key) || dotenv.env[key]!.isEmpty) {
        missingKeys.add(key);
      }
    }

    if (missingKeys.isNotEmpty) {
      final error = '❌ CRITICAL CONFIG MISSING: ${missingKeys.join(", ")}';
      Log.e(error);
      throw Exception(error);
    }

    Log.i('✅ [AppConfig] Environment validation successful.');
    Log.d('📡 Cloud URL: ${apiBaseUrl}');
    Log.d('🏠 Local URL: ${localApiUrl}');
  }
}
