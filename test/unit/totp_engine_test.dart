
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

const String _redirectPrefix = 'https://balaseetharamanjaneyulu.com/?payload=';

/// Mirrors the exact derivation in idle_screen.dart _deriveSecret.
String deriveFullSecret(String half1, String deviceId) {
  final half2 = Hmac(sha256, utf8.encode(deviceId))
      .convert(utf8.encode(half1))
      .toString()
      .substring(0, 16);
  return '$half1$half2';
}

/// Strips the redirect URL wrapper if present, returning the core IATT token.
String unwrapToken(String token) {
  if (token.startsWith(_redirectPrefix)) {
    return token.substring(_redirectPrefix.length);
  }
  return token;
}

/// Mirrors the exact QR generation in totp_engine.dart _generateNextToken (v6.0).
/// Includes the nonce field which was added in v6.0.
String generateQrToken(
    String sessionId, String secret, int timestampMs, String nonce) {
  final String dataString = '$sessionId|$timestampMs|$nonce';
  final String base64Payload = base64.encode(utf8.encode(dataString));
  final List<int> keyBytes = utf8.encode(secret);
  final List<int> messageBytes = utf8.encode(base64Payload);
  final hmac = Hmac(sha256, keyBytes);
  final String signatureHex = hmac.convert(messageBytes).toString().substring(0, 16);
  return 'IATT::$base64Payload::$signatureHex';
}

void main() {
  group('SmartBoard Golden Contract v5.4', () {
    const String testSessionId = 'sess_999';
    const String testSecret = 'secret_abc';
    const int testTimestamp = 1711881234000;
    const String testNonce = 'xYz9';

    test('Token format: IATT::<base64>::<16-char-hex>', () {
      final String token = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      
      final parts = token.split('::');
      expect(parts.length, equals(3));
      expect(parts[0], equals('IATT'));
      expect(parts[2].length, equals(16)); // truncated HMAC, not full 64-char SHA256
      expect(parts[2], matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('Payload decodes to session_id|timestamp_ms|nonce', () {
      final String token = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      final String base64Part = token.split('::')[1];
      
      final String decoded = utf8.decode(base64.decode(base64Part));
      expect(decoded, equals('$testSessionId|$testTimestamp|$testNonce'));
    });

    test('Timestamp millisecond precision changes the token', () {
      final String token1 = generateQrToken(testSessionId, testSecret, 1711881234000, testNonce);
      final String token2 = generateQrToken(testSessionId, testSecret, 1711881234001, testNonce);
      
      expect(token1, isNot(equals(token2)));
    });

    test('Nonce changes the token (anti-replay)', () {
      final String token1 = generateQrToken(testSessionId, testSecret, testTimestamp, 'AAAA');
      final String token2 = generateQrToken(testSessionId, testSecret, testTimestamp, 'BBBB');

      expect(token1, isNot(equals(token2)));
    });

    test('Deterministic for fixed inputs', () {
      final String token1 = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      final String token2 = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);

      expect(token1, equals(token2));
    });
  });

  group('Split-Knowledge: Secret Binding (v6.2)', () {
    // Known server-provided half1 and board hardware ID
    const String half1 = 'dGhpcyBpcyBhIHRlc3QgaGFsZg';
    const String deviceId = 'AA:BB:CC:DD:EE:FF';
    final String fullSecret = deriveFullSecret(half1, deviceId);
    const String sessionId = '38008fafa1199767a148';
    const int timestampMs = 1711881234000;
    const String nonce = 'xYz9';

    test('QR token HMAC key is the DERIVED full secret (half1 + half2)', () {
      // Board derives full_secret, generates QR
      final token = generateQrToken(sessionId, fullSecret, timestampMs, nonce);
      final parts = token.split('::');

      // Server reconstructs: hash full_secret against base64 payload
      final keyBytes = utf8.encode(fullSecret);
      final messageBytes = utf8.encode(parts[1]);
      final expectedSig = Hmac(sha256, keyBytes)
          .convert(messageBytes)
          .toString()
          .substring(0, 16);

      expect(parts[2], equals(expectedSig));
    });

    test('Server CAN validate a QR with reconstructed full_secret', () {
      // Board side
      final token = generateQrToken(sessionId, fullSecret, timestampMs, nonce);

      // Server side (same derivation from half1 + deviceId)
      final serverSecret = deriveFullSecret(half1, deviceId);
      final parts = token.split('::');
      final keyBytes = utf8.encode(serverSecret);
      final messageBytes = utf8.encode(parts[1]);
      final expectedSig = Hmac(sha256, keyBytes)
          .convert(messageBytes)
          .toString()
          .substring(0, 16);

      expect(parts[2], equals(expectedSig));
    });

    test('Server CANNOT validate with half1-only (missing half2 derivation)', () {
      // Board generates QR using the REAL derived full_secret
      final token = generateQrToken(sessionId, fullSecret, timestampMs, nonce);

      // Server tries to validate using half1-only (no deviceId to derive half2)
      // This simulates a server that doesn't have the deviceId in Redis
      final parts = token.split('::');
      final keyBytes = utf8.encode(half1); // half1-only, NOT the full secret
      final messageBytes = utf8.encode(parts[1]);
      final half1OnlySig = Hmac(sha256, keyBytes)
          .convert(messageBytes)
          .toString()
          .substring(0, 16);

      // half1-only signature does NOT match the real HMAC key (full secret)
      expect(parts[2], isNot(equals(half1OnlySig)));
    });
  });
}
