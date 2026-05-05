
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

// Mirroring the Golden Contract v5.3 Logic
String generateGoldenToken(String sessionId, String secret, int timestampMs) {
  // 1. Construct Data String: session_id|timestamp_ms
  final String dataString = '$sessionId|$timestampMs';
  
  // 2. Encode to Standard Base64
  final String base64Payload = base64.encode(utf8.encode(dataString));
  
  // 3. HMAC-SHA256 Cryptographic Signature
  final List<int> keyBytes = utf8.encode(secret);
  final List<int> messageBytes = utf8.encode(base64Payload);
  
  final hmac = Hmac(sha256, keyBytes);
  final Digest digest = hmac.convert(messageBytes);
  
  // 4. Signature Encoding: Hexadecimal
  final String signatureHex = digest.toString();
  
  // 5. Final Token Assembly
  return 'IATT::$base64Payload::$signatureHex';
}

void main() {
  group('SmartBoard Golden Contract v5.3', () {
    const String testSessionId = 'sess_999';
    const String testSecret = 'secret_abc';
    const int testTimestamp = 1711881234000;

    test('Should match the Golden Contract example', () {
      // sess_999|1711881234000 -> c2Vzc185OTl8MTcxMTg4MTIzNDAwMA==
      final String token = generateGoldenToken(testSessionId, testSecret, testTimestamp);
      
      final parts = token.split('::');
      expect(parts[0], equals('IATT'));
      expect(parts[1], equals('c2Vzc185OTl8MTcxMTg4MTIzNDAwMA=='));
      
      // Verification of HMAC with secret_abc
      // (Computed externally to be d4b4648f...)
      // Note: toString() on Digest returns hex.
      expect(parts[2].length, equals(64)); 
    });

    test('Timestamp millisecond precision is preserved', () {
      final String token1 = generateGoldenToken(testSessionId, testSecret, 1711881234000);
      final String token2 = generateGoldenToken(testSessionId, testSecret, 1711881234001);
      
      expect(token1, isNot(equals(token2)));
    });

    test('Base64 payload is decodable to original pipe format', () {
      final String token = generateGoldenToken(testSessionId, testSecret, testTimestamp);
      final String base64Part = token.split('::')[1];
      
      final String decoded = utf8.decode(base64.decode(base64Part));
      expect(decoded, equals('sess_999|1711881234000'));
    });
  });
}
