import 'package:isar/isar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'session_manager.dart';
import '../models/isar_schemas.dart';
import 'api_service.dart';
import '../core/utils/logger.dart';
import 'hardware_fingerprint_service.dart';
import 'secure_storage_service.dart';

class DeviceService {
  static Isar get _isar => SessionManager.isar;

  /// Checks if this SmartBoard has already been bound to a classroom.
  static Future<bool> isRegistered() async {
    final count = await _isar.deviceRegistrations.count();
    return count >0;
  }

  /// Retrieves the permanent registration details.
  static Future<DeviceRegistration?> getRegistration() async {
    return await _isar.deviceRegistrations.where().findFirst();
  }

  /// The active Room ID for this hardware.
  static Future<String?> getRoomId() async {
    final reg = await getRegistration();
    return reg?.roomId;
  }

  /// Step1: Request Administrative OTP to authorize this hardware.
  static Future<void> requestOtp({required String roomId}) async {
    await ApiService.requestRegistrationOtp(roomId: roomId);
  }

  /// Step2: Completes the One-Time Registration with the Backend using the Admin OTP.
  /// Binds the hardware fingerprint to the room in the server's database.
  /// v5.4: Now extracts and stores cryptographic tokens from server response.
  static Future<void> registerWithOtp({
    required String roomId,
    required String otp,
    required String deviceName,
    int rosterCount = 60,
  }) async {
    // 1. Call Backend Handshake (v5.3) and capture response
    final response = await ApiService.verifyRegistrationOtp(
      roomId: roomId,
      otp: otp,
      deviceName: deviceName,
    );

    // v5.4: Extract cryptographic tokens from server response
    final apiKey = response['api_key']?.toString() ?? response['apiKey']?.toString();
    final accessToken = response['access_token']?.toString() ?? response['accessToken']?.toString();
    final refreshToken = response['refresh_token']?.toString() ?? response['refreshToken']?.toString();
    final expiryMs = response['expires_in_ms'] ?? response['expiresInMs'];

    // Store tokens securely
    if (apiKey != null && apiKey.isNotEmpty) {
      await SecureStorageService.storeApiKey(apiKey);
      Log.i('🔐 [DeviceService] API Key stored securely');
    }

    if (accessToken != null && accessToken.isNotEmpty) {
      int expiry;
      if (expiryMs is int) {
        expiry = expiryMs;
      } else if (expiryMs is String) {
        expiry = int.tryParse(expiryMs) ?? (DateTime.now().millisecondsSinceEpoch + 900000);
      } else {
        expiry = DateTime.now().millisecondsSinceEpoch + 900000; // 15 min default
      }
      await SecureStorageService.storeAccessToken(accessToken, expiry);
      Log.i('🔐 [DeviceService] Access token stored (expires in 15min)');
    }

    if (refreshToken != null && refreshToken.isNotEmpty) {
      await SecureStorageService.storeRefreshToken(refreshToken);
      Log.i('🔐 [DeviceService] Refresh token stored');
    }

    final hardwareId = await HardwareFingerprintService.getWindowsFingerprint();
    
    // 2. Persist to Local Vault (Clear old registration first to avoid Unique Index violation)
    final reg = DeviceRegistration()
      ..roomId = roomId
      ..hardwareId = hardwareId
      ..roomName = deviceName
      ..building = 'Staging'
      ..department = 'CSE'
      ..capacity = rosterCount
      ..registrationDate = DateTime.now()
      ..apiKey = apiKey
      ..accessToken = accessToken
      ..refreshToken = refreshToken;

    await _isar.writeTxn(() => _isar.deviceRegistrations.clear());
    await _isar.writeTxn(() => _isar.deviceRegistrations.put(reg));
    
    Log.i('✅ [DeviceService] Hardware securely bound via OTP to Room: $roomId');
    Log.i('🔐 [DeviceService] Cryptographic tokens stored - MAC spoofing no longer possible');
  }

  /// Legacy Registration Method (v5.2 Direct Bypass)
  /// Now deprecated: Use requestOtp() and registerWithOtp() instead.
  static Future<void> register({
    required String roomId,
    required String deviceName,
    required int rosterCount,
  }) async {
    throw UnimplementedError('Direct registration is deprecated. Use OTP flow.');
  }

  /// Layer1: The Context Sync (The Bedrock)
  /// Pulls timetable from Firestore directly (same as mobile apps) into Isar cache
  static Future<void> syncTimetable() async {
    final registration = await getRegistration();
    if (registration == null) return;

    try {
      // v5.2: Sync server time
      final serverTime = await ApiService.syncTime();
      Log.i('⏰ [DeviceService] Server Time Synced: $serverTime');
    } catch (e) {
      Log.w('⚠️ [DeviceService] Time sync failed (continuing): $e');
    }

    // Pull from Firestore directly (same pattern as Faculty/Student apps)
    if (Firebase.apps.isEmpty) {
      Log.w('⚠️ [DeviceService] Firebase not initialized. Cannot sync from Firestore.');
      return;
    }

    try {
      final dayName = _getDayNameString(DateTime.now());
      final roomId = registration.roomId;

      Log.i('📡 [DeviceService] Syncing from Firestore: room=$roomId, day=$dayName');

      final snapshot = await FirebaseFirestore.instance
          .collection('timetable_slots')
          .where('classroom_id', isEqualTo: roomId)
          .where('day_of_week', isEqualTo: dayName)
          .get();

      final dayOfWeek = DateTime.now().weekday;

      if (snapshot.docs.isEmpty) {
        Log.w('⚠️ [DeviceService] No timetable slots found for room=$roomId, day=$dayName');
        // Clear Isar cache so UI shows "No Class Scheduled"
        await _updateIsarCache([], dayOfWeek);
        return;
      }
      final entries = snapshot.docs.map((doc) {
        final data = doc.data();
        return TimetableEntry()
          ..dayOfWeek = dayOfWeek
          ..startTime = data['start_time'] ?? ''
          ..endTime = data['end_time'] ?? ''
          ..courseName = data['subject_name'] ?? 'Unknown'
          ..facultyName = data['faculty_name'] ?? 'Unknown';
      }).toList();

      entries.sort((a, b) => a.startTime.compareTo(b.startTime));

      // Update Isar cache
      await _updateIsarCache(entries, dayOfWeek);

      Log.i('🏛️ [DeviceService] Synced ${entries.length} slots from Firestore.');
    } catch (e, stackTrace) {
      Log.e('❌ [DeviceService] Firestore sync failed: $e');
      Log.e('❌ [DeviceService] Stack trace: $stackTrace');
      // Don't rethrow - let the app continue with whatever data is available
    }
  }

  /// Real-time Firestore stream for today's schedule for this room.
  /// Mirrors the Faculty/Student app pattern using Firestore snapshots().
  static Stream<List<TimetableEntry>> watchTodaySchedule(String roomId) {
    final now = DateTime.now();
    final dayName = _getDayNameString(now);
    final dayOfWeek = now.weekday;
    final cleanRoomId = roomId.trim();

    return FirebaseFirestore.instance
        .collection('timetable_slots')
        .where('classroom_id', isEqualTo: cleanRoomId)
        .where('day_of_week', isEqualTo: dayName)
        .snapshots()
        .asyncMap((snapshot) async {
          final entries = snapshot.docs.map((doc) {
            final data = doc.data();
            return TimetableEntry()
              ..dayOfWeek = dayOfWeek
              ..startTime = data['start_time'] ?? ''
              ..endTime = data['end_time'] ?? ''
              ..courseName = data['subject_name'] ?? 'Unknown'
              ..facultyName = data['faculty_name'] ?? 'Unknown';
          }).toList();

          entries.sort((a, b) => a.startTime.compareTo(b.startTime));

          // Update local Isar cache for offline resilience
          await _updateIsarCache(entries, dayOfWeek);

          return entries;
        });
  }

  /// Real-time listener for an active session in a specific room.
  /// Allows the SmartBoard to "ignite" instantly when a professor starts a session.
  static Stream<Map<String, dynamic>?> watchActiveSession(String roomId) {
    return FirebaseFirestore.instance
        .collection('sessions')
        .where('classroom_id', isEqualTo: roomId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          final doc = snapshot.docs.first;
          final data = doc.data();
          data['session_id'] = doc.id;
          return data;
        });
  }

  static Future<void> _updateIsarCache(List<TimetableEntry> entries, int dayOfWeek) async {
    try {
      final isar = SessionManager.isar;
      await isar.writeTxn(() async {
        await isar.timetableEntrys.filter().dayOfWeekEqualTo(dayOfWeek).deleteAll();
        await isar.timetableEntrys.putAll(entries);
      });
      Log.i('📦 [DeviceService] Isar cache updated from Firestore stream');
    } catch (e) {
      Log.e('❌ [DeviceService] Failed to update Isar cache: $e');
    }
  }

  static String _getDayNameString(DateTime date) {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  /// Fetches all timetable entries for today.
  /// First tries local Isar cache, then falls back to Firestore directly.
  static Future<List<TimetableEntry>> getTodayTimeline() async {
    final now = DateTime.now();
    final dayOfWeek = now.weekday; // 1 (Mon) - 7 (Sun)
    
    print('📅 [DeviceService] getTodayTimeline: dayOfWeek=$dayOfWeek');
    
    // Try local Isar cache first
    final cached = await _isar.timetableEntrys
        .filter()
        .dayOfWeekEqualTo(dayOfWeek)
        .sortByStartTime()
        .findAll();
    
    print('📅 [DeviceService] Isar cache: ${cached.length} entries');
    
    if (cached.isNotEmpty) return cached;
    
    // Fall back to Firestore directly (same pattern as mobile apps)
    if (Firebase.apps.isNotEmpty) {
      try {
        final dayName = _getDayNameString(now);
        final roomId = (await getRoomId() ?? '').trim();
        print('📅 [DeviceService] Firestore query: roomId=$roomId, dayName=$dayName');
        
        final snapshot = await FirebaseFirestore.instance
            .collection('timetable_slots')
            .where('classroom_id', isEqualTo: roomId)
            .where('day_of_week', isEqualTo: dayName)
            .get();
        
        print('📅 [DeviceService] Firestore returned ${snapshot.docs.length} docs');
        
        if (snapshot.docs.isNotEmpty) {
          final entries = snapshot.docs.map((doc) {
            final data = doc.data();
            print('📅 [DeviceService] Doc: ${doc.id} -> ${data['subject_name']}');
            return TimetableEntry()
              ..dayOfWeek = dayOfWeek
              ..startTime = data['start_time'] ?? ''
              ..endTime = data['end_time'] ?? ''
              ..courseName = data['subject_name'] ?? 'Unknown'
              ..facultyName = data['faculty_name'] ?? 'Unknown';
          }).toList();
          
          entries.sort((a, b) => a.startTime.compareTo(b.startTime));
          
          // Update Isar cache
          await _updateIsarCache(entries, dayOfWeek);
          
          return entries;
        }
      } catch (e, stackTrace) {
        print('❌ [DeviceService] Firestore fallback failed: $e');
        print('❌ [DeviceService] Stack: $stackTrace');
      }
    } else {
      print('⚠️ [DeviceService] Firebase not initialized');
    }
    
    return cached; // Return empty list if nothing found
  }

  /// Finds the currently active slot based on system time.
  /// v5.4: Now checks both startTime and endTime to ensure accurate "Live" status.
  static Future<TimetableEntry?> getCurrentSlot() async {
    final now = DateTime.now();
    final dayOfWeek = now.weekday; // 1-7
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    final isar = SessionManager.isar;
    // Try Isar first: Get all classes for today, filter in memory
    final allEntries = await isar.timetableEntrys
        .filter()
        .dayOfWeekEqualTo(dayOfWeek)
        .findAll();
    
    // Find the class that has started and not yet ended
    TimetableEntry? entry;
    for (final e in allEntries) {
      if (e.startTime.compareTo(timeStr) <= 0 && timeStr.compareTo(e.endTime) < 0) {
        entry = e;
        break;
      }
    }
    
    if (entry != null) {
      return entry;
    }
    
    // Fall back to Firestore (e.g. if Isar was just cleared or first run)
    if (Firebase.apps.isNotEmpty) {
      try {
        final dayName = _getDayNameString(now);
        final roomId = (await getRoomId() ?? '').trim();
        
        // Note: Simple query to avoid needing complex composite indexes immediately
        final snapshot = await FirebaseFirestore.instance
            .collection('timetable_slots')
            .where('classroom_id', isEqualTo: roomId)
            .where('day_of_week', isEqualTo: dayName)
            .get();
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final startTime = data['start_time'] ?? '';
          final endTime = data['end_time'] ?? '';
          
          if (startTime.isNotEmpty && endTime.isNotEmpty) {
            if (startTime.compareTo(timeStr) <= 0 && endTime.compareTo(timeStr) > 0) {
              return TimetableEntry()
                ..dayOfWeek = dayOfWeek
                ..startTime = startTime
                ..endTime = endTime
                ..courseName = data['subject_name'] ?? 'Unknown'
                ..facultyName = data['faculty_name'] ?? 'Unknown';
            }
          }
        }
      } catch (e) {
        Log.e('❌ [DeviceService] getCurrentSlot Firestore fallback failed: $e');
      }
    }
    
    return null;
  }

  /// Deletes the local registration (USE WITH CAUTION - for IT maintenance only).
  static Future<void> clearRegistration() async {
    await SecureStorageService.clearAll();
    Log.w('⚠️ [DeviceService] Registration wiped. Device is now anonymous.');
  }
}
