import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get baseUrl => dotenv.env['API_BASE_URL'] ?? 'https://api-dev.balaseetharamanjaneyulu.com';
  
  static String get sslFingerprint => dotenv.env['SSL_PIN_FINGERPRINT'] ?? '';
  
  static String get localApiUrl => dotenv.env['LOCAL_API_URL'] ?? 'http://127.0.0.1:8000/v1/board/telemetry';

  static bool get isDebug => dotenv.env['DEBUG']?.toLowerCase() == 'true';

  static bool get enableVideoBreaks => dotenv.env['ENABLE_VIDEO_BREAKS']?.toLowerCase() == 'true' || false;

  /// QR Attendance countdown window in seconds. Set OTP_ROTATION_WINDOW_SECONDS in .env.
  static int get otpRotationWindowSeconds =>
      int.tryParse(dotenv.env['OTP_ROTATION_WINDOW_SECONDS'] ?? '') ?? 300;

  static void validate() {
    if (dotenv.env['API_BASE_URL'] == null) {
      print('⚠️ [AppConfig] API_BASE_URL not set in .env. Falling back to default.');
    }
  }
}
