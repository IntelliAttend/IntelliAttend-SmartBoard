import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/models/remote_config.dart';

void main() {
  group('UpdateManifest.fromJson', () {
    test('parses full manifest', () {
      final json = {
        'minimum_version': '5.5.0',
        'download_url': 'https://example.com/iasb-5.5.0.msi',
        'sha256': 'abc123',
        'force': true,
        'rollout_percentage': 25,
        'release_notes': 'Fixed QR crash on rapid scan',
        'published_at': '2026-06-28T12:00:00Z',
      };
      final m = UpdateManifest.fromJson(json);
      expect(m.minimumVersion, '5.5.0');
      expect(m.downloadUrl, 'https://example.com/iasb-5.5.0.msi');
      expect(m.sha256, 'abc123');
      expect(m.force, isTrue);
      expect(m.rolloutPercentage, 25);
      expect(m.releaseNotes, 'Fixed QR crash on rapid scan');
      expect(m.publishedAt, '2026-06-28T12:00:00Z');
    });

    test('defaults when fields are missing', () {
      final json = <String, dynamic>{};
      final m = UpdateManifest.fromJson(json);
      expect(m.minimumVersion, '0.0.0');
      expect(m.downloadUrl, isNull);
      expect(m.sha256, isNull);
      expect(m.force, isFalse);
      expect(m.rolloutPercentage, 100);
      expect(m.releaseNotes, isNull);
      expect(m.publishedAt, isNull);
    });

    test('parses numeric rollout_percentage from string', () {
      final json = {'rollout_percentage': '50'};
      final m = UpdateManifest.fromJson(json);
      expect(m.rolloutPercentage, 50);
    });

    test('parses rollout_percentage as int', () {
      final json = {'rollout_percentage': 75};
      final m = UpdateManifest.fromJson(json);
      expect(m.rolloutPercentage, 75);
    });

    test('force is false for non-bool truthy values', () {
      final m = UpdateManifest.fromJson({'force': 'yes'});
      expect(m.force, isFalse);
    });

    test('handles null values gracefully', () {
      final json = {
        'minimum_version': null,
        'download_url': null,
        'sha256': null,
        'force': null,
        'rollout_percentage': null,
        'release_notes': null,
        'published_at': null,
      };
      final m = UpdateManifest.fromJson(json);
      // null?.toString() yields null, fallback for minimum_version is '0.0.0'.
      expect(m.minimumVersion, '0.0.0');
      expect(m.downloadUrl, isNull);
      expect(m.sha256, isNull);
      expect(m.force, isFalse);
    });
  });

  group('UpdateManifest.toJson', () {
    test('round-trips through JSON', () {
      final original = UpdateManifest(
        minimumVersion: '5.5.0',
        downloadUrl: 'https://example.com/iasb.msi',
        sha256: 'deadbeef',
        force: true,
        rolloutPercentage: 50,
        releaseNotes: 'Fix things',
        publishedAt: '2026-01-01T00:00:00Z',
      );
      final json = original.toJson();
      final restored = UpdateManifest.fromJson(json);
      expect(restored.minimumVersion, original.minimumVersion);
      expect(restored.downloadUrl, original.downloadUrl);
      expect(restored.sha256, original.sha256);
      expect(restored.force, original.force);
      expect(restored.rolloutPercentage, original.rolloutPercentage);
      expect(restored.releaseNotes, original.releaseNotes);
      expect(restored.publishedAt, original.publishedAt);
    });

    test('omits null fields', () {
      final m = UpdateManifest(minimumVersion: '5.5.0');
      final json = m.toJson();
      expect(json.containsKey('download_url'), isFalse);
      expect(json.containsKey('sha256'), isFalse);
      expect(json.containsKey('releasenotes'), isFalse);
      expect(json.containsKey('release_notes'), isFalse);
      expect(json.containsKey('published_at'), isFalse);
    });
  });

  group('UpdateManifest.parsedMinimum', () {
    test('returns parsed Version', () {
      final m = UpdateManifest(minimumVersion: '5.5.0');
      expect(m.parsedMinimum.major, 5);
      expect(m.parsedMinimum.minor, 5);
      expect(m.parsedMinimum.patch, 0);
    });

    test('returns zero for unparseable version', () {
      final m = UpdateManifest(minimumVersion: 'invalid');
      expect(m.parsedMinimum.major, 0);
    });
  });

  group('UpdateManifest.includesBoard', () {
    test('returns true when rolloutPercentage >= 100', () {
      final m = UpdateManifest(
        minimumVersion: '5.5.0',
        rolloutPercentage: 100,
      );
      expect(m.includesBoard('IASB-0000'), isTrue);
      expect(m.includesBoard('IASB-9999'), isTrue);
    });

    test('returns false when rolloutPercentage <= 0', () {
      final m = UpdateManifest(
        minimumVersion: '5.5.0',
        rolloutPercentage: 0,
      );
      expect(m.includesBoard('IASB-0000'), isFalse);
    });

    test('deterministic hash for same board ID', () {
      const boardId = 'IASB-4208';
      final m = UpdateManifest(
        minimumVersion: '5.5.0',
        rolloutPercentage: 50,
      );
      expect(m.includesBoard(boardId), m.includesBoard(boardId));
    });

    test('some boards in cohort, some out at 50%', () {
      final m = UpdateManifest(
        minimumVersion: '5.5.0',
        rolloutPercentage: 50,
      );
      final results = List.generate(100, (i) {
        return m.includesBoard('IASB-${i.toString().padLeft(4, '0')}');
      });
      final included = results.where((r) => r).length;
      expect(included, greaterThan(0));
      expect(included, lessThan(100));
    });

    test('no board excluded at 100%', () {
      final m = UpdateManifest(
        minimumVersion: '5.5.0',
        rolloutPercentage: 100,
      );
      for (var i = 0; i < 1000; i++) {
        expect(m.includesBoard('BOARD-$i'), isTrue);
      }
    });

    test('all boards excluded at 0%', () {
      final m = UpdateManifest(
        minimumVersion: '5.5.0',
        rolloutPercentage: 0,
      );
      for (var i = 0; i < 100; i++) {
        expect(m.includesBoard('BOARD-$i'), isFalse);
      }
    });

    test('deterministic distribution for known board IDs', () {
      final m = UpdateManifest(
        minimumVersion: '5.5.0',
        rolloutPercentage: 30,
      );
      final ids = List.generate(1000, (i) => 'IASB-${1000 + i}');
      final included = ids.where((id) => m.includesBoard(id)).length;
      final ratio = included / ids.length;
      // Should be roughly 30% ± 5%
      expect(ratio, closeTo(0.30, 0.05));
    });
  });

  group('RemoteConfig.fromJson', () {
    test('parses full config', () {
      final json = {
        'config_version': 3,
        'flags': {'enable_analytics': false, 'kiosk_mode': true},
        'ui': {
          'branding': {'title': 'SmartBoard'},
          'labels': {'welcome_text': 'Hello'},
        },
        'force_update': {
          'minimum_version': '5.5.0',
          'download_url': 'https://example.com/iasb.msi',
          'sha256': 'abc',
          'force': true,
          'rollout_percentage': 50,
        },
        'issued_at': '2026-06-28T12:00:00Z',
      };
      final config = RemoteConfig.fromJson(json);
      expect(config.configVersion, 3);
      expect(config.flags['enable_analytics'], isFalse);
      expect(config.flags['kiosk_mode'], isTrue);
      expect(config.ui['branding']['title'], 'SmartBoard');
      expect(config.ui['labels']['welcome_text'], 'Hello');
      expect(config.update, isNotNull);
      expect(config.update!.minimumVersion, '5.5.0');
      expect(config.issuedAt, '2026-06-28T12:00:00Z');
    });

    test('empty config defaults', () {
      final config = RemoteConfig.fromJson(<String, dynamic>{});
      expect(config.configVersion, 0);
      expect(config.flags, isEmpty);
      expect(config.ui, isEmpty);
      expect(config.update, isNull);
      expect(config.issuedAt, isNull);
    });

    test('config with null force_update', () {
      final json = {'config_version': 1, 'force_update': null};
      final config = RemoteConfig.fromJson(json);
      expect(config.update, isNull);
    });

    test('config with empty flags', () {
      final json = {'config_version': 2, 'flags': {}};
      final config = RemoteConfig.fromJson(json);
      expect(config.flags, isEmpty);
    });
  });

  group('RemoteConfig.toJson', () {
    test('round-trips through JSON', () {
      final original = RemoteConfig(
        configVersion: 5,
        flags: {'feat_a': true, 'feat_b': false},
        ui: {'setting': 'value'},
        update: UpdateManifest(
          minimumVersion: '6.0.0',
          downloadUrl: 'https://example.com/iasb.msi',
        ),
        issuedAt: '2026-01-01T00:00:00Z',
      );
      final json = original.toJson();
      final restored = RemoteConfig.fromJson(json);
      expect(restored.configVersion, original.configVersion);
      expect(restored.flags, original.flags);
      expect(restored.ui, original.ui);
      expect(restored.update!.minimumVersion, original.update!.minimumVersion);
      expect(restored.issuedAt, original.issuedAt);
    });

    test('omits null update and issuedAt', () {
      final c = RemoteConfig(configVersion: 1);
      final json = c.toJson();
      expect(json.containsKey('force_update'), isFalse);
      expect(json.containsKey('issued_at'), isFalse);
    });
  });

  group('RemoteConfig.isNewerThan', () {
    test('config version higher is newer', () {
      final c = RemoteConfig(configVersion: 5);
      expect(c.isNewerThan(4), isTrue);
    });

    test('config version equal is not newer', () {
      final c = RemoteConfig(configVersion: 5);
      expect(c.isNewerThan(5), isFalse);
    });

    test('config version lower is not newer', () {
      final c = RemoteConfig(configVersion: 3);
      expect(c.isNewerThan(5), isFalse);
    });

    test('config version 0 is newer than none applied (-1)', () {
      final c = RemoteConfig(configVersion: 1);
      expect(c.isNewerThan(0), isTrue);
    });
  });
}
