import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

/// Mirrors the exact derivation in idle_screen.dart _deriveSecret.
String deriveFullSecret(String half1, String deviceId) {
  final half2 = Hmac(sha256, utf8.encode(deviceId))
      .convert(utf8.encode(half1))
      .toString()
      .substring(0, 16);
  return '$half1$half2';
}

/// Mirrors the exact QR generation in totp_engine.dart _generateNextToken (v7.0).
/// Produces: IATT::<Base64URL( sidHash(6) + timestampSec(4) + nonce(2) + hmac(8) )>
String generateQrToken(
    String sessionId, String secret, int timestampSec, List<int> nonce) {
  final sidHash = sha256.convert(utf8.encode(sessionId)).bytes.take(6).toList();
  final tsBytes = ByteData(4)..setUint32(0, timestampSec, Endian.big);
  final header = <int>[
    ...sidHash,
    ...tsBytes.buffer.asUint8List(),
    ...nonce,
  ];
  final keyBytes = utf8.encode(secret);
  final hmacBytes = Hmac(sha256, keyBytes).convert(header).bytes.take(8).toList();
  final payloadBytes = <int>[...header, ...hmacBytes];
  final b64url = base64Url.encode(payloadBytes).replaceAll('=', '');
  return 'IATT::$b64url';
}

/// Decodes a token, returning the 20 raw bytes. Returns null on failure.
List<int>? decodeToken(String token) {
  const prefix = 'IATT::';
  if (!token.startsWith(prefix)) return null;
  try {
    var b64 = token.substring(prefix.length);
    // Restore padding stripped during encoding (Dart decoder requires multiple of 4).
    while (b64.length % 4 != 0) b64 += '=';
    return base64Url.decode(b64);
  } catch (_) {
    return null;
  }
}

/// Validates a token against the given full secret.
bool validateQrToken(String token, String fullSecret) {
  final raw = decodeToken(token);
  if (raw == null || raw.length != 20) return false;
  final header = raw.take(12).toList();
  final providedHmac = raw.skip(12).toList();
  final expectedHmac = Hmac(sha256, utf8.encode(fullSecret))
      .convert(header).bytes.take(8).toList();
  return _listEquals(providedHmac, expectedHmac);
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('SmartBoard Binary QR v7.0', () {
    const String testSessionId = 'sess_999';
    const String testSecret = 'secret_abc';
    const int testTimestamp = 1711881234; // seconds
    final List<int> testNonce = [0xAB, 0xCD];

    test('Token format: IATT::<Base64URL> — 33 chars total', () {
      final token = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      expect(token.startsWith('IATT::'), isTrue);
      expect(token.length, equals(33)); // IATT:: (6) + Base64URL (27)
    });

    test('Token decodes to exactly 20 raw bytes', () {
      final token = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      final raw = decodeToken(token);
      expect(raw, isNotNull);
      expect(raw!.length, equals(20));
    });

    test('First 6 bytes = SHA256(sessionId)[0..5]', () {
      final expectedHash = sha256.convert(utf8.encode(testSessionId)).bytes.take(6).toList();
      final token = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      final raw = decodeToken(token)!;
      final sidHash = raw.take(6).toList();
      expect(sidHash, equals(expectedHash));
    });

    test('Bytes 6-9 = timestamp as uint32 BE', () {
      final token = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      final raw = decodeToken(token)!;
      final tsBytes = raw.sublist(6, 10);
      final decoded = ByteData(4)..buffer.asUint8List().setAll(0, tsBytes);
      expect(decoded.getUint32(0, Endian.big), equals(testTimestamp));
    });

    test('Bytes 10-11 = nonce bytes', () {
      final token = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      final raw = decodeToken(token)!;
      final nonceBytes = raw.sublist(10, 12);
      expect(nonceBytes, equals(testNonce));
    });

    test('Bytes 12-19 = HMAC-SHA256(secret, header)[0..7]', () {
      final token = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      final raw = decodeToken(token)!;
      final header = raw.take(12).toList();
      final providedHmac = raw.skip(12).toList();
      final expectedHmac = Hmac(sha256, utf8.encode(testSecret))
          .convert(header).bytes.take(8).toList();
      expect(providedHmac, equals(expectedHmac));
    });

    test('Timestamp second precision changes the token', () {
      final token1 = generateQrToken(testSessionId, testSecret, 1711881234, testNonce);
      final token2 = generateQrToken(testSessionId, testSecret, 1711881235, testNonce);
      expect(token1, isNot(equals(token2)));
    });

    test('Nonce changes the token (anti-replay)', () {
      final token1 = generateQrToken(testSessionId, testSecret, testTimestamp, [0x00, 0x00]);
      final token2 = generateQrToken(testSessionId, testSecret, testTimestamp, [0xFF, 0xFF]);
      expect(token1, isNot(equals(token2)));
    });

    test('Deterministic for fixed inputs', () {
      final token1 = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      final token2 = generateQrToken(testSessionId, testSecret, testTimestamp, testNonce);
      expect(token1, equals(token2));
    });
  });

  group('Split-Knowledge: Secret Binding (v7.0)', () {
    const String half1 = 'dGhpcyBpcyBhIHRlc3QgaGFsZg';
    const String deviceId = 'AA:BB:CC:DD:EE:FF';
    final String fullSecret = deriveFullSecret(half1, deviceId);
    const String sessionId = '38008fafa1199767a148';
    const int timestampSec = 1711881234;
    final List<int> nonce = [0x12, 0x34];

    test('QR token HMAC key is the DERIVED full secret (half1 + half2)', () {
      final token = generateQrToken(sessionId, fullSecret, timestampSec, nonce);
      expect(validateQrToken(token, fullSecret), isTrue);
    });

    test('Server CAN validate a QR with reconstructed full_secret', () {
      final token = generateQrToken(sessionId, fullSecret, timestampSec, nonce);
      final serverSecret = deriveFullSecret(half1, deviceId);
      expect(validateQrToken(token, serverSecret), isTrue);
    });

    test('Server CANNOT validate with half1-only (missing half2 derivation)', () {
      final token = generateQrToken(sessionId, fullSecret, timestampSec, nonce);
      // half1-only should produce a different HMAC
      final raw = decodeToken(token)!;
      final header = raw.take(12).toList();
      final half1OnlyHmac = Hmac(sha256, utf8.encode(half1))
          .convert(header).bytes.take(8).toList();
      final tokenHmac = raw.skip(12).toList();
      expect(tokenHmac, isNot(equals(half1OnlyHmac)));
    });
  });
}
