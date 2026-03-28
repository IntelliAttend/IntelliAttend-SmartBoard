import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/isar_schemas.dart';

class SessionManager {
  static Isar? _isar;
  static const _storage = FlutterSecureStorage();
  
  static Future<void> init() async {
    if (_isar != null) return;
    
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [ActiveSessionSchema, QueuedScanSchema],
      directory: dir.path,
    );
    print('[SessionManager] Isar Vault Initialized at ${dir.path}');
  }

  static Isar get isar => _isar!;

  /// PHASE 3: Persist session to Isar and Secure Storage
  static Future<void> saveSession({
    required String sessionId,
    required String sessionSecret,
    required int rosterCount,
    required String facultyName,
    required DateTime endTime,
  }) async {
    // 1. Store metadata in Isar (for quick listing/resume)
    final session = ActiveSession()
      ..sessionId = sessionId
      ..rosterCount = rosterCount
      ..facultyName = facultyName
      ..courseName = 'CS101' // Mock for now
      ..sectionId = 'SEC-A'
      ..scheduledEndTime = endTime
      ..verifiedStudentIds = [];

    await _isar!.writeTxn(() async {
      await _isar!.activeSessions.put(session);
    });

    // 2. Store the sensitive seed in Hardware Keystore (Zero-Trust)
    await _storage.write(key: 'secret_$sessionId', value: sessionSecret);
    print('[SessionManager] Session $sessionId persisted to Isar & SecureStorage.');
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

  static Future<String?> getSessionSecret(String sessionId) async {
    return await _storage.read(key: 'secret_$sessionId');
  }

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
    await _storage.delete(key: 'secret_$sessionId');
    print('[SessionManager] Session $sessionId wiped.');
  }
}
