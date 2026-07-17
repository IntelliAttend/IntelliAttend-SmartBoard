import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

class SslPinningService {
  static http.Client? _instance;

  static const Duration _connectionTimeout = Duration(seconds: 30);
  static const Duration _idleTimeout = Duration(seconds: 30);

  static http.Client get client {
    _instance ??= _create();
    return _instance!;
  }

  static http.Client _create() {
    final fingerprint = AppConfig.sslFingerprint;

    if (fingerprint.isEmpty) {
      Log.w(
          '[SSL] SSL_PIN_FINGERPRINT not set. Certificate pinning disabled.');
    }

    final inner = HttpClient()
      ..connectionTimeout = _connectionTimeout
      ..idleTimeout = _idleTimeout;

    if (fingerprint.isNotEmpty) {
      inner.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
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
      Log.i(
          '🔒 [SSL] Pinning enabled (fingerprint: ${fingerprint.substring(0, 8)}…).');
    }

    return IOClient(inner);
  }
}
