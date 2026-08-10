import 'dart:convert';
import 'dart:math';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/isar_schemas.dart';
import '../core/security/secure_storage_service.dart';
import '../core/utils/logger.dart';
import 'time_sync_service.dart';
import '../models/board_notification.dart';

class SessionManager {
  static Isar? _isar;

  static Future<void> init() async {
    if (_isar != null) return;

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
      HydrationProfileSchema,
      HydrationRosterSchema,
      StoredNotificationSchema,
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
    String slotId = '',
  }) async {
    final session = ActiveSession()
      ..sessionId = sessionId
      ..slotId = slotId
      ..rosterCount = rosterCount
      ..facultyName = facultyName
      ..courseName = courseName
      ..sectionId = sectionId
      ..scheduledEndTime = endTime
      ..verifiedStudentIds = []
      ..lifecycle = 'active';

    await _isar!.writeTxn(() async {
      await _isar!.activeSessions.put(session);
    });

    Log.i(
        '🚀 [SessionManager] Session $sessionId persisted: $courseName by $facultyName (slot: $slotId)');
  }

  /// Check if there's an active session that hasn't expired.
  /// If [currentSlotId] is provided, only returns a session matching that slot.
  /// Uses lifecycle as the primary authority: only 'active' sessions are returned.
  static Future<ActiveSession?> getResumeableSession({String? currentSlotId}) async {
    ActiveSession? session;

    if (currentSlotId != null && currentSlotId.isNotEmpty) {
      session = await _isar!.activeSessions
          .filter()
          .slotIdEqualTo(currentSlotId)
          .lifecycleEqualTo('active')
          .findFirst();
    }

    // Fallback: any active session (no slot filter)
    session ??= await _isar!.activeSessions
        .filter()
        .lifecycleEqualTo('active')
        .findFirst();

    if (session != null) {
      Log.i('[SessionManager] Found resumeable session: ${session.sessionId} (slot: ${session.slotId})');
    }
    return session;
  }

  /// Check if a session with the given ID exists and is still 'active' in Isar.
  /// Used by IdleScreen to verify an in-memory session is still live.
  static Future<bool> sessionExists(String sessionId) async {
    final count = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .lifecycleEqualTo('active')
        .count();
    return count > 0;
  }

  /// Mark a session's lifecycle as 'completed'. Called by SummaryScreen before
  /// clearSession() so that crash recovery sees the session as ended, not active.
  static Future<void> markSessionCompleted(String sessionId) async {
    final session = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    if (session == null) return;
    await _isar!.writeTxn(() async {
      session.lifecycle = 'completed';
      await _isar!.activeSessions.put(session);
    });
    Log.i('[SessionManager] Session $sessionId lifecycle set to completed');
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

  static Future<void> clearAllActiveSessions() async {
    await _isar!.writeTxn(() async {
      await _isar!.activeSessions.where().deleteAll();
    });
    Log.i('[SessionManager] All active sessions wiped from Isar.');
  }

  /// Clears all ActiveSession records that don't match the given [currentSlotId].
  /// Called on slot transitions to prevent stale sessions from being recovered.
  static Future<void> clearSessionsNotMatching(String currentSlotId) async {
    await _isar!.writeTxn(() async {
      final all = await _isar!.activeSessions.where().findAll();
      final stale = all.where((s) => s.slotId != currentSlotId).toList();
      if (stale.isNotEmpty) {
        await _isar!.activeSessions.deleteAll(stale.map((s) => s.id).toList());
        Log.i('[SessionManager] Cleared ${stale.length} stale session(s) not matching slot $currentSlotId');
      }
    });
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
      // FIX: Only delete completed sessions from PREVIOUS days, not today.
      // The original implementation deleted ALL records regardless of day,
      // which wiped the duplicate-prevention markers on boot and caused
      // the OTP card to reappear for an already-started session.
      final now = TimeSyncService.timeNow;
      final todayStart = DateTime(now.year, now.month, now.day);
      final toDelete = allCompleted
          .where((c) => c.completedAt.isBefore(todayStart))
          .toList();
      if (toDelete.isNotEmpty) {
        await _isar!.writeTxn(() async {
          for (final c in toDelete) {
            await _isar!.completedSessions.delete(c.id);
          }
        });
        Log.i(
            '🧹 [SessionManager] Cleaned ${toDelete.length} old completed-session records '
            '(preserved ${allCompleted.length - toDelete.length} from today).');
      } else {
        Log.d('[SessionManager] No old completed-session records to clean.');
      }
    }
  }

  // ── Notification persistence ─────────────────────────────────────────────

  static StoredNotification _boardNotificationToStored(BoardNotification n) {
    final now = TimeSyncService.timeNow;
    TimetableEntry? slot;
    try {
      slot = _isar!.timetableEntrys
          .filter()
          .dayOfWeekEqualTo(now.weekday)
          .startTimeLessThan('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}')
          .endTimeGreaterThan('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}')
          .findFirstSync();
    } catch (_) {}

    final stored = StoredNotification()
      ..notificationId = n.notificationId ?? n.id
      ..localId = n.id
      ..title = n.title
      ..body = n.body
      ..type = n.type
      ..timestamp = n.timestamp
      ..read = n.read
      ..attachmentUrl = n.attachmentUrl
      ..attachmentName = n.attachmentName
      ..attachmentType = n.attachmentType
      ..attachmentSize = n.attachmentSize
      ..priority = n.priority.name
      ..precautionarySteps = n.precautionarySteps ?? []
      ..location = n.location
      ..safeExit = n.safeExit
      ..assemblyPoint = n.assemblyPoint
      ..requiresAcknowledgement = n.requiresAcknowledgement
      ..durationSeconds = n.durationSeconds
      ..displayMode = n.displayMode
      ..slotId = slot?.slotId
      ..courseName = slot?.courseName
      ..facultyName = slot?.facultyName
      ..sectionId = slot?.sectionId
      ..roomNumber = slot?.roomNumber
      ..storedAt = now;

    return stored;
  }

  static BoardNotification _storedToBoardNotification(StoredNotification s) {
    return BoardNotification(
      id: s.localId,
      title: s.title,
      body: s.body,
      type: s.type,
      timestamp: s.timestamp,
      read: s.read,
      attachmentUrl: s.attachmentUrl,
      attachmentName: s.attachmentName,
      attachmentType: s.attachmentType,
      attachmentSize: s.attachmentSize,
      priority: _parsePriority(s.priority),
      precautionarySteps: s.precautionarySteps.isEmpty ? null : s.precautionarySteps,
      location: s.location,
      safeExit: s.safeExit,
      assemblyPoint: s.assemblyPoint,
      notificationId: s.notificationId,
      requiresAcknowledgement: s.requiresAcknowledgement,
      durationSeconds: s.durationSeconds,
      displayMode: s.displayMode,
    );
  }

  static NotificationPriority _parsePriority(String p) {
    switch (p) {
      case 'emergency': return NotificationPriority.emergency;
      case 'high': return NotificationPriority.high;
      case 'normal': return NotificationPriority.normal;
      case 'low': return NotificationPriority.low;
      default: return NotificationPriority.low;
    }
  }

  static Future<void> saveNotification(BoardNotification notification) async {
    final stored = _boardNotificationToStored(notification);
    await _isar!.writeTxn(() async {
      await _isar!.storedNotifications.put(stored);
    });
    Log.d('[SessionManager] Notification persisted: ${notification.id}');
  }

  static Future<void> saveNotifications(List<BoardNotification> notifications) async {
    if (notifications.isEmpty) return;
    final stored = notifications.map(_boardNotificationToStored).toList();
    await _isar!.writeTxn(() async {
      await _isar!.storedNotifications.putAll(stored);
    });
    Log.d('[SessionManager] Persisted ${stored.length} notifications');
  }

  static Future<List<BoardNotification>> getAllStoredNotifications() async {
    final all = await _isar!.storedNotifications
        .where()
        .sortByTimestampDesc()
        .findAll();
    return all.map(_storedToBoardNotification).toList();
  }

  static Future<BoardNotification?> getStoredNotification(String notificationId) async {
    final result = await _isar!.storedNotifications
        .filter()
        .notificationIdEqualTo(notificationId)
        .findFirst();
    return result != null ? _storedToBoardNotification(result) : null;
  }

  static Future<void> deleteStoredNotification(String notificationId) async {
    await _isar!.writeTxn(() async {
      await _isar!.storedNotifications
          .filter()
          .notificationIdEqualTo(notificationId)
          .deleteAll();
    });
  }

  static Future<void> deleteStoredNotifications(List<String> notificationIds) async {
    await _isar!.writeTxn(() async {
      await _isar!.storedNotifications.deleteAllByNotificationId(notificationIds);
    });
  }

  static Future<void> markStoredNotificationRead(String notificationId) async {
    await _isar!.writeTxn(() async {
      final existing = await _isar!.storedNotifications
          .filter()
          .notificationIdEqualTo(notificationId)
          .findFirst();
      if (existing != null) {
        existing.read = true;
        await _isar!.storedNotifications.put(existing);
      }
    });
  }

  static Future<int> getUnreadNotificationCount() async {
    return await _isar!.storedNotifications
        .filter()
        .readEqualTo(false)
        .count();
  }

  static Future<List<BoardNotification>> getStoredNotificationsByType(String type) async {
    final results = await _isar!.storedNotifications
        .filter()
        .typeEqualTo(type)
        .sortByTimestampDesc()
        .findAll();
    return results.map(_storedToBoardNotification).toList();
  }

  static Future<void> clearAllStoredNotifications() async {
    await _isar!.writeTxn(() async {
      await _isar!.storedNotifications.where().deleteAll();
    });
    Log.i('[SessionManager] All stored notifications cleared');
  }

  static Future<void> saveAttendanceSnapshot({
    required String sessionId,
    required List<int> presentIndices,
    required List<int> absentIndices,
  }) async {
    final session = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    if (session == null) {
      Log.w('[SessionManager] No active session $sessionId to save snapshot to.');
      return;
    }
    await _isar!.writeTxn(() async {
      session.presentIndices = presentIndices;
      session.absentIndices = absentIndices;
      await _isar!.activeSessions.put(session);
    });
    Log.i('[SessionManager] Attendance snapshot saved for $sessionId (${presentIndices.length} present, ${absentIndices.length} absent)');
  }

  static Future<(List<int> present, List<int> absent)?> loadAttendanceSnapshot(String sessionId) async {
    final session = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    if (session == null) return null;

    // If the session lifecycle is 'completed', the snapshot is stale.
    // Clear it and return null so crash recovery doesn't resurrect old marks.
    if (session.lifecycle == 'completed') {
      Log.i('[SessionManager] Snapshot for $sessionId is completed — clearing.');
      await clearAttendanceSnapshot(sessionId);
      return null;
    }

    return (session.presentIndices, session.absentIndices);
  }

  /// Wipe the attendance snapshot (presentIndices/absentIndices) from an
  /// ActiveSession without deleting the session itself. Called when starting
  /// a fresh session to prevent stale marks from a previous session leaking in.
  static Future<void> clearAttendanceSnapshot(String sessionId) async {
    final session = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    if (session == null) return;
    await _isar!.writeTxn(() async {
      session.presentIndices = [];
      session.absentIndices = [];
      await _isar!.activeSessions.put(session);
    });
    Log.i('[SessionManager] Attendance snapshot cleared for $sessionId');
  }

  /// Save pending taps for offline recovery
  static Future<void> savePendingTaps({
    required String sessionId,
    required List<Map<String, dynamic>> taps,
  }) async {
    final session = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    if (session == null) {
      Log.w('[SessionManager] No active session $sessionId to save pending taps to.');
      return;
    }
    await _isar!.writeTxn(() async {
      // Store as JSON string in a field (assuming we have a pendingTapsJson field)
      // For now, we'll use a simple approach with the existing fields
      session.pendingTapsJson = taps.isNotEmpty ? jsonEncode(taps) : null;
      await _isar!.activeSessions.put(session);
    });
    Log.i('[SessionManager] ${taps.length} pending taps saved for $sessionId');
  }

  /// Clear pending taps after successful sync
  static Future<void> clearPendingTaps({required String sessionId}) async {
    final session = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    if (session == null) return;
    await _isar!.writeTxn(() async {
      session.pendingTapsJson = null;
      await _isar!.activeSessions.put(session);
    });
    Log.i('[SessionManager] Pending taps cleared for $sessionId');
  }

  /// Load pending taps for sync
  static Future<List<Map<String, dynamic>>> loadPendingTaps(String sessionId) async {
    final session = await _isar!.activeSessions
        .filter()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    if (session?.pendingTapsJson == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(session!.pendingTapsJson!);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      Log.e('[SessionManager] Failed to decode pending taps: $e');
      return [];
    }
  }
}
