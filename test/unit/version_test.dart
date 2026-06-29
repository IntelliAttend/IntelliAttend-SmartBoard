import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/core/utils/version.dart';

void main() {
  group('Version.parse', () {
    test('parses standard X.Y.Z', () {
      final v = Version.parse('5.4.0');
      expect(v.major, 5);
      expect(v.minor, 4);
      expect(v.patch, 0);
      expect(v.buildNumber, isNull);
      expect(v.preRelease, isNull);
    });

    test('parses X.Y.Z+build', () {
      final v = Version.parse('5.4.0+1');
      expect(v.major, 5);
      expect(v.minor, 4);
      expect(v.patch, 0);
      expect(v.buildNumber, '1');
    });

    test('parses X.Y.Z-pre', () {
      final v = Version.parse('2.0.0-beta');
      expect(v.major, 2);
      expect(v.minor, 0);
      expect(v.patch, 0);
      expect(v.preRelease, 'beta');
    });

    test('parses X.Y.Z-pre+build', () {
      final v = Version.parse('2.0.0-beta+1');
      expect(v.major, 2);
      expect(v.minor, 0);
      expect(v.patch, 0);
      // Pre-release includes everything after the first '-'.
      expect(v.preRelease, 'beta+1');
      expect(v.buildNumber, isNull);
    });

    test('parses with whitespace', () {
      final v = Version.parse('  3.1.4  ');
      expect(v.major, 3);
      expect(v.minor, 1);
      expect(v.patch, 4);
    });

    test('parses double-digit components', () {
      final v = Version.parse('12.34.567');
      expect(v.major, 12);
      expect(v.minor, 34);
      expect(v.patch, 567);
    });

    test('throws FormatException for empty string', () {
      expect(() => Version.parse(''), throwsFormatException);
    });

    test('throws FormatException for partial version', () {
      expect(() => Version.parse('5.4'), throwsFormatException);
    });

    test('throws FormatException for non-numeric', () {
      expect(() => Version.parse('a.b.c'), throwsFormatException);
    });

    test('throws FormatException for single number', () {
      expect(() => Version.parse('5'), throwsFormatException);
    });

    test('throws FormatException for alphabetic suffix without separator', () {
      expect(() => Version.parse('5.4.0rc1'), throwsFormatException);
    });
  });

  group('Version comparison', () {
    test('equality by major.minor.patch', () {
      expect(Version.parse('5.4.0'), equals(Version.parse('5.4.0')));
    });

    test('equality ignores build number', () {
      expect(Version.parse('5.4.0+1'), equals(Version.parse('5.4.0+2')));
    });

    test('equality ignores pre-release tag', () {
      expect(Version.parse('5.4.0-beta'), equals(Version.parse('5.4.0')));
    });

    test('not equal for different major', () {
      expect(Version.parse('5.4.0'), isNot(equals(Version.parse('6.4.0'))));
    });

    test('not equal for different minor', () {
      expect(Version.parse('5.4.0'), isNot(equals(Version.parse('5.5.0'))));
    });

    test('not equal for different patch', () {
      expect(Version.parse('5.4.0'), isNot(equals(Version.parse('5.4.1'))));
    });

    test('identicalBuild requires matching buildNumber', () {
      expect(
        Version.parse('5.4.0+1').identicalBuild(Version.parse('5.4.0+1')),
        isTrue,
      );
    });

    test('identicalBuild false when buildNumber differs', () {
      expect(
        Version.parse('5.4.0+1').identicalBuild(Version.parse('5.4.0+2')),
        isFalse,
      );
    });

    test('less than', () {
      expect(Version.parse('5.4.0') < Version.parse('5.5.0'), isTrue);
      expect(Version.parse('5.4.0') < Version.parse('5.4.0'), isFalse);
      expect(Version.parse('5.5.0') < Version.parse('5.4.0'), isFalse);
    });

    test('less than or equal', () {
      expect(Version.parse('5.4.0') <= Version.parse('5.5.0'), isTrue);
      expect(Version.parse('5.4.0') <= Version.parse('5.4.0'), isTrue);
      expect(Version.parse('5.5.0') <= Version.parse('5.4.0'), isFalse);
    });

    test('greater than', () {
      expect(Version.parse('5.5.0') > Version.parse('5.4.0'), isTrue);
      expect(Version.parse('5.4.0') > Version.parse('5.4.0'), isFalse);
      expect(Version.parse('5.4.0') > Version.parse('5.5.0'), isFalse);
    });

    test('greater than or equal', () {
      expect(Version.parse('5.5.0') >= Version.parse('5.4.0'), isTrue);
      expect(Version.parse('5.4.0') >= Version.parse('5.4.0'), isTrue);
      expect(Version.parse('5.4.0') >= Version.parse('5.5.0'), isFalse);
    });

    test('cross-component comparison (major beats minor)', () {
      expect(Version.parse('6.0.0') > Version.parse('5.99.99'), isTrue);
    });

    test('cross-component comparison (minor beats patch)', () {
      expect(Version.parse('5.10.0') > Version.parse('5.9.99'), isTrue);
    });
  });

  group('Version.toString', () {
    test('formats as X.Y.Z', () {
      expect(Version.parse('5.4.0').toString(), '5.4.0');
    });

    test('includes buildNumber', () {
      expect(Version.parse('5.4.0+1').toString(), '5.4.0+1');
    });

    test('includes preRelease', () {
      expect(Version.parse('5.4.0-beta').toString(), '5.4.0-beta');
    });

    test('includes preRelease and buildNumber', () {
      expect(
        Version.parse('5.4.0-beta+1').toString(),
        '5.4.0-beta+1',
      );
    });
  });

  group('Version.semantic', () {
    test('returns X.Y.Z without suffix', () {
      expect(Version.parse('5.4.0-beta+1').semantic, '5.4.0');
    });
  });

  group('Version.zero', () {
    test('is 0.0.0', () {
      expect(Version.zero.major, 0);
      expect(Version.zero.minor, 0);
      expect(Version.zero.patch, 0);
    });

    test('equals parsed zero', () {
      expect(Version.zero, equals(Version.parse('0.0.0')));
    });

    test('is less than any real version', () {
      expect(Version.zero < Version.parse('0.0.1'), isTrue);
      expect(Version.zero < Version.parse('0.1.0'), isTrue);
      expect(Version.zero < Version.parse('1.0.0'), isTrue);
    });
  });

  group('Version edge cases', () {
    test('large numbers', () {
      final v = Version.parse('999999.999999.999999+999999');
      expect(v.major, 999999);
      expect(v.minor, 999999);
      expect(v.patch, 999999);
      expect(v.buildNumber, '999999');
    });

    test('pre-release with dots', () {
      final v = Version.parse('1.0.0-alpha.1');
      expect(v.preRelease, 'alpha.1');
    });

    test('pre-release with hyphens in tag', () {
      final v = Version.parse('1.0.0-rc-1');
      expect(v.preRelease, 'rc-1');
    });

    test('build number with dots', () {
      final v = Version.parse('1.0.0+20260101.120000');
      expect(v.buildNumber, '20260101.120000');
    });

    test('hashCode equality', () {
      final a = Version.parse('5.4.0+1');
      final b = Version.parse('5.4.0+999');
      expect(a.hashCode, equals(b.hashCode));
    });

    test('hashCode different for different major', () {
      final a = Version.parse('5.4.0');
      final b = Version.parse('6.4.0');
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });
}
