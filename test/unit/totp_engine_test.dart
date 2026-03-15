
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

// Mirroring the internal logic for testing
String generateHash(String secret, int epoch) {
  final List<int> secretBytes = utf8.encode(secret);
  final List<int> epochBytes = utf8.encode(epoch.toString());
  final Hmac hmac = Hmac(sha256, secretBytes);
  final Digest digest = hmac.convert(epochBytes);
  return digest.toString();
}

void main() {
  group('TotpEngine Cryptographic Logic', () {
    const String testSecret = 'Z9#KL2!PQ8RX\$MN5';
    const int windowMs = 3500; // 3.5s

    test('Identical seed and epoch must yield identical hash', () {
      final String hash1 = generateHash(testSecret, 1000);
      final String hash2 = generateHash(testSecret, 1000);
      
      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64)); // SHA-256 length
    });

    test('Hash must change when epoch increments', () {
      final String hash1 = generateHash(testSecret, 1000);
      final String hash2 = generateHash(testSecret, 1001);
      
      expect(hash1, isNot(equals(hash2)));
    });

    test('Window calculation logic must be stable', () {
      const int windowMs = 3500;
      
      // Align baseTime to be exactly at the start of a 3.5s window
      final int rawTime = 1710500000000;
      final int baseTime = rawTime - (rawTime % windowMs);
      
      final int timeSameWindow = baseTime + 3400; // 3.4s later (still in window)
      final int timeNextWindow = baseTime + 3500; // 3.5s later (exactly next window)

      final int epochBase = baseTime ~/ windowMs;
      final int epochSame = timeSameWindow ~/ windowMs;
      final int epochNext = timeNextWindow ~/ windowMs;

      expect(epochSame, equals(epochBase), reason: '3.4s offset should stay in the same 3.5s window');
      expect(epochNext, equals(epochBase + 1), reason: '3.5s offset must be the next window');
    });
  });
}
