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
  /// v5.5: Also validates that the registration is not corrupted.
  static Future<bool> isRegistered() async {
    final reg = await _isar.deviceRegistrations.where().findFirst();
    if (reg == null) return false;
    
    // If registration is corrupted (missing ID) or legacy (missing classroomId),
    // we wipe it to force a clean metadata sync.
    if (reg.smartBoardId.isEmpty || reg.classroomId == null) {
      Log.w('⚠️ [DeviceService] Corrupted or Legacy registration found. Wiping for fresh sync...');
      await _isar.writeTxn(() => _isar.deviceRegistrations.clear());
      return false;
    }
    
    return true;
  }

  /// Retrieves the permanent registration details.
  /// Automatically heals missing metadata (like classroomId) from Firestore if needed.
  static Future<DeviceRegistration?> getRegistration() async {
    final reg = await _isar.deviceRegistrations.where().findFirst();
    if (reg != null && reg.classroomId == null) {
      if (reg.smartBoardId.isEmpty) {
        Log.w('⚠️ [DeviceService] Registration exists but smartBoardId is empty. Skipping healing.');
        return reg;
      }
      Log.i('🔧 [DeviceService] Missing classroomId for ${reg.smartBoardId}. Attempting to heal...');
      try {
        final doc = await FirebaseFirestore.instance.collection('smart_boards').doc(reg.smartBoardId).get();
        if (doc.exists) {
          final data = doc.data()!;
          final classroomId = data['classroom_id']?.toString() ?? data['classroomId']?.toString();
          if (classroomId != null) {
            await _isar.writeTxn(() async {
              reg.classroomId = classroomId;
              await _isar.deviceRegistrations.put(reg);
            });
            Log.i('✅ [DeviceService] Healed metadata: classroomId=$classroomId');
          }
        }
      } catch (e) {
        Log.w('⚠️ [DeviceService] Metadata healing failed: $e');
      }
    }
    return reg;
  }

  /// The active SmartBoard ID for identification and Firestore queries.
  static Future<String?> getSmartBoardId() async {
    final reg = await getRegistration();
    return reg?.smartBoardId;
  }

  /// Step1: Request Administrative OTP to authorize this hardware.
  static Future<void> requestOtp({required String smartBoardId}) async {
    await ApiService.requestRegistrationOtp(smartBoardId: smartBoardId);
  }

  /// Step2: Completes the One-Time Registration with the Backend using the Admin OTP.
  /// Binds the hardware fingerprint to the room in the server's database.
  /// v5.4: Now extracts and stores cryptographic tokens from server response.
  static Future<void> registerWithOtp({
    required String smartBoardId,
    required String otp,
    required String deviceName,
    int rosterCount = 60,
  }) async {
    // 1. Call Backend Handshake and capture response
    final response = await ApiService.verifyRegistrationOtp(
      smartBoardId: smartBoardId,
      otp: otp,
      deviceName: deviceName,
    );

    // Identity is strictly the SmartBoard ID
    final finalBoardId = smartBoardId;
    
    final apiKey = response['api_key']?.toString() ?? response['apiKey']?.toString();
    final accessToken = response['access_token']?.toString() ?? response['accessToken']?.toString();
    final refreshToken = response['refresh_token']?.toString() ?? response['refreshToken']?.toString();
    final expiryMs = response['expires_in_ms'] ?? response['expiresInMs'];

    // Store tokens securely
    if (apiKey != null && apiKey.isNotEmpty) {
      await SecureStorageService.storeApiKey(apiKey);
    }

    if (accessToken != null && accessToken.isNotEmpty) {
      int expiry;
      if (expiryMs is int) {
        expiry = expiryMs;
      } else if (expiryMs is String) {
        expiry = int.tryParse(expiryMs) ?? (DateTime.now().millisecondsSinceEpoch + 900000);
      } else {
        expiry = DateTime.now().millisecondsSinceEpoch + 900000;
      }
      await SecureStorageService.storeAccessToken(accessToken, expiry);
    }

    if (refreshToken != null && refreshToken.isNotEmpty) {
      await SecureStorageService.storeRefreshToken(refreshToken);
    }

    final hardwareId = await HardwareFingerprintService.getWindowsFingerprint();
    
    // 2. Fetch Metadata from Firestore (using board_id as document ID)
    String roomName = deviceName;
    String building = 'Main Campus';
    String department = 'Academic';
    int capacity = rosterCount;
    String? classroomId;

    try {
      final doc = await FirebaseFirestore.instance.collection('smart_boards').doc(finalBoardId).get();
      if (doc.exists) {
        final data = doc.data()!;
        roomName = data['room_name'] ?? data['roomName'] ?? roomName;
        building = data['building'] ?? building;
        department = data['department'] ?? department;
        capacity = data['capacity'] ?? capacity;
        // Resolve logical classroom ID for queries (e.g. 'room_4208')
        classroomId = data['classroom_id']?.toString() ?? data['classroomId']?.toString();
        Log.i('📡 [DeviceService] Metadata synced for $finalBoardId. Classroom ID: $classroomId');
      }
    } catch (e) {
      Log.w('⚠️ [DeviceService] Firestore metadata sync failed: $e');
    }

    // 3. Persist to Local Vault
    final reg = DeviceRegistration()
      ..smartBoardId = finalBoardId
      ..classroomId = classroomId
      ..hardwareId = hardwareId
      ..roomName = roomName
      ..building = building
      ..department = department
      ..capacity = capacity
      ..registrationDate = DateTime.now()
      ..apiKey = apiKey
      ..accessToken = accessToken
      ..refreshToken = refreshToken;

    await _isar.writeTxn(() async {
      await _isar.deviceRegistrations.clear();
      await _isar.timetableEntrys.clear();
      await _isar.deviceRegistrations.put(reg);
    });
    
    Log.i('✅ [DeviceService] Bound to SmartBoard ID: $finalBoardId');

    // v5.4: Trigger a FULL timetable sync immediately after registration
    // This ensures the device has the entire week's schedule cached for offline use.
    await syncTimetable(fullSync: true);
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
  /// Pulls timetable from Firestore directly into Isar cache.
  /// [fullSync]: If true, fetches the entire week. If false, only today.
  static Future<void> syncTimetable({bool fullSync = false}) async {
    final registration = await getRegistration();
    if (registration == null) return;

    try {
      // v5.2: Sync server time
      final serverTime = await ApiService.syncTime();
      Log.i('⏰ [DeviceService] Server Time Synced: $serverTime');
    } catch (e) {
      Log.w('⚠️ [DeviceService] Time sync failed (continuing): $e');
    }

    // Pull from Firestore directly
    if (Firebase.apps.isEmpty) {
      Log.w('⚠️ [DeviceService] Firebase not initialized. Cannot sync from Firestore.');
      return;
    }

    try {
      final now = DateTime.now();
      final dayName = _getDayNameString(now);
      final dayOfWeek = now.weekday;
      
      // Use logical classroomId for timetable query, fallback to smartBoardId
      final classroomId = registration.classroomId ?? registration.smartBoardId;

      Log.i('📡 [DeviceService] Syncing from Firestore (Full=$fullSync): room=$classroomId');

      var query = FirebaseFirestore.instance
          .collection('timetable_slots')
          .where('classroom_id', isEqualTo: classroomId);

      if (!fullSync) {
        query = query.where('day_of_week', isEqualTo: dayName);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        Log.w('⚠️ [DeviceService] No timetable slots found for room=$classroomId');
        if (!fullSync) {
          await _updateIsarCache([], dayOfWeek);
        } else {
          await _updateIsarCache([], null);
        }
        return;
      }

      final entries = snapshot.docs.map((doc) {
        final data = doc.data();
        final slotDayName = data['day_of_week']?.toString() ?? dayName;
        
        return TimetableEntry()
          ..dayOfWeek = _getDayNumber(slotDayName)
          ..startTime = data['start_time'] ?? ''
          ..endTime = data['end_time'] ?? ''
          ..courseName = data['subject_name'] ?? 'Class'
          ..facultyName = data['faculty_name'] ?? (data['faculty_emails'] is List ? (data['faculty_emails'] as List).join(', ') : data['faculty_emails']?.toString() ?? 'Professor')
          ..sectionId = data['section_id']?.toString() ?? 'N/A';
      }).toList();

      // Update Isar cache
      await _updateIsarCache(entries, fullSync ? null : dayOfWeek);

      Log.i('🏛️ [DeviceService] Sync complete. Found ${entries.length} slots.');
    } catch (e, stackTrace) {
      Log.e('❌ [DeviceService] Firestore sync failed: $e');
      Log.e('❌ [DeviceService] Stack trace: $stackTrace');
    }
  }

  /// Real-time Firestore stream for today's schedule for this room.
  /// Mirrors the Faculty/Student app pattern using Firestore snapshots().
  static Stream<List<TimetableEntry>> watchTodaySchedule(DeviceRegistration registration) {
    final now = DateTime.now();
    final dayName = _getDayNameString(now);
    final dayOfWeek = now.weekday;
    
    // Use logical classroomId for queries
    final queryId = registration.classroomId ?? registration.smartBoardId;

    return FirebaseFirestore.instance
        .collection('timetable_slots')
        .where('classroom_id', isEqualTo: queryId)
        .where('day_of_week', isEqualTo: dayName)
        .snapshots()
        .asyncMap((snapshot) async {
          Log.i('📡 [DeviceService] Firestore returned ${snapshot.docs.length} docs for $queryId on $dayName');
          final entries = snapshot.docs.map((doc) {
            final data = doc.data();
            return TimetableEntry()
              ..dayOfWeek = dayOfWeek
              ..startTime = data['start_time'] ?? ''
              ..endTime = data['end_time'] ?? ''
              ..courseName = data['subject_name'] ?? 'Unknown'
              ..facultyName = data['faculty_name'] ?? (data['faculty_emails'] is List ? (data['faculty_emails'] as List).join(', ') : data['faculty_emails']?.toString() ?? 'Unknown')
              ..sectionId = data['section_id']?.toString() ?? 'N/A';
          }).toList();

          entries.sort((a, b) => a.startTime.compareTo(b.startTime));

          // Update local Isar cache for offline resilience
          await _updateIsarCache(entries, dayOfWeek);
          
          if (entries.isEmpty) {
            Log.w('⚠️ [DeviceService] Stream update: No slots found for $dayName');
          } else {
            Log.i('🏛️ [DeviceService] Stream update: ${entries.length} slots received');
          }

          return entries;
        });
  }

  /// Real-time listener for an active session in a specific room.
  /// Allows the SmartBoard to "ignite" instantly when a professor starts a session.
  static Stream<Map<String, dynamic>?> watchActiveSession(DeviceRegistration registration) {
    final queryId = registration.classroomId ?? registration.smartBoardId;
    
    return FirebaseFirestore.instance
        .collection('ActiveSessions')
        .where('room_id', isEqualTo: queryId)
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

  static Future<void> _updateIsarCache(List<TimetableEntry> entries, int? dayOfWeek) async {
    try {
      final isar = SessionManager.isar;
      await isar.writeTxn(() async {
        if (dayOfWeek != null) {
          // Selective day update (daily sync or stream)
          await isar.timetableEntrys.filter().dayOfWeekEqualTo(dayOfWeek).deleteAll();
        } else {
          // Full cache reset (registration or maintenance sync)
          await isar.timetableEntrys.clear();
        }
        await isar.timetableEntrys.putAll(entries);
      });
      Log.i('📦 [DeviceService] Isar cache updated (${entries.length} entries)');
    } catch (e) {
      Log.e('❌ [DeviceService] Failed to update Isar cache: $e');
    }
  }

  static int _getDayNumber(String dayName) {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final idx = days.indexWhere((d) => d.toLowerCase() == dayName.toLowerCase());
    return idx != -1 ? idx + 1 : DateTime.now().weekday;
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
        final registration = await getRegistration();
        if (registration == null) return cached;

        final dayName = _getDayNameString(now);
        final queryId = (registration.classroomId ?? registration.smartBoardId).trim();
        print('📅 [DeviceService] Firestore query: room=$queryId, dayName=$dayName');
        
        final snapshot = await FirebaseFirestore.instance
            .collection('timetable_slots')
            .where('classroom_id', isEqualTo: queryId)
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
              ..facultyName = data['faculty_name'] ?? (data['faculty_emails'] is List ? (data['faculty_emails'] as List).join(', ') : data['faculty_emails']?.toString() ?? 'Unknown')
              ..sectionId = data['section_id']?.toString() ?? 'N/A';
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

  /// Fetches all timetable entries for the entire week from local cache.
  static Future<List<TimetableEntry>> getWeeklyTimeline() async {
    // We prioritize local cache for the weekly view as it's primarily for offline reference.
    final entries = await _isar.timetableEntrys
        .where()
        .sortByDayOfWeek()
        .thenByStartTime()
        .findAll();
    
    Log.i('📅 [DeviceService] Weekly timeline: ${entries.length} entries');
    return entries;
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
        final registration = await getRegistration();
        if (registration == null) return null;

        final dayName = _getDayNameString(now);
        final queryId = (registration.classroomId ?? registration.smartBoardId).trim();
        
        // Note: Simple query to avoid needing complex composite indexes immediately
        final snapshot = await FirebaseFirestore.instance
            .collection('timetable_slots')
            .where('classroom_id', isEqualTo: queryId)
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
                ..facultyName = data['faculty_name'] ?? (data['faculty_emails'] is List ? (data['faculty_emails'] as List).join(', ') : data['faculty_emails']?.toString() ?? 'Unknown')
                ..sectionId = data['section_id']?.toString() ?? 'N/A';
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
    await _isar.writeTxn(() async {
      await _isar.deviceRegistrations.clear();
      await _isar.timetableEntrys.clear();
      await _isar.activeSessions.clear();
    });
    Log.w('⚠️ [DeviceService] Registration wiped. Device is now anonymous.');
  }
}
