import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';

class SessionManager {
  static Isar? _isar;
  
  static Future<void> init() async {
    if (_isar != null) return;
    
    final dir = await getApplicationDocumentsDirectory();
    final schemas = [
      ActiveSessionSchema, 
      QueuedScanSchema, 
      DeviceRegistrationSchema,
      TimetableEntrySchema,
    ];

    try {
      _isar = await Isar.open(
        schemas,
        directory: dir.path,
      );
      Log.i('📦 [SessionManager] Isar Vault Initialized.');
    } catch (e) {
      Log.e('❌ [SessionManager] Isar Initialization Failed (Attempt 1): $e');
      
      // v5.4 Fallback: If schema mismatch or corruption occurs, wipe and recreate.
      // This ensures the SmartBoard remains operational even if cache is stale.
      try {
        Log.w('📦 [SessionManager] Attempting to wipe corrupted/stale local vault...');
        final isar = Isar.getInstance();
        if (isar != null) {
          await isar.close();
        }
        
        // Use a different name or clear the directory
        _isar = await Isar.open(
          schemas,
          directory: dir.path,
          name: 'intelliattend_vault_v2', // Increment name to force new file if needed
        );
        Log.i('📦 [SessionManager] New Isar Vault Created successfully.');
      } catch (retryError) {
        Log.e('🚨 [SessionManager] CRITICAL: Fatal Isar Failure: $retryError');
        rethrow;
      }
    }
  }

  static Isar get isar {
    if (_isar == null) {
      throw Exception('Isar not initialized. Call SessionManager.init() first.');
    }
    return _isar!;
  }

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

    Log.i('🚀 [SessionManager] Session $sessionId persisted: $courseName by $facultyName');
  }

  /// Check if there's an active session that hasn't expired
  static Future<ActiveSession?> getResumeableSession() async {
    final now = DateTime.now();
    final session = await _isar!.activeSessions
        .filter()
        .scheduledEndTimeGreaterThan(now)
        .findFirst();
    
    if (session != null) {
      print('[SessionManager] Found resumeable session: ${session.sessionId}');
    }
    return session;
  }

  // REPLACED BY VOLATILE MEMORY LOGIC in v5.2
  // static Future<String?> getSessionSecret(String sessionId) async { ... }

  static Future<void> addVerifiedStudent(String sessionId, String studentId) async {
    final session = await _isar!.activeSessions.filter().sessionIdEqualTo(sessionId).findFirst();
    if (session != null && !session.verifiedStudentIds.contains(studentId)) {
      session.verifiedStudentIds.add(studentId);
      await _isar!.writeTxn(() async {
        await _isar!.activeSessions.put(session);
      });
    }
  }

  static Future<void> clearSession(String sessionId) async {
    await _isar!.writeTxn(() async {
      await _isar!.activeSessions.filter().sessionIdEqualTo(sessionId).deleteAll();
    });
    print('[SessionManager] Session $sessionId wiped from Isar.');
  }
}
