import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/isar_schemas.dart';
import '../core/security/secure_storage_service.dart';
import '../core/utils/logger.dart';
import 'time_sync_service.dart';

class SessionManager {
  static Isar? _isar;

  static Future<void> init() async {
    if (_isar != null) return;

    await _migrateFromOldPath();

    // Pre-generate and persist AES-256 key in OS keychain for future Isar 3.2+
    // encryption support. Not yet passed to Isar.open() (3.1.0 limitation).
    // ignore: unused_local_variable
    final encryptKey = await _loadEncryptionKey();

    final dir = await getApplicationSupportDirectory();
    final schemas = [
      ActiveSessionSchema,
      QueuedScanSchema,
      DeviceRegistrationSchema,
      TimetableEntrySchema,
      CompletedSessionSchema,
    ];

    try {
      _isar = await Isar.open(
        schemas,
        directory: dir.path,
      );
      Log.i('📦 [SessionManager] Isar Vault Initialized.');
    } catch (e) {
      Log.e('❌ [SessionManager] Isar Initialization Failed (Attempt 1): $e');

      try {
        Log.w(
            '📦 [SessionManager] Attempting to wipe corrupted/stale local vault...');
        final isar = Isar.getInstance();
        if (isar != null) {
          await isar.close();
        }

        _isar = await Isar.open(
          schemas,
          directory: dir.path,
          name: 'intelliattend_vault_v2',
        );
        Log.i('📦 [SessionManager] New Isar Vault Created successfully.');
      } catch (retryError) {
        Log.e('🚨 [SessionManager] CRITICAL: Fatal Isar Failure: $retryError');
        rethrow;
      }
    }
  }

  /// Generates or retrieves the AES-256 Isar encryption key.
  /// The key is 32 bytes stored as base64 in the OS keychain.
  static Future<List<int>?> _loadEncryptionKey() async {
    try {
      String? storedKey = await SecureStorageService.getIsarEncryptKey();
      if (storedKey == null) {
        final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
        storedKey = base64Encode(key);
        await SecureStorageService.storeIsarEncryptKey(storedKey);
      }
      final decoded = base64Decode(storedKey);
      if (decoded.length != 32) {
        Log.w('⚠️ [SessionManager] Invalid encryption key length, recreating...');
        final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
        final newKey = base64Encode(key);
        await SecureStorageService.storeIsarEncryptKey(newKey);
        return key;
      }
      return decoded;
    } catch (e) {
      Log.w('⚠️ [SessionManager] Encryption key setup failed, proceeding without encryption: $e');
      return null;
    }
  }

  static Future<void> _migrateFromOldPath() async {
    try {
      final oldDir = await getApplicationDocumentsDirectory();
      final newDir = await getApplicationSupportDirectory();

      final oldFile = File('${oldDir.path}/intelliattend_vault_v2.isar');
      final newFile = File('${newDir.path}/intelliattend_vault_v2.isar');

      if (await oldFile.exists() && !await newFile.exists()) {
        await newFile.parent.create(recursive: true);
        await oldFile.copy(newFile.path);
        await oldFile.delete();
        Log.i(
            '📦 [SessionManager] Isar database migrated from Documents to AppSupport');
      }
    } catch (e) {
      Log.w('⚠️ [SessionManager] Migration from old path skipped: $e');
    }
  }

  static Isar get isar {
    if (_isar == null) {
      throw Exception(
          'Isar not initialized. Call SessionManager.init() first.');
    }
    return _isar!;
  }

  /// Test-only: inject an Isar instance without going through init().
  /// Must NOT be used in production code.
  static set isarOverride(Isar? isar) => _isar = isar;

  /// Persists a new active session to the local vault.
  /// Standardizes metadata across all screen callers.
  static Future<void> saveSession({
    required String sessionId,
    required int rosterCount,
    required String facultyName,
    required String courseName,
    required String sectionId,
    required DateTime endTime,
  }) async {
    final session = ActiveSession()
      ..sessionId = sessionId
      ..rosterCount = rosterCount
      ..facultyName = facultyName
      ..courseName = courseName
      ..sectionId = sectionId
      ..scheduledEndTime = endTime
      ..verifiedStudentIds = [];

    await _isar!.writeTxn(() async {
      await _isar!.activeSessions.put(session);
    });

    Log.i(
        '🚀 [SessionManager] Session $sessionId persisted: $courseName by $facultyName');
  }

  /// Check if there's an active session that hasn't expired
  static Future<ActiveSession?> getResumeableSession() async {
    final now = TimeSyncService.timeNow;
    final session = await _isar!.activeSessions
        .filter()
        .scheduledEndTimeGreaterThan(now)
        .findFirst();

    if (session != null) {
      Log.i('[SessionManager] Found resumeable session: ${session.sessionId}');
    }
    return session;
  }

  // REPLACED BY VOLATILE MEMORY LOGIC in v5.2
  // static Future<String?> getSessionSecret(String sessionId) async { ... }

  static Future<void> addVerifiedStudent(
      String sessionId, String studentId) async {
    final session = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    if (session != null && !session.verifiedStudentIds.contains(studentId)) {
      session.verifiedStudentIds.add(studentId);
      await _isar!.writeTxn(() async {
        await _isar!.activeSessions.put(session);
      });
    }
  }

  /// Verify-before-navigate: read back a session by ID to confirm teardown.
  static Future<ActiveSession?> getSession(String sessionId) async {
    return await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
  }

  static Future<void> clearSession(String sessionId) async {
    await _isar!.writeTxn(() async {
      await _isar!.activeSessions
          .filter()
          .sessionIdEqualTo(sessionId)
          .deleteAll();
    });
    Log.i('[SessionManager] Session $sessionId wiped from Isar.');
  }

  static Future<void> recordCompletedSession({
    required String slotId,
    required String sessionId,
    required String courseName,
    required String facultyName,
    required int attendeeCount,
  }) async {
    final completed = CompletedSession()
      ..slotId = slotId
      ..sessionId = sessionId
      ..completedAt = TimeSyncService.timeNow
      ..courseName = courseName
      ..facultyName = facultyName
      ..attendeeCount = attendeeCount;

    await _isar!.writeTxn(() async {
      final existing = await _isar!.completedSessions
          .filter()
          .slotIdEqualTo(slotId)
          .findFirst();
      if (existing != null) {
        completed.id = existing.id;
      }
      await _isar!.completedSessions.put(completed);
    });

    Log.i(
        '✅ [SessionManager] Slot $slotId marked as completed: $courseName ($attendeeCount attendees)');
  }

  static Future<bool> isSlotCompleted(String slotId) async {
    final completed = await _isar!.completedSessions
        .filter()
        .slotIdEqualTo(slotId)
        .findFirst();
    return completed != null;
  }

  static Future<Set<String>> getCompletedSlotIds() async {
    final all = await _isar!.completedSessions.where().findAll();
    return all.map((c) => c.slotId).toSet();
  }

  static Future<void> clearCompletedSessionsForDay(int dayOfWeek) async {
    final allCompleted = await _isar!.completedSessions.where().findAll();
    if (allCompleted.isNotEmpty) {
      await _isar!.writeTxn(() async {
        for (final c in allCompleted) {
          await _isar!.completedSessions.delete(c.id);
        }
      });
      Log.i(
          '🧹 [SessionManager] Cleaned ${allCompleted.length} completed-session records for new day.');
    }
  }
}
