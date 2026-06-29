import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intelliattend_smartboard/models/remote_config.dart';
import 'package:intelliattend_smartboard/services/auto_updater.dart';
import 'package:intelliattend_smartboard/services/remote_config_service.dart';
import 'package:intelliattend_smartboard/services/update_checker.dart';

/// Registers a mock for path_provider platform channels so that
/// AutoUpdater._startUpdate (called by checkForUpdate) does not throw
/// a MissingPluginException in the test environment.
void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getTemporaryDirectory':
          return Directory.systemTemp.path;
        case 'getApplicationDocumentsDirectory':
          return Directory.systemTemp.path;
        case 'getApplicationSupportDirectory':
          return Directory.systemTemp.path;
      }
      return null;
    },
  );
}

/// Integration test for the auto-update pipeline.
///
/// Simulates the server → board flow by constructing [RemoteConfig] objects
/// directly (as the heartbeat handler would) and verifying that:
///   1. Config features and UI strings are applied correctly
///   2. Update manifests are correctly extracted
///   3. Stale config versions are rejected
///   4. Version comparisons correctly determine update need
///
/// Does NOT test HTTP transport (TestWidgetsFlutterBinding intercepts all
/// HTTP calls). HTTP-layer testing belongs in api_service_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _mockPathProvider();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(isOptional: true);

    PackageInfo.setMockInitialValues(
      appName: 'IntelliAttendSmartBoard',
      packageName: 'com.intelliattend.smartboard',
      version: '5.4.0',
      buildNumber: '1',
      buildSignature: 'test',
    );

    await AutoUpdater.init(boardId: 'IASB-TEST');
    await RemoteConfigService.init();
  });

  tearDown(() async {
    UpdateChecker.stop();
  });

  group('Pipeline: config JSON → RemoteConfig → apply → manifest', () {
    test('applies config with flags and UI strings', () async {
      final config = RemoteConfig.fromJson({
        'config_version': 1,
        'flags': {
          'enable_documents': false,
          'experimental_feature': true,
        },
        'ui': {
          'branding': {'title': 'Integration Test'},
        },
        'issued_at': '2026-06-28T12:00:00Z',
      });

      final applied = await RemoteConfigService.applyConfig(config);
      expect(applied, isTrue);

      expect(
          RemoteConfigService.isFeatureEnabled('enable_documents'), isFalse);
      expect(
          RemoteConfigService.isFeatureEnabled('experimental_feature'), isTrue);
      expect(RemoteConfigService.uiString('branding.title'),
          'Integration Test');
      expect(RemoteConfigService.appliedVersion, 1);
    });

    test('config with force_update produces an update manifest', () async {
      final config = RemoteConfig.fromJson({
        'config_version': 2,
        'flags': {},
        'ui': {},
        'force_update': {
          'minimum_version': '5.5.0',
          'download_url':
              'https://github.com/example/releases/download/v5.5.0/IntelliAttendSmartBoard-5.5.0.msi',
          'sha256':
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          'force': true,
          'rollout_percentage': 100,
          'release_notes': 'Integration test release',
          'published_at': '2026-06-28T12:00:00Z',
        },
        'issued_at': '2026-06-28T12:00:00Z',
      });

      final applied = await RemoteConfigService.applyConfig(config);
      expect(applied, isTrue);

      final manifest = RemoteConfigService.updateManifest;
      expect(manifest, isNotNull);
      expect(manifest!.minimumVersion, '5.5.0');
      expect(
          manifest.downloadUrl, contains('IntelliAttendSmartBoard-5.5.0.msi'));
      expect(manifest.force, isTrue);
      expect(manifest.rolloutPercentage, 100);
    });

    test('config without force_update has null manifest', () async {
      final config = RemoteConfig.fromJson({
        'config_version': 3,
        'flags': {},
        'ui': {},
        'issued_at': '2026-06-28T12:00:00Z',
      });

      await RemoteConfigService.applyConfig(config);
      expect(RemoteConfigService.updateManifest, isNull);
    });

    test('stale config version is not re-applied', () async {
      final configV10 = RemoteConfig(
        configVersion: 10,
        flags: {'feat': true},
      );
      await RemoteConfigService.applyConfig(configV10);

      final configV5 = RemoteConfig.fromJson({
        'config_version': 5,
        'flags': {'feat': false},
      });
      final applied = await RemoteConfigService.applyConfig(configV5);

      expect(applied, isFalse);
      expect(RemoteConfigService.isFeatureEnabled('feat'), isTrue);
      expect(RemoteConfigService.appliedVersion, 10);
    });

    test('empty config block is handled gracefully', () async {
      final config = RemoteConfig.fromJson({});
      final applied = await RemoteConfigService.applyConfig(config);
      expect(applied, isFalse);
    });
  });

  group('Version comparison decisions', () {
    test('update needed when board is on older version', () async {
      final config = RemoteConfig.fromJson({
        'config_version': 20,
        'flags': {},
        'ui': {},
        'force_update': {
          'minimum_version': '5.5.0',
          'download_url': 'https://example.com/iasb-5.5.0.msi',
          'sha256':
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          'force': false,
          'rollout_percentage': 100,
        },
      });

      await RemoteConfigService.applyConfig(config);

      final manifest = RemoteConfigService.updateManifest!;
      final isUpdateNeeded = await AutoUpdater.checkForUpdate(manifest);
      expect(isUpdateNeeded, isTrue);
    });

    test('no update needed when board is already current', () async {
      PackageInfo.setMockInitialValues(
        appName: 'IntelliAttendSmartBoard',
        packageName: 'com.intelliattend.smartboard',
        version: '5.5.0',
        buildNumber: '1',
        buildSignature: 'test',
      );
      AutoUpdater.progress.value = null;
      await AutoUpdater.init(boardId: 'IASB-TEST');

      final config = RemoteConfig.fromJson({
        'config_version': 21,
        'flags': {},
        'ui': {},
        'force_update': {
          'minimum_version': '5.5.0',
          'download_url': 'https://example.com/iasb-5.5.0.msi',
          'rollout_percentage': 100,
        },
      });

      await RemoteConfigService.applyConfig(config);

      final manifest = RemoteConfigService.updateManifest!;
      final isUpdateNeeded = await AutoUpdater.checkForUpdate(manifest);
      expect(isUpdateNeeded, isFalse);
    });
  });
}
