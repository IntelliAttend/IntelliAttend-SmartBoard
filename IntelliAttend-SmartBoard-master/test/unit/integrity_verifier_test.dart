import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intelliattend_smartboard/core/security/integrity_verifier.dart';

void main() {
  group('IntegrityVerifier', () {
    setUp(() async {
      await dotenv.load(isOptional: true);
    });

    test('verifyCodeSignature returns true in debug mode', () async {
      final result = await IntegrityVerifier.verifyCodeSignature();
      expect(result, isTrue);
    });

    test('verify does not throw', () {
      expect(() => IntegrityVerifier.verify(), returnsNormally);
    });
  });
}
