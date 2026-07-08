import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

class AppConfig {
  static const String smartBoardEmailDomain = 'smartboard.intelliattend.com';

  /// Formats a SmartBoard ID into an email for Firebase Auth.
  static String boardIdToEmail(String boardId) => boardId.contains('@')
      ? boardId.toLowerCase()
      : '${boardId.toLowerCase()}@$smartBoardEmailDomain';

  /// Read a value from dotenv first, then fall back to --dart-define.
  static String _env(String key, [String fallback = '']) {
    final fromDotenv = dotenv.env[key];
    if (fromDotenv != null && fromDotenv.isNotEmpty) return fromDotenv;
    try {
      return const String.fromEnvironment(key);
    } catch (_) {
      return fallback;
    }
  }

  static String get baseUrl {
    final url = _env('API_BASE_URL');
    return url.isNotEmpty
        ? url
        : 'https://api-dev.balaseetharamanjaneyulu.com';
  }

  static String get sslFingerprint => _env('SSL_PIN_FINGERPRINT');

  static bool get isDebug => _env('DEBUG').toLowerCase() == 'true';

  static bool get enableVideoBreaks =>
      _env('ENABLE_VIDEO_BREAKS').toLowerCase() == 'true';

  /// Background ambient video URL. Set AMBIENT_VIDEO_URL in .env.
  /// Defaults to Flutter's demo butterfly video if unset.
  static String get ambientVideoUrl {
    final url = _env('AMBIENT_VIDEO_URL');
    return url.isNotEmpty
        ? url
        : 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
  }

  /// Session attendance window in seconds. Set SESSION_WINDOW_SECONDS in .env.
  static int get sessionWindowSeconds =>
      int.tryParse(_env('SESSION_WINDOW_SECONDS')) ?? 300;

  /// Enable document sharing (prototyping mode only).
  static bool get enableDocuments =>
      _env('ENABLE_DOCUMENTS').toLowerCase() == 'true';

  /// Maximum cache age for downloaded documents in days.
  static int get documentCacheMaxDays =>
      int.tryParse(_env('DOCUMENT_CACHE_MAX_DAYS')) ?? 7;

  /// Maximum cache size for downloaded documents in MB.
  static int get documentCacheMaxMb =>
      int.tryParse(_env('DOCUMENT_CACHE_MAX_MB')) ?? 200;

  static String get firebaseApiKey => _env('FIREBASE_API_KEY');
  static String get firebaseProjectId => _env('FIREBASE_PROJECT_ID');
  static String get firebaseAppId => _env('FIREBASE_APP_ID');
  static String get firebaseMessagingSenderId =>
      _env('FIREBASE_MESSAGING_SENDER_ID');

  static void validate() {
    if (_env('API_BASE_URL').isEmpty) {
      Log.w(
          '[AppConfig] API_BASE_URL not set. Falling back to default.');
    }
    if (firebaseApiKey.isEmpty) {
      Log.w('[AppConfig] FIREBASE_API_KEY not set — auth will fail.');
    }
    if (firebaseAppId.isEmpty) {
      Log.w(
          '[AppConfig] FIREBASE_APP_ID not set — Firebase init may fail.');
    }
    if (firebaseProjectId.isEmpty) {
      Log.w('[AppConfig] FIREBASE_PROJECT_ID not set.');
    }
    if (sslFingerprint.isEmpty) {
      Log.w(
          '[AppConfig] SSL_PIN_FINGERPRINT not set — certificate pinning disabled.');
    }
  }
}
