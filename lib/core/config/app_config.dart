import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

class AppConfig {
  static const String smartBoardEmailDomain = 'smartboard.intelliattend.com';

  /// Formats a SmartBoard ID into an email for Firebase Auth.
  static String boardIdToEmail(String boardId) => boardId.contains('@')
      ? boardId.toLowerCase()
      : '${boardId.toLowerCase()}@$smartBoardEmailDomain';

  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ??
      'https://api-dev.balaseetharamanjaneyulu.com';

  static String get sslFingerprint => dotenv.env['SSL_PIN_FINGERPRINT'] ?? '';

  static bool get isDebug => dotenv.env['DEBUG']?.toLowerCase() == 'true';

  static bool get enableVideoBreaks =>
      dotenv.env['ENABLE_VIDEO_BREAKS']?.toLowerCase() == 'true' || false;

  /// Background ambient video URL. Set AMBIENT_VIDEO_URL in .env.
  /// Defaults to Flutter's demo butterfly video if unset.
  static String get ambientVideoUrl =>
      dotenv.env['AMBIENT_VIDEO_URL'] ??
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

  /// Session attendance window in seconds. Set SESSION_WINDOW_SECONDS in .env.
  static int get sessionWindowSeconds =>
      int.tryParse(dotenv.env['SESSION_WINDOW_SECONDS'] ?? '') ?? 300;

  /// Enable document sharing (prototyping mode only).
  /// PDFs open in the built-in pdfrx viewer.
  /// All other file types launch the system default app via url_launcher.
  static bool get enableDocuments =>
      dotenv.env['ENABLE_DOCUMENTS']?.toLowerCase() == 'true' || false;

  /// Maximum cache age for downloaded documents in days.
  static int get documentCacheMaxDays =>
      int.tryParse(dotenv.env['DOCUMENT_CACHE_MAX_DAYS'] ?? '') ?? 7;

  /// Maximum cache size for downloaded documents in MB.
  static int get documentCacheMaxMb =>
      int.tryParse(dotenv.env['DOCUMENT_CACHE_MAX_MB'] ?? '') ?? 200;

  // Firebase REST credentials — used by FirebaseRestAuth (no plugin).
  // The kiosk only ever hits identitytoolkit + securetoken endpoints.
  static String get firebaseApiKey => dotenv.env['FIREBASE_API_KEY'] ?? '';
  static String get firebaseProjectId =>
      dotenv.env['FIREBASE_PROJECT_ID'] ?? '';
  static String get firebaseAppId => dotenv.env['FIREBASE_APP_ID'] ?? '';
  static String get firebaseMessagingSenderId =>
      dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '';

  static void validate() {
    if (dotenv.env['API_BASE_URL'] == null) {
      Log.w(
          '[AppConfig] API_BASE_URL not set in .env. Falling back to default.');
    }
    if (firebaseApiKey.isEmpty) {
      Log.w('[AppConfig] FIREBASE_API_KEY not set in .env — auth will fail.');
    }
    if (firebaseAppId.isEmpty) {
      Log.w(
          '[AppConfig] FIREBASE_APP_ID not set in .env — Firebase init may fail.');
    }
  }
}
