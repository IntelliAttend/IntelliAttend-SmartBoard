import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intelliattend_smartboard/models/remote_config.dart';
import 'package:intelliattend_smartboard/services/remote_config_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RemoteConfigService.applyConfig', () {
    test('applies newer config', () async {
      final config = RemoteConfig(
        configVersion: 1,
        flags: {'test_flag': true},
      );
      final applied = await RemoteConfigService.applyConfig(config);
      expect(applied, isTrue);
      expect(RemoteConfigService.isFeatureEnabled('test_flag'), isTrue);
    });

    test('rejects stale config (same version)', () async {
      await RemoteConfigService.applyConfig(RemoteConfig(configVersion: 5));
      final stale =
          await RemoteConfigService.applyConfig(RemoteConfig(configVersion: 5));
      expect(stale, isFalse);
    });

    test('rejects older config', () async {
      await RemoteConfigService.applyConfig(RemoteConfig(configVersion: 10));
      final older = await RemoteConfigService.applyConfig(
          RemoteConfig(configVersion: 5));
      expect(older, isFalse);
    });

    test('applies higher version after lower', () async {
      await RemoteConfigService.applyConfig(RemoteConfig(configVersion: 1));
      await RemoteConfigService.applyConfig(RemoteConfig(configVersion: 2));
      expect(RemoteConfigService.appliedVersion, 2);
    });

    test('persists to SharedPreferences', () async {
      const flags = {'persist_test': true};
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 7, flags: flags),
      );
      // Reset service state and reload from prefs.
      SharedPreferences.setMockInitialValues({});
      await RemoteConfigService.init();
      expect(RemoteConfigService.isFeatureEnabled('persist_test'), isTrue);
      expect(RemoteConfigService.appliedVersion, 7);
    });
  });

  group('RemoteConfigService.init', () {
    test('loads persisted config from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode({
          'config_version': 3,
          'flags': {'cached_feature': false},
          'ui': {},
        }),
        'remote_config_version': 3,
      });
      await RemoteConfigService.init();
      expect(RemoteConfigService.isFeatureEnabled('cached_feature'), isFalse);
      expect(RemoteConfigService.appliedVersion, 3);
    });

    test('handles missing cache gracefully', () async {
      SharedPreferences.setMockInitialValues({});
      await RemoteConfigService.init();
      expect(RemoteConfigService.appliedVersion, 0);
    });

    test('handles corrupted cache gracefully', () async {
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': '{invalid json',
        'remote_config_version': 1,
      });
      await RemoteConfigService.init();
      expect(RemoteConfigService.appliedVersion, 0);
    });
  });

  group('RemoteConfigService.isFeatureEnabled', () {
    test('returns true when no config loaded (safe default)', () {
      expect(RemoteConfigService.isFeatureEnabled('unknown'), isTrue);
    });

    test('returns true when flag absent from config (absent = enabled)', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {'active_flag': false}),
      );
      expect(RemoteConfigService.isFeatureEnabled('absent_flag'), isTrue);
    });

    test('returns false when flag is false', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {'flag': false}),
      );
      expect(RemoteConfigService.isFeatureEnabled('flag'), isFalse);
    });

    test('returns true when flag is true', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {'flag': true}),
      );
      expect(RemoteConfigService.isFeatureEnabled('flag'), isTrue);
    });

    test('treats string "true"/"1"/"yes" as truthy', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {
          'a': 'true',
          'b': '1',
          'c': 'yes',
        }),
      );
      expect(RemoteConfigService.isFeatureEnabled('a'), isTrue);
      expect(RemoteConfigService.isFeatureEnabled('b'), isTrue);
      expect(RemoteConfigService.isFeatureEnabled('c'), isTrue);
    });

    test('treats string "false"/"0"/"no" as falsy', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {
          'a': 'false',
          'b': '0',
          'c': 'no',
        }),
      );
      expect(RemoteConfigService.isFeatureEnabled('a'), isFalse);
      expect(RemoteConfigService.isFeatureEnabled('b'), isFalse);
      expect(RemoteConfigService.isFeatureEnabled('c'), isFalse);
    });

    test('treats int 0 as falsy, non-zero as truthy', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {
          'disabled': 0,
          'enabled': 1,
        }),
      );
      expect(RemoteConfigService.isFeatureEnabled('disabled'), isFalse);
      expect(RemoteConfigService.isFeatureEnabled('enabled'), isTrue);
    });

    test('treats non-null object as truthy', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {'obj': {'nested': 1}}),
      );
      expect(RemoteConfigService.isFeatureEnabled('obj'), isTrue);
    });
  });

  group('RemoteConfigService.flagString', () {
    test('returns value when key exists', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {'key': 'hello'}),
      );
      expect(RemoteConfigService.flagString('key'), 'hello');
    });

    test('returns default when key absent', () {
      expect(
        RemoteConfigService.flagString('missing', defaultValue: 'fallback'),
        'fallback',
      );
    });

    test('returns null when key absent and no default', () {
      expect(RemoteConfigService.flagString('missing'), isNull);
    });
  });

  group('RemoteConfigService.flagNumber', () {
    test('returns int value', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {'num': 42}),
      );
      expect(RemoteConfigService.flagNumber('num'), 42);
    });

    test('returns double value', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {'pi': 3.14}),
      );
      expect(RemoteConfigService.flagNumber('pi'), 3.14);
    });

    test('parses string to number', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, flags: {'str': '99'}),
      );
      expect(RemoteConfigService.flagNumber('str'), 99);
    });

    test('returns default when absent', () {
      expect(
        RemoteConfigService.flagNumber('missing', defaultValue: 0),
        0,
      );
    });
  });

  group('RemoteConfigService.uiString', () {
    test('returns top-level value', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, ui: {'header': 'Smart'}),
      );
      expect(RemoteConfigService.uiString('header'), 'Smart');
    });

    test('returns nested value with dot notation', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(
          configVersion: 1,
          ui: {'labels': {'welcome': 'Hello'}},
        ),
      );
      expect(RemoteConfigService.uiString('labels.welcome'), 'Hello');
    });

    test('returns fallback when missing', () {
      expect(
        RemoteConfigService.uiString('missing', fallback: 'default'),
        'default',
      );
    });

    test('returns null when missing and no fallback', () {
      expect(RemoteConfigService.uiString('missing'), isNull);
    });

    test('returns fallback for deeply nested missing key', () async {
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, ui: {'a': {'b': {'c': 'found'}}}),
      );
      expect(
        RemoteConfigService.uiString('a.b.z', fallback: 'not found'),
        'not found',
      );
    });
  });

  group('RemoteConfigService.updateManifest', () {
    test('returns null when no update configured', () {
      expect(RemoteConfigService.updateManifest, isNull);
    });

    test('returns manifest when update configured', () async {
      final manifest = UpdateManifest(
        minimumVersion: '5.5.0',
        downloadUrl: 'https://example.com/iasb.msi',
      );
      await RemoteConfigService.applyConfig(
        RemoteConfig(configVersion: 1, update: manifest),
      );
      expect(RemoteConfigService.updateManifest, isNotNull);
      expect(RemoteConfigService.updateManifest!.minimumVersion, '5.5.0');
      expect(RemoteConfigService.updateManifest!.downloadUrl,
          'https://example.com/iasb.msi');
    });
  });

  group('RemoteConfigService listeners', () {
    test('addListener fires on config change', () async {
      int callCount = 0;
      RemoteConfigService.addListener(() {
        callCount++;
      });
      await RemoteConfigService.applyConfig(RemoteConfig(configVersion: 100));
      expect(callCount, 1);
    });

    test('removeListener stops notifications', () async {
      int callCount = 0;
      void listener() {
        callCount++;
      }
      RemoteConfigService.addListener(listener);
      RemoteConfigService.removeListener(listener);
      await RemoteConfigService.applyConfig(RemoteConfig(configVersion: 101));
      expect(callCount, 0);
    });
  });
}
