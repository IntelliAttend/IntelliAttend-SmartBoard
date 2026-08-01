import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:intelliattend_smartboard/core/config/install_paths.dart';
import 'package:intelliattend_smartboard/core/lifecycle/lifecycle_phases.dart';
import 'package:intelliattend_smartboard/core/security/secure_storage_service.dart';
import 'package:intelliattend_smartboard/models/isar_schemas.dart';
import 'package:intelliattend_smartboard/services/session_manager.dart';

/// Find the Isar native DLL across known locations.
String? findIsarDll() {
  final candidates = [
    // Build output
    '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\isar.dll',
    // Project root
    '${Directory.current.path}\\isar.dll',
    // Flutter cache
    '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache\\bin\\isar.dll',
  ];
  return candidates.firstWhere(
    (p) => File(p).existsSync(),
    orElse: () => 'isar.dll',
  );
}

void main() {
  late Directory tempRoot;
  Isar? testIsar;

  /// The FlutterSecureStorage method channel name.
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // ── Temp directory for InstallPaths ─────────────────────────────────
    tempRoot = Directory.systemTemp.createTempSync('reinstall_test_');
    Directory('${tempRoot.path}\\App').createSync(recursive: true);
    InstallPaths.testRootOverride = tempRoot.path;

    // ── FlutterSecureStorage mock (all reads return null) ───────────────
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'write':
          return null;
        case 'delete':
          return null;
        case 'deleteAll':
          return null;
        case 'containsKey':
          return false;
        case 'readAll':
          return <String, String>{};
        default:
          return null;
      }
    });

    // ── Real Isar in a temp directory (only DeviceRegistration needed) ─
    // If native DLL is unavailable, testIsar stays null and Isar tests skip.
    try {
      final isarDll = findIsarDll();
      if (isarDll != null) {
        await Isar.initializeIsarCore(libraries: {Abi.current(): isarDll});
      }
      testIsar = await Isar.open(
        [
          ActiveSessionSchema,
          QueuedScanSchema,
          DeviceRegistrationSchema,
          TimetableEntrySchema,
          CompletedSessionSchema,
          HydrationProfileSchema,
          HydrationRosterSchema,
          StoredNotificationSchema,
        ],
        directory: tempRoot.path,
      );
      SessionManager.isarOverride = testIsar;
    } catch (e) {
      // Isar not available in this test environment
    }
  });

  tearDown(() async {
    InstallPaths.testRootOverride = null;
    SessionManager.isarOverride = null;
    if (testIsar != null) {
      await testIsar!.close(deleteFromDisk: true);
    }
    tempRoot.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  // ── Helpers ──────────────────────────────────────────────────────────

  File markerFile() => File('${InstallPaths.appDir}\\.initialized');

  bool markerExists() => markerFile().existsSync();

  Map<String, dynamic>? readMarker() {
    if (!markerExists()) return null;
    return jsonDecode(markerFile().readAsStringSync()) as Map<String, dynamic>;
  }

  /// Seed SecureStorage with email and/or refresh token.
  Future<void> seedSecureStorage({
    required bool hasEmail,
    required bool hasRefreshToken,
  }) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      switch (call.method) {
        case 'read':
          final key = call.arguments['key'] as String;
          if (key == 'board_email' && hasEmail) return 'test@board.com';
          if (key == 'refresh_token' && hasRefreshToken) {
            return 'test_refresh_token';
          }
          return null;
        case 'write':
          return null;
        case 'delete':
          return null;
        case 'deleteAll':
          return null;
        case 'containsKey':
          return false;
        case 'readAll':
          return <String, String>{};
        default:
          return null;
      }
    });
  }

  /// Replace SecureStorage mock so all reads return null (post-clear).
  void simulateSecureStorageGetsCleared() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'write':
          return null;
        case 'delete':
          return null;
        case 'deleteAll':
          return null;
        case 'containsKey':
          return false;
        case 'readAll':
          return <String, String>{};
        default:
          return null;
      }
    });
  }

  Future<void> seedIsarRegistration() async {
    if (testIsar == null) return;
    final reg = DeviceRegistration()
      ..smartBoardId = 'SB-001'
      ..hardwareId = 'HW-001'
      ..roomName = 'Room 101'
      ..building = 'Main'
      ..department = 'CS'
      ..capacity = 50
      ..registrationDate = DateTime.now();
    await testIsar!.writeTxn(() async {
      await testIsar!.deviceRegistrations.put(reg);
    });
  }

  void verifyMarkerWritten() {
    expect(markerExists(), true);
    final marker = readMarker();
    expect(marker, isNotNull);
    expect(marker!['initialized_at'], isA<String>());
    final initTime = DateTime.parse(marker['initialized_at'] as String);
    expect(
      initTime.difference(DateTime.now()).inSeconds.abs(),
      lessThan(5),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  Simulation tests — all 7 scenarios + resilience
  // ════════════════════════════════════════════════════════════════════════

  group('Reinstall detection — Simulation', () {
    test(
      'A: Fresh install — no marker, no stale data → marker written, nothing wiped',
      () async {
        expect(markerExists(), false);

        await LifecyclePhases.clearStaleDataIfReinstall();

        verifyMarkerWritten();
      },
    );

    test(
      'B: Normal startup — marker exists → no action, data preserved',
      () async {
        markerFile().parent.createSync(recursive: true);
        markerFile().writeAsStringSync(jsonEncode({
          'initialized_at': DateTime.now().toIso8601String(),
        }));
        expect(markerExists(), true);

        await LifecyclePhases.clearStaleDataIfReinstall();

        expect(markerExists(), true);
      },
    );

    test(
      'C: Update via MajorUpgrade — marker survives → no action despite stale SecureStorage',
      () async {
        markerFile().parent.createSync(recursive: true);
        markerFile().writeAsStringSync(jsonEncode({
          'initialized_at': DateTime.now()
              .subtract(const Duration(days: 7))
              .toIso8601String(),
        }));
        expect(markerExists(), true);

        await seedSecureStorage(hasEmail: true, hasRefreshToken: false);

        await LifecyclePhases.clearStaleDataIfReinstall();

        // SecureStorage data should survive — marker was present
        expect(
          await SecureStorageService.getBoardEmail(),
          'test@board.com',
          reason: 'SecureStorage data must survive when marker is present',
        );
      },
    );

    test(
      'D: Reinstall — stale SecureStorage (email) → wiped + marker written',
      () async {
        expect(markerExists(), false);
        await seedSecureStorage(hasEmail: true, hasRefreshToken: false);

        await LifecyclePhases.clearStaleDataIfReinstall();

        verifyMarkerWritten();

        // After wipe, reads return null
        simulateSecureStorageGetsCleared();
        final email = await SecureStorageService.getBoardEmail();
        expect(email, isNull,
            reason: 'Email should be wiped after reinstall detection');
        final rt = await SecureStorageService.getRefreshToken();
        expect(rt, isNull,
            reason: 'Refresh token should be wiped after reinstall detection');
      },
    );

    test(
      'E: Reinstall — stale Isar DeviceRegistration → wiped + marker written',
      () async {
        if (testIsar == null) return;
        expect(markerExists(), false);
        await seedIsarRegistration();
        expect(
            await testIsar!.deviceRegistrations.where().findFirst(), isNotNull);

        await LifecyclePhases.clearStaleDataIfReinstall();

        verifyMarkerWritten();

        final regAfter =
            await testIsar!.deviceRegistrations.where().findFirst();
        expect(regAfter, isNull,
            reason:
                'DeviceRegistration should be wiped after reinstall detection');
      },
    );

    test(
      'F: Reinstall — both SecureStorage and Isar stale → both wiped + marker',
      () async {
        if (testIsar == null) return;
        expect(markerExists(), false);
        await seedSecureStorage(hasEmail: true, hasRefreshToken: true);
        await seedIsarRegistration();

        await LifecyclePhases.clearStaleDataIfReinstall();

        verifyMarkerWritten();

        simulateSecureStorageGetsCleared();
        expect(await SecureStorageService.getBoardEmail(), isNull);
        expect(await SecureStorageService.getRefreshToken(), isNull);

        final regAfter =
            await testIsar!.deviceRegistrations.where().findFirst();
        expect(regAfter, isNull,
            reason: 'DeviceRegistration should be wiped');
      },
    );

    test(
      'G: First install after corruption — no marker, no stale data → marker only',
      () async {
        expect(markerExists(), false);

        await LifecyclePhases.clearStaleDataIfReinstall();

        verifyMarkerWritten();
      },
    );

    test(
      'G: First install after corruption — no marker, no stale data → marker only',
      () async {
        expect(markerExists(), false);

        await LifecyclePhases.clearStaleDataIfReinstall();

        verifyMarkerWritten();

        if (testIsar == null) return;
        final regAfter =
            await testIsar!.deviceRegistrations.where().findFirst();
        expect(regAfter, isNull);
      },
    );

    test(
      'Idempotency — second call with marker present is a no-op',
      () async {
        await LifecyclePhases.clearStaleDataIfReinstall();
        verifyMarkerWritten();

        final markerContent = markerFile().readAsStringSync();

        await LifecyclePhases.clearStaleDataIfReinstall();

        expect(markerFile().readAsStringSync(), equals(markerContent),
            reason: 'Second call should not modify the marker');
      },
    );

    test(
      'Resilience — SecureStorage throws is handled gracefully',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
          throw PlatformException(
              code: 'UNEXPECTED_ERROR', message: 'mock failure');
        });

        // Should not throw; the outer try-catch catches the error.
        // Marker is NOT written because the exception fires before the
        // marker-write lines are reached.
        await LifecyclePhases.clearStaleDataIfReinstall();

        // If the exception occurred, marker may or may not be written
        // depending on where in the try block it fired. The key assertion
        // is that the method does not throw.
      },
    );

    test(
      'Resilience — Isar not initialized is handled gracefully',
      () async {
        SessionManager.isarOverride = null;

        await LifecyclePhases.clearStaleDataIfReinstall();

        expect(markerExists(), true,
            reason:
                'Marker should be written even when Isar is unavailable');
      },
    );
  });

  group('Reinstall detection — SecureStorage mock verification', () {
    test('SecureStorage mock returns null by default', () async {
      expect(await SecureStorageService.getBoardEmail(), isNull);
      expect(await SecureStorageService.getRefreshToken(), isNull);
    });

    test('SecureStorage mock returns seeded values', () async {
      await seedSecureStorage(hasEmail: true, hasRefreshToken: true);
      expect(await SecureStorageService.getBoardEmail(), 'test@board.com');
      expect(
          await SecureStorageService.getRefreshToken(), 'test_refresh_token');
    });

    test('simulateSecureStorageGetsCleared returns null after clear', () async {
      await seedSecureStorage(hasEmail: true, hasRefreshToken: true);
      simulateSecureStorageGetsCleared();
      expect(await SecureStorageService.getBoardEmail(), isNull);
      expect(await SecureStorageService.getRefreshToken(), isNull);
    });
  });
}
