import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

class AppConfig {
  static const String smartBoardEmailDomain = 'smartboard.intelliattend.com';

  // ── Production defaults ──────────────────────────────────────────────────
  // Hardcoded so the app works out of the box after a fresh MSI install,
  // even without a .env file or --dart-define flags.  These are the same
  // values the CI injects via secrets / repository variables.
  //
  // NOTE: Firebase Web API keys are NOT secrets — they are designed to be
  // embedded in client applications. Security is enforced by Firebase
  // Security Rules and App Check, not by hiding the API key. See:
  // https://firebase.google.com/docs/projects/api-keys
  static const String _prodBaseUrl = 'https://api.intelliattend.app';
  static const String _prodFirebaseApiKey =
      'AIzaSyBooFadQf3TZFvZOUJkihMUdgexrbeoQnE';
  static const String _prodFirebaseProjectId = 'intelliattend-a2564';
  static const String _prodFirebaseAppId =
      '1:738499328288:web:c345f44de9d8393062ff45';
  static const String _prodFirebaseMessagingSenderId = '738499328288';

  /// Formats a SmartBoard ID into an email for Firebase Auth.
  static String boardIdToEmail(String boardId) => boardId.contains('@')
      ? boardId.toLowerCase()
      : '${boardId.toLowerCase()}@$smartBoardEmailDomain';

  /// Read a value from dotenv first, then fall back to --dart-define.
  static String _env(String key, [String fallback = '']) {
    try {
      final fromDotenv = dotenv.env[key];
      if (fromDotenv != null && fromDotenv.isNotEmpty) return fromDotenv;
    } catch (_) {
      // dotenv may not be initialized if no .env file was found.
    }
    try {
      return String.fromEnvironment(key);
    } catch (_) {
      return fallback;
    }
  }

  /// API base URL — reads from .env / --dart-define first.
  /// In release mode, falls back to the production default so the app
  /// never crashes on a fresh install.  In debug mode, throws so missing
  /// config is caught during development.
  static String get baseUrl {
    final url = _env('API_BASE_URL');
    if (url.isNotEmpty) return url;
    if (kReleaseMode) {
      Log.i('[AppConfig] Using built-in production API URL');
      return _prodBaseUrl;
    }
    throw StateError(
        'API_BASE_URL is not set. Pass it via --dart-define or .env file.');
  }

  /// SSL certificate fingerprint for pinning.
  /// Returns empty string if not set or if using the placeholder value.
  static String get sslFingerprint {
    final pin = _env('SSL_PIN_FINGERPRINT');
    if (pin.isEmpty || pin == 'SSL_PIN_FINGERPRINTrefd') {
      return '';
    }
    return pin;
  }

  /// Debug mode — NEVER enabled in release builds regardless of .env value.
  static bool get isDebug =>
      !kReleaseMode && _env('DEBUG').toLowerCase() == 'true';

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

  /// Firebase config — .env / --dart-define first, production defaults in release.
  static String get firebaseApiKey {
    final v = _env('FIREBASE_API_KEY');
    if (v.isNotEmpty) return v;
    if (kReleaseMode) return _prodFirebaseApiKey;
    return '';
  }

  static String get firebaseProjectId {
    final v = _env('FIREBASE_PROJECT_ID');
    if (v.isNotEmpty) return v;
    if (kReleaseMode) return _prodFirebaseProjectId;
    return '';
  }

  static String get firebaseAppId {
    final v = _env('FIREBASE_APP_ID');
    if (v.isNotEmpty) return v;
    if (kReleaseMode) return _prodFirebaseAppId;
    return '';
  }

  static String get firebaseMessagingSenderId {
    final v = _env('FIREBASE_MESSAGING_SENDER_ID');
    if (v.isNotEmpty) return v;
    if (kReleaseMode) return _prodFirebaseMessagingSenderId;
    return '';
  }

  static void validate() {
    if (baseUrl.isEmpty) {
      Log.w('[AppConfig] API_BASE_URL not set — app will throw at startup.');
    }
    if (firebaseApiKey.isEmpty) {
      Log.w('[AppConfig] FIREBASE_API_KEY not set — auth will fail.');
    }
    if (firebaseAppId.isEmpty) {
      Log.w('[AppConfig] FIREBASE_APP_ID not set — Firebase init may fail.');
    }
    if (firebaseProjectId.isEmpty) {
      Log.w('[AppConfig] FIREBASE_PROJECT_ID not set.');
    }
    if (sslFingerprint.isEmpty) {
      Log.w(
          '[AppConfig] SSL_PIN_FINGERPRINT not set or is placeholder — certificate pinning DISABLED.');
    }
  }
}
