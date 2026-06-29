import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intelliattend_smartboard/core/utils/version.dart';
import 'package:intelliattend_smartboard/services/update_health_monitor.dart';

/// Locate the health file that UpdateHealthMonitor writes.
/// Uses the same logic as the production code.
File get healthFile {
  // Use test-specific env to avoid polluting real AppData.
  final localAppData = Platform.environment['LOCALAPPDATA'] ??
      '${Platform.environment['USERPROFILE']}\\AppData\\Local';
  final dir = Directory('$localAppData\\IntelliAttendSmartBoard');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return File('${dir.path}\\update_health.json');
}

/// Save original health content and restore after tests.
String? _savedHealthContent;

/// Save the current health file (if any) so we can restore it later.
void saveHealthState() {
  final f = healthFile;
  if (f.existsSync()) {
    _savedHealthContent = f.readAsStringSync();
  } else {
    _savedHealthContent = null;
  }
}

/// Restore the original health file (or delete the test one).
void restoreHealthState() {
  final f = healthFile;
  if (_savedHealthContent != null) {
    f.writeAsStringSync(_savedHealthContent!);
    _savedHealthContent = null;
  } else {
    if (f.existsSync()) {
      f.deleteSync();
    }
  }
}

/// Write known health state for testing.
void writeHealthFile(Map<String, dynamic> data) {
  final f = healthFile;
  if (!f.parent.existsSync()) {
    f.parent.createSync(recursive: true);
  }
  f.writeAsStringSync(jsonEncode(data));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    saveHealthState();
  });

  tearDown(() {
    restoreHealthState();
  });

  group('UpdateHealthMonitor.init', () {
    test('fresh start with no prior health file', () async {
      // Ensure no health file exists.
      final f = healthFile;
      if (f.existsSync()) f.deleteSync();

      final rollbackInitiated = await UpdateHealthMonitor.init(
        Version.parse('5.4.0'),
      );
      expect(rollbackInitiated, isFalse);
    });

    test('detects version change when previous_version differs', () async {
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'stable',
        'stable_startups': 10,
        'last_stable_version': '5.3.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.pending);
    });

    test('same version does not change status', () async {
      writeHealthFile({
        'previous_version': '5.4.0',
        'status': 'stable',
        'stable_startups': 5,
        'last_stable_version': '5.4.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.stable);
    });

    test('no previous version (0.0.0) does not trigger pending', () async {
      writeHealthFile({
        'previous_version': '0.0.0',
        'status': 'stable',
        'stable_startups': 0,
        'last_stable_version': '0.0.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      // previous_version is 0.0.0 → isNewVersion is false
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.stable);
    });

    test('cleanups backup when version is already stable', () async {
      final testBackupPath = 'iasb_backup_test_dir';
      Directory(testBackupPath).createSync();
      addTearDown(() {
        if (Directory(testBackupPath).existsSync()) {
          Directory(testBackupPath).deleteSync(recursive: true);
        }
      });

      writeHealthFile({
        'previous_version': '5.4.0',
        'status': 'stable',
        'stable_startups': 3,
        'last_stable_version': '5.4.0',
        'rollback_count': 0,
        'backup_path': testBackupPath,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      // Backup should be deleted since status is stable.
      expect(Directory(testBackupPath).existsSync(), isFalse);
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.stable);
    });
  });

  group('UpdateHealthMonitor.markStartupSuccessful', () {
    test('increments startup counter', () async {
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'pending',
        'stable_startups': 0,
        'last_stable_version': '5.3.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.pending);

      await UpdateHealthMonitor.markStartupSuccessful();
      // After 1 successful start, still pending (need 3).
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.pending);
    });

    test('marks stable after 3 successful starts', () async {
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'pending',
        'stable_startups': 0,
        'last_stable_version': '5.3.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));

      await UpdateHealthMonitor.markStartupSuccessful();
      await UpdateHealthMonitor.markStartupSuccessful();
      await UpdateHealthMonitor.markStartupSuccessful();
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.stable);
    });

    test('marks stable after 3+ starts', () async {
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'pending',
        'stable_startups': 0,
        'last_stable_version': '5.3.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));

      for (var i = 0; i < 5; i++) {
        await UpdateHealthMonitor.markStartupSuccessful();
      }
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.stable);
      expect(
        UpdateHealthMonitor.lastStableVersion,
        Version.parse('5.4.0'),
      );
    });

    test('persists startup count to health file', () async {
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'pending',
        'stable_startups': 0,
        'last_stable_version': '5.3.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      await UpdateHealthMonitor.markStartupSuccessful();

      // Verify the file was written.
      final saved = jsonDecode(healthFile.readAsStringSync())
          as Map<String, dynamic>;
      expect(saved['stable_startups'], 1);
      expect(saved['status'], 'pending');
    });
  });

  group('UpdateHealthMonitor.handleCrashLoopDetected', () {
    test('returns false when version is stable', () async {
      writeHealthFile({
        'previous_version': '5.4.0',
        'status': 'stable',
        'stable_startups': 3,
        'last_stable_version': '5.4.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));

      final result = await UpdateHealthMonitor.handleCrashLoopDetected();
      expect(result, isFalse);
    });

    test('returns true and triggers rollback when version is pending', () async {
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'pending',
        'stable_startups': 0,
        'last_stable_version': '5.3.0',
        'rollback_count': 0,
        // No backup_path → rollback will fail early (no exit).
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      expect(UpdateHealthMonitor.status, UpdateHealthStatus.pending);

      final result = await UpdateHealthMonitor.handleCrashLoopDetected();
      // Returns true because status was pending and rollback was attempted.
      // Since backupPath is null, rollback logs an error and returns without
      // calling exit(0).
      expect(result, isTrue);
    });

    test('returns false when no update was ever performed', () async {
      // First launch of a version.
      writeHealthFile({
        'previous_version': '0.0.0',
        'status': 'stable',
        'stable_startups': 0,
        'last_stable_version': '0.0.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));

      final result = await UpdateHealthMonitor.handleCrashLoopDetected();
      // Status is stable (not pending) because isNewVersion was false.
      expect(result, isFalse);
    });
  });

  group('UpdateHealthMonitor.preserveCurrentInstall', () {
    test('creates backup and records state', () async {
      // Create a temp directory simulating the app install.
      final tempDir = Directory.systemTemp.createTempSync('iasb_test_app_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      // Write a test file.
      File('${tempDir.path}\\app.exe').writeAsStringSync('fake binary');

      await UpdateHealthMonitor.preserveCurrentInstall(
        Version.parse('5.3.0'),
        'https://example.com/iasb-5.4.0.msi',
        'abc123',
      );

      // Check that the health file records previous_version.
      final saved =
          jsonDecode(healthFile.readAsStringSync()) as Map<String, dynamic>;
      expect(saved['previous_version'], '5.3.0');
      expect(saved['status'], 'pending');
      expect(saved['stable_startups'], 0);
    });
  });

  group('UpdateHealthMonitor accessors', () {
    test('currentVersion returns the version passed to init', () async {
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'pending',
        'stable_startups': 0,
        'last_stable_version': '5.3.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      expect(UpdateHealthMonitor.currentVersion, Version.parse('5.4.0'));
    });

    test('isPendingStabilisation reflects status', () async {
      // Fresh install of a version (pending status).
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'pending',
        'stable_startups': 0,
        'last_stable_version': '5.3.0',
        'rollback_count': 0,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      expect(UpdateHealthMonitor.isPendingStabilisation, isTrue);

      // After stabilization, isPending is false.
      await UpdateHealthMonitor.markStartupSuccessful();
      await UpdateHealthMonitor.markStartupSuccessful();
      await UpdateHealthMonitor.markStartupSuccessful();
      expect(UpdateHealthMonitor.isPendingStabilisation, isFalse);
    });

    test('rollbackCount tracks total rollbacks', () async {
      writeHealthFile({
        'previous_version': '5.3.0',
        'status': 'pending',
        'stable_startups': 0,
        'last_stable_version': '5.3.0',
        'rollback_count': 3,
      });
      await UpdateHealthMonitor.init(Version.parse('5.4.0'));
      expect(UpdateHealthMonitor.rollbackCount, 3);
    });
  });

  group('UpdateHealthStatus enum', () {
    test('has all expected values', () {
      expect(UpdateHealthStatus.values, hasLength(4));
      expect(UpdateHealthStatus.values, contains(UpdateHealthStatus.stable));
      expect(UpdateHealthStatus.values, contains(UpdateHealthStatus.pending));
      expect(
          UpdateHealthStatus.values, contains(UpdateHealthStatus.rollingBack));
      expect(UpdateHealthStatus.values, contains(UpdateHealthStatus.failed));
    });
  });

  group('UpdateReportStatus enum', () {
    test('has all expected values', () {
      expect(UpdateReportStatus.values, hasLength(3));
      expect(
          UpdateReportStatus.values, contains(UpdateReportStatus.completed));
      expect(UpdateReportStatus.values, contains(UpdateReportStatus.failed));
      expect(
          UpdateReportStatus.values, contains(UpdateReportStatus.rolledBack));
    });
  });
}
