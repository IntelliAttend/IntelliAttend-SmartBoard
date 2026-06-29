import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:intelliattend_smartboard/models/remote_config.dart';
import 'package:intelliattend_smartboard/services/auto_updater.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _mockPathProvider();
    PackageInfo.setMockInitialValues(
      appName: 'IntelliAttendSmartBoard',
      packageName: 'com.intelliattend.smartboard',
      version: '5.4.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
    AutoUpdater.progress.value = null;
    await AutoUpdater.init(boardId: 'IASB-TEST');
  });

  group('AutoUpdater.installedVersion', () {
    test('reads from PackageInfo mock', () {
      final v = AutoUpdater.installedVersion;
      expect(v.major, 5);
      expect(v.minor, 4);
      expect(v.patch, 0);
    });
  });

  group('AutoUpdater.checkForUpdate', () {
    test('returns false when already up to date', () async {
      final manifest = UpdateManifest(minimumVersion: '5.4.0');
      final result = await AutoUpdater.checkForUpdate(manifest);
      expect(result, isFalse);
    });

    test('returns false when installed version is newer', () async {
      final manifest = UpdateManifest(minimumVersion: '5.3.0');
      final result = await AutoUpdater.checkForUpdate(manifest);
      expect(result, isFalse);
    });

    test('returns false when manifest has no download URL', () async {
      final manifest = UpdateManifest(minimumVersion: '5.5.0');
      // downloadUrl is null by default.
      final result = await AutoUpdater.checkForUpdate(manifest);
      expect(result, isFalse);
    });

    test('returns false when board not in rollout cohort', () async {
      final manifest = UpdateManifest(
        minimumVersion: '5.5.0',
        downloadUrl: 'https://example.com/iasb-5.5.0.msi',
        rolloutPercentage: 0, // exclude all boards
      );
      final result = await AutoUpdater.checkForUpdate(manifest);
      expect(result, isFalse);
    });

    test('returns true when update is available and board is in cohort',
        () async {
      final manifest = UpdateManifest(
        minimumVersion: '5.5.0',
        downloadUrl: 'https://github.com/example/releases/download/v5.5.0/iasb.msi',
        rolloutPercentage: 100,
      );
      final result = await AutoUpdater.checkForUpdate(manifest);
      // Should return true (starts update). The actual download will fail
      // in test because there's no HTTP server, but checkForUpdate only
      // does pre-flight checks before calling _startUpdate.
      expect(result, isTrue);
    });

    test('returns true when force flag is set and update is needed', () async {
      final manifest = UpdateManifest(
        minimumVersion: '5.5.0',
        downloadUrl: 'https://example.com/iasb-5.5.0.msi',
        force: true,
        rolloutPercentage: 100,
      );
      final result = await AutoUpdater.checkForUpdate(manifest);
      expect(result, isTrue);
    });

    test('returns false when update already in progress', () async {
      // Simulate an already-in-progress state.
      AutoUpdater.progress.value = const UpdateProgress(
        state: UpdateState.downloading,
        targetVersion: '5.5.0',
        fraction: 0.5,
      );

      final manifest = UpdateManifest(
        minimumVersion: '5.5.0',
        downloadUrl: 'https://example.com/iasb-5.5.0.msi',
        rolloutPercentage: 100,
      );
      final result = await AutoUpdater.checkForUpdate(manifest);
      expect(result, isFalse);
    });
  });

  group('AutoUpdater state transitions', () {
    test('progress starts as null', () {
      expect(AutoUpdater.progress.value, isNull);
    });

    test('progress state machine covers all transitions', () {
      const allStates = [
        UpdateState.idle,
        UpdateState.downloading,
        UpdateState.verifying,
        UpdateState.installing,
        UpdateState.completed,
        UpdateState.failed,
      ];
      for (final state in UpdateState.values) {
        expect(allStates, contains(state));
      }
    });
  });

  group('UpdateProgress', () {
    test('statusText shows downloading percentage', () {
      final p = const UpdateProgress(
        state: UpdateState.downloading,
        targetVersion: '5.5.0',
        fraction: 0.5,
      );
      expect(p.statusText, contains('Downloading'));
      expect(p.statusText, contains('50%'));
    });

    test('statusText shows verifying', () {
      final p = const UpdateProgress(
        state: UpdateState.verifying,
        targetVersion: '5.5.0',
        fraction: 1.0,
      );
      expect(p.statusText, contains('Verifying'));
    });

    test('statusText shows installing', () {
      final p = const UpdateProgress(
        state: UpdateState.installing,
        targetVersion: '5.5.0',
        fraction: 1.0,
      );
      expect(p.statusText, contains('Installing'));
    });

    test('statusText shows completed', () {
      final p = const UpdateProgress(
        state: UpdateState.completed,
        targetVersion: '5.5.0',
      );
      expect(p.statusText, contains('installed'));
    });

    test('statusText shows error text for failed state', () {
      final p = const UpdateProgress(
        state: UpdateState.failed,
        targetVersion: '5.5.0',
        error: 'Network error',
      );
      expect(p.statusText, 'Network error');
    });

    test('statusText is empty for idle', () {
      final p = const UpdateProgress(
        state: UpdateState.idle,
        targetVersion: '',
      );
      expect(p.statusText, isEmpty);
    });

    test('statusText shows generic message when error is null for failed',
        () {
      final p = const UpdateProgress(
        state: UpdateState.failed,
        targetVersion: '5.5.0',
      );
      expect(p.statusText, 'Update failed');
    });

    test('force flag is carried through', () {
      final p = const UpdateProgress(
        state: UpdateState.downloading,
        targetVersion: '5.5.0',
        force: true,
      );
      expect(p.force, isTrue);
    });
  });

  group('Version comparison boundary', () {
    test('equal version returns false', () async {
      final manifest = UpdateManifest(minimumVersion: '5.4.0+1');
      final result = await AutoUpdater.checkForUpdate(manifest);
      // Installed is 5.4.0+1, required is 5.4.0 — buildNumber ignored,
      // so 5.4.0 >= 5.4.0 → no update.
      expect(result, isFalse);
    });

    test('patch version bump triggers update', () async {
      final manifest = UpdateManifest(
        minimumVersion: '5.4.1',
        downloadUrl: 'https://example.com/iasb.msi',
        rolloutPercentage: 100,
      );
      final result = await AutoUpdater.checkForUpdate(manifest);
      expect(result, isTrue);
    });
  });
}
