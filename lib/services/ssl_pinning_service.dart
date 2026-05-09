import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../core/utils/logger.dart';

/// v5.8: HTTP client with configurable SSL pinning + mandatory timeouts.
///
/// Changes from v5.7:
///   - Added 30s connection timeout (prevents indefinite hangs when backend is slow)
///   - Added 30s idle timeout (releases resources on stalled connections)
///   - Both pinning and non-pinning paths now use the same HttpClient base,
///     ensuring timeout behavior is identical regardless of SSL_PIN_FINGERPRINT.
///
/// Why timeouts are critical (AUDIT-2.3):
///   Without them, a single slow backend response can freeze the entire
///   SmartBoard UI indefinitely. 30s is generous for API calls on a
///   local/regional network and gives the retry interceptor time to fire.
class SslPinningService {
  static http.Client? _instance;

  static const Duration _connectionTimeout = Duration(seconds: 30);
  static const Duration _idleTimeout = Duration(seconds: 30);

  static http.Client get client {
    _instance ??= _create();
    return _instance!;
  }

  static http.Client _create() {
    final fingerprint = dotenv.env['SSL_PIN_FINGERPRINT'];

    final inner = HttpClient()
      ..connectionTimeout = _connectionTimeout
      ..idleTimeout = _idleTimeout;

    if (fingerprint != null && fingerprint.isNotEmpty) {
      inner.badCertificateCallback = (X509Certificate cert, String host, int port) {
        try {
          final digest = sha256.convert(cert.der);
          if (digest.toString() == fingerprint) return true;
        } catch (_) {
          final digest = sha1.convert(cert.sha1);
          if (digest.toString() == fingerprint) return true;
        }
        Log.e('❌ [SSL] Certificate pinning failed for $host');
        return false;
      };
      Log.i('🔒 [SSL] Pinning enabled (fingerprint: ${fingerprint.substring(0, 8)}…).');
    } else {
      Log.w('⚠️ [SSL] SSL_PIN_FINGERPRINT not set. Set it in .env for production.');
    }

    return IOClient(inner);
  }
}
