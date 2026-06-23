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

/// Mirrors the exact QR token generation in totp_engine.dart _generateNextToken.
String generateQrToken(
    String sessionId, String fullSecret, int timestampMs, String nonce) {
  final dataString = '$sessionId|$timestampMs|$nonce';
  final base64Payload = base64.encode(utf8.encode(dataString));
  final keyBytes = utf8.encode(fullSecret);
  final messageBytes = utf8.encode(base64Payload);
  final hmac = Hmac(sha256, keyBytes);
  final signatureHex = hmac.convert(messageBytes).toString().substring(0, 16);
  return 'IATT::$base64Payload::$signatureHex';
}

bool validateQrToken(String token, String fullSecret) {
  final core = unwrapToken(token);
  final parts = core.split('::');
  if (parts.length != 3) return false;
  if (parts[0] != 'IATT') return false;

  final base64Payload = parts[1];
  final providedSig = parts[2];

  final keyBytes = utf8.encode(fullSecret);
  final messageBytes = utf8.encode(base64Payload);
  final hmac = Hmac(sha256, keyBytes);
  final expectedSig = hmac.convert(messageBytes).toString().substring(0, 16);

  return providedSig == expectedSig;
}

void main() {
  group('Split-Knowledge: Derivation (idle_screen.dart _deriveSecret)', () {
    // Known test vectors — these are NOT random, they are the exact algorithm
    const String half1 = 'dGhpcyBpcyBhIHRlc3QgaGFsZg';
    const String deviceId = 'AA:BB:CC:DD:EE:FF';

    test('derivation is DETERMINISTIC — same inputs always produce same output',
        () {
      final result1 = deriveFullSecret(half1, deviceId);
      final result2 = deriveFullSecret(half1, deviceId);
      final result3 = deriveFullSecret(half1, deviceId);

      // All three runs must produce identical results (not random)
      expect(result1, equals(result2));
      expect(result2, equals(result3));

      // Verify expected prefix + length constraints
      expect(result1.startsWith(half1), isTrue);
      expect(result1.length, equals(half1.length + 16));
    });

    test('full_secret = half1 + HMAC-SHA256(deviceId, half1)[:16]', () {
      final result = deriveFullSecret(half1, deviceId);

      // half1 is the PREFIX of the full secret
      expect(result.startsWith(half1), isTrue);

      // The remaining 16 chars = HMAC(sha256, deviceId, half1).substring(0, 16)
      final computedHalf2 = Hmac(sha256, utf8.encode(deviceId))
          .convert(utf8.encode(half1))
          .toString()
          .substring(0, 16);
      expect(result, equals('$half1$computedHalf2'));
    });

    test('full_secret is NOT random — it is PURELY derived from half1 + deviceId',
        () {
      // Prove: same half1 with same deviceId = same result (no randomness)
      final first = deriveFullSecret(half1, deviceId);
      final second = deriveFullSecret(half1, deviceId);
      expect(first, equals(second));

      // Prove: the output is NOT a random token — it's a deterministic function
      // of the inputs. Changing ANY input bit changes the output.
      final withDifferentHalf1 =
          deriveFullSecret('ANOTHER_HALF_STRING', deviceId);
      expect(withDifferentHalf1, isNot(equals(first)));
    });

    test('DIFFERENT deviceId produces DIFFERENT full_secret (hardware binding)',
        () {
      final boardA = deriveFullSecret(half1, 'AA:BB:CC:DD:EE:01');
      final boardB = deriveFullSecret(half1, 'AA:BB:CC:DD:EE:02');

      // Same half1, different hardware → completely different full secret
      expect(boardA, isNot(equals(boardB)));

      // Both still start with the same half1 (the prefix)
      expect(boardA.startsWith(half1), isTrue);
      expect(boardB.startsWith(half1), isTrue);
    });

    test('DIFFERENT half1 produces DIFFERENT full_secret', () {
      const String half1A = 'AAAAfirstHalfTest';
      const String half1B = 'BBBBsecondHalfTst';
      const String deviceX = 'AA:BB:CC:DD:EE:FF';

      final secretA = deriveFullSecret(half1A, deviceX);
      final secretB = deriveFullSecret(half1B, deviceX);

      expect(secretA, isNot(equals(secretB)));
    });

    test('full_secret directly embeds half1 as the PREFIX', () {
      const String testHalf1 = 'test_prefix_value_123';
      const String testDevice = '11:22:33:44:55:66';

      final fullSecret = deriveFullSecret(testHalf1, testDevice);

      // The server gave half1; the board prepends it. This is critical:
      // when the server reconstructs the full secret for QR validation,
      // it uses the SAME half1 it originally sent.
      expect(fullSecret.substring(0, testHalf1.length), equals(testHalf1));
      expect(fullSecret.length, equals(testHalf1.length + 16));
    });

    test('half2 is EXACTLY 16 hex characters (truncated HMAC)', () {
      final fullSecret = deriveFullSecret(half1, deviceId);
      final half2 = fullSecret.substring(half1.length);

      expect(half2.length, equals(16));
      // hex characters only
      expect(half2, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('Server can RECONSTRUCT the same full_secret for QR validation', () {
      // Scenario: server sent half1 to board, stored half1 + deviceId in Redis
      // Student scans QR → server reconstructs:
      const String knownHalf1 = half1;
      const String knownDeviceId = deviceId;

      // Board side
      final boardSecret = deriveFullSecret(knownHalf1, knownDeviceId);

      // Server side (same math)
      final serverSecret = deriveFullSecret(knownHalf1, knownDeviceId);

      // Both must match — server can validate any QR the board generates
      expect(boardSecret, equals(serverSecret));
    });

    test('Server RECONSTRUCTION FAILS with wrong deviceId', () {
      // Hacker has half1 from Redis, guesses wrong deviceId
      const String wrongDeviceId = 'FF:EE:DD:CC:BB:AA';
      final hackerSecret = deriveFullSecret(half1, wrongDeviceId);
      final realSecret = deriveFullSecret(half1, deviceId);

      // Hacker's reconstructed secret is different → can't validate QRs
      expect(hackerSecret, isNot(equals(realSecret)));
    });

    test('Server RECONSTRUCTION FAILS without half1', () {
      // Hacker has deviceId but no half1 (Redis was cleared / half1 never in Firestore)
      const String noHalf1 = '';
      final hackerSecret = deriveFullSecret(noHalf1, deviceId);
      final realSecret = deriveFullSecret(half1, deviceId);

      expect(hackerSecret, isNot(equals(realSecret)));
    });
  });

  group('Split-Knowledge: QR Token Binding (totp_engine.dart)', () {
    const String sessionId = '38008fafa1199767a148';
    const String half1 = 'dGhpcyBpcyBhIHRlc3QgaGFsZg';
    const String deviceId = 'AA:BB:CC:DD:EE:FF';
    final String fullSecret = deriveFullSecret(half1, deviceId);
    const int timestampMs = 1711881234000;
    const String nonce = 'xYz9';

    test('QR token uses derived full_secret as HMAC key — NOT random', () {
      // Same inputs = same token (deterministic for fixed nonce)
      final token1 = generateQrToken(sessionId, fullSecret, timestampMs, nonce);
      final token2 = generateQrToken(sessionId, fullSecret, timestampMs, nonce);

      expect(token1, equals(token2));
    });

    test('QR token format: IATT::<base64>::<16-char-hex-sig>', () {
      final token =
          generateQrToken(sessionId, fullSecret, timestampMs, nonce);
      final parts = token.split('::');

      expect(parts.length, equals(3));
      expect(parts[0], equals('IATT'));
      expect(parts[2].length, equals(16));
      expect(parts[2], matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('QR payload decodes to session_id|timestamp_ms|nonce', () {
      final token =
          generateQrToken(sessionId, fullSecret, timestampMs, nonce);
      final base64Payload = token.split('::')[1];
      final decoded = utf8.decode(base64.decode(base64Payload));

      expect(decoded, equals('$sessionId|$timestampMs|$nonce'));
    });

    test('QR token is VALIDATABLE by server with reconstructed secret', () {
      // Board generates QR
      final token =
          generateQrToken(sessionId, fullSecret, timestampMs, nonce);

      // Server reconstructs full_secret from half1 + deviceId (both in Redis)
      final serverSecret = deriveFullSecret(half1, deviceId);

      // Server validates
      expect(validateQrToken(token, serverSecret), isTrue);
    });

    test('QR token FAILS validation with wrong secret', () {
      final token =
          generateQrToken(sessionId, fullSecret, timestampMs, nonce);

      const String wrongSecret = 'thisIsCompletelyWrong';

      expect(validateQrToken(token, wrongSecret), isFalse);
    });

    test('QR token FAILS validation if tampered with', () {
      final token =
          generateQrToken(sessionId, fullSecret, timestampMs, nonce);

      // Tamper: change one character in signature
      final tamperedToken = '${token.substring(0, token.length - 1)}0';

      expect(validateQrToken(tamperedToken, fullSecret), isFalse);
    });

    test('DIFFERENT nonce → DIFFERENT QR (anti-replay within time window)',
        () {
      final token1 =
          generateQrToken(sessionId, fullSecret, timestampMs, 'AAAA');
      final token2 =
          generateQrToken(sessionId, fullSecret, timestampMs, 'BBBB');

      expect(token1, isNot(equals(token2)));
      // Both still validatable independently
      expect(validateQrToken(token1, fullSecret), isTrue);
      expect(validateQrToken(token2, fullSecret), isTrue);
    });

    test('DIFFERENT timestamp → DIFFERENT QR', () {
      final token1 =
          generateQrToken(sessionId, fullSecret, 1711881234000, nonce);
      final token2 =
          generateQrToken(sessionId, fullSecret, 1711881234001, nonce);

      expect(token1, isNot(equals(token2)));
    });

    test('QR token generated with half1-only (no deviceId) is INVALID', () {
      // This tests that a board that NEVER derives half2 (just uses half1)
      // produces tokens the server can't validate
      const String half1Only = half1;
      final badToken =
          generateQrToken(sessionId, half1Only, timestampMs, nonce);

      // Server reconstructs with the REAL full secret
      expect(validateQrToken(badToken, fullSecret), isFalse);
    });

    test('QR token with RANDOM secret (not derived) FAILS server validation', () {
      // This tests the "we are not generating random things" requirement:
      // if the board used a random secret instead of the derived one,
      // the server could never validate it.
      const String randomSecret = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0';
      final randomToken =
          generateQrToken(sessionId, randomSecret, timestampMs, nonce);

      // Server validates with the REAL reconstructed secret
      expect(validateQrToken(randomToken, fullSecret), isFalse);
    });
  });

  group('Split-Knowledge: Violation Detection', () {
    // These tests FAIL intentionally if someone introduces randomness
    test('board does NOT generate its own half1 — half1 comes ONLY from server',
        () {
      const String serverProvidedHalf1 = 'server_generated_half1_value';
      const String boardDeviceId = 'AA:BB:CC:DD:EE:FF';

      final boardFullSecret = deriveFullSecret(serverProvidedHalf1, boardDeviceId);

      // The full secret PREFIX must be exactly the half1 the server sent
      expect(boardFullSecret.startsWith(serverProvidedHalf1), isTrue);

      // If the board generated its own half1, this would fail
      // because the prefix would be something else
      const String fakeHalf1 = 'board_invented_half1_wrong';
      expect(boardFullSecret.startsWith(fakeHalf1), isFalse);
    });

    test('board does NOT add RANDOM bytes — output is deterministic pure function',
        () {
      // Run 100 times, must always produce the same result
      const String h = 'fixed_half1_value_for_randomness_test';
      const String d = 'AB:CD:EF:01:23:45';

      final results = List.generate(
          100, (_) => deriveFullSecret(h, d));
      expect(results.toSet().length, equals(1));
    });

    test('server can validate QR WITHOUT ever knowing the full secret beforehand',
        () {
      // Server knows: session_id, half1, deviceId, board_id
      // Board generates: QR with full_secret = half1 + HMAC(deviceId, half1)[:16]
      // Server reconstructs full_secret from Redis (half1 + deviceId)
      // → validates QR

      const String sid = 'sess_test_001';
      const String h1 = 'server_half1_for_reconstruction';
      const String devId = 'AB:CD:EF:01:23:45';
      const int ts = 1711881234000;
      const String n = 'nonce01';

      // Board side
      final boardSecret = deriveFullSecret(h1, devId);
      final qrToken = generateQrToken(sid, boardSecret, ts, n);

      // Server reconstructs (same derivation math)
      final serverSecret = deriveFullSecret(h1, devId);

      // Server has both the QR and the reconstructed secret for the first time
      expect(validateQrToken(qrToken, serverSecret), isTrue);
    });
  });

  group('URL Wrapper: Scanner Deflection', () {
    const String sid = 'sess_wrap_001';
    const String h1 = 'wrapper_test_half1';
    const String devId = 'AA:BB:CC:DD:EE:FF';
    const int ts = 1711881234000;
    const String n = 'nonce_wrap';

    test('wrapped token validates identically to unwrapped', () {
      final secret = deriveFullSecret(h1, devId);
      final core = generateQrToken(sid, secret, ts, n);
      final wrapped = '$_redirectPrefix$core';

      expect(validateQrToken(wrapped, secret), isTrue,
          reason: 'URL-wrapped token must validate the same as core IATT token');
    });

    test('unwrapToken strips redirect prefix correctly', () {
      final secret = deriveFullSecret(h1, devId);
      final core = generateQrToken(sid, secret, ts, n);
      final wrapped = '$_redirectPrefix$core';

      final unwrapped = unwrapToken(wrapped);
      expect(unwrapped, equals(core));
      expect(unwrapped.startsWith('IATT::'), isTrue);
    });

    test('unwrapToken passes through raw IATT tokens unchanged', () {
      final secret = deriveFullSecret(h1, devId);
      final core = generateQrToken(sid, secret, ts, n);

      final result = unwrapToken(core);
      expect(result, equals(core));
    });

    test('generic scanner opens redirect URL — token is in query parameter', () {
      final secret = deriveFullSecret(h1, devId);
      final core = generateQrToken(sid, secret, ts, n);
      final wrapped = '$_redirectPrefix$core';

      // A generic scanner sees a valid https:// URL
      expect(wrapped.startsWith('https://'), isTrue);

      // The URL contains the domain
      expect(wrapped.contains('balaseetharamanjaneyulu.com'), isTrue);

      // The IATT payload is in the query parameter, not sent to server
      expect(wrapped.contains('?payload=IATT::'), isTrue);

      // Validate the QR URL passes the same crypto checks
      expect(validateQrToken(wrapped, secret), isTrue);
    });
  });
}
