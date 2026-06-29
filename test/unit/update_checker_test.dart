import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intelliattend_smartboard/models/remote_config.dart';
import 'package:intelliattend_smartboard/services/auto_updater.dart';
import 'package:intelliattend_smartboard/services/remote_config_service.dart';
import 'package:intelliattend_smartboard/services/update_checker.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'IntelliAttendSmartBoard',
      packageName: 'com.intelliattend.smartboard',
      version: '9.9.9',
      buildNumber: '1',
      buildSignature: 'test',
    );
    AutoUpdater.progress.value = null;
    await AutoUpdater.init(boardId: 'IASB-TEST');
  });

  tearDown(() {
    UpdateChecker.stop();
  });

  group('UpdateChecker lifecycle', () {
    test('start and stop do not throw', () {
      UpdateChecker.start();
      UpdateChecker.stop();
    });

    test('multiple start calls are safe', () {
      UpdateChecker.start();
      UpdateChecker.start();
      UpdateChecker.stop();
    });

    test('stop when not started is safe', () {
      UpdateChecker.stop();
      UpdateChecker.stop();
    });
  });

  group('UpdateChecker.checkNow', () {
    test('does not throw when no manifest configured', () async {
      await expectLater(UpdateChecker.checkNow(), completes);
    });

    test('does not throw when manifest matches current version', () async {
      // The manifest requires 9.9.9 and installed is 9.9.9 → no update needed.
      await RemoteConfigService.applyConfig(
        RemoteConfig(
          configVersion: 1,
          update: UpdateManifest(
            minimumVersion: '9.9.9',
            downloadUrl: 'https://example.com/nonexistent.msi',
            rolloutPercentage: 100,
          ),
        ),
      );
      await expectLater(UpdateChecker.checkNow(), completes);
    });
  });
}
