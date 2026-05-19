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

  static String get localApiUrl =>
      dotenv.env['LOCAL_API_URL'] ?? 'http://127.0.0.1:8000/v1/board/telemetry';

  static bool get isDebug => dotenv.env['DEBUG']?.toLowerCase() == 'true';

  static bool get enableVideoBreaks =>
      dotenv.env['ENABLE_VIDEO_BREAKS']?.toLowerCase() == 'true' || false;

  /// QR Attendance countdown window in seconds. Set OTP_ROTATION_WINDOW_SECONDS in .env.
  static int get otpRotationWindowSeconds =>
      int.tryParse(dotenv.env['OTP_ROTATION_WINDOW_SECONDS'] ?? '') ?? 300;

  /// QR code generation interval in milliseconds. Set QR_ROTATION_FREQUENCY_MS in .env.
  static int get qrRotationFrequencyMs =>
      int.tryParse(dotenv.env['QR_ROTATION_FREQUENCY_MS'] ?? '') ?? 5000;

  // Firebase REST credentials — used by FirebaseRestAuth (no plugin).
  // The kiosk only ever hits identitytoolkit + securetoken endpoints.
  static String get firebaseApiKey => dotenv.env['FIREBASE_API_KEY'] ?? '';
  static String get firebaseProjectId =>
      dotenv.env['FIREBASE_PROJECT_ID'] ?? '';

  static void validate() {
    if (dotenv.env['API_BASE_URL'] == null) {
      Log.w(
          '[AppConfig] API_BASE_URL not set in .env. Falling back to default.');
    }
    if (firebaseApiKey.isEmpty) {
      Log.w('[AppConfig] FIREBASE_API_KEY not set in .env — auth will fail.');
    }
  }
}
