import 'package:isar/isar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../services/session_manager.dart';
import '../../models/isar_schemas.dart';
import '../../services/hardware_fingerprint_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/time_sync_service.dart';
import '../../core/utils/logger.dart';
import 'auth_repository.dart';

abstract class IDeviceRepository {
  Future<bool> isRegistered();
  Future<DeviceRegistration?> getRegistration();
  Future<void> clearRegistration();
  Future<void> performMigrationBridge();
  Future<void> sendHeartbeat({
    required String screenState,
    required int uptimeSeconds,
    required String appVersion,
  });
  Future<void> syncTimetable({bool fullSync = false});
  Stream<List<TimetableEntry>> watchTodaySchedule(DeviceRegistration registration);
  Stream<Map<String, dynamic>?> watchActiveSession(DeviceRegistration registration);
  Stream<Map<String, dynamic>?> watchSpecificSession(String sessionId);
  Future<List<TimetableEntry>> getTodayTimeline();
  Future<List<TimetableEntry>> getWeeklyTimeline();
  Future<TimetableEntry?> getCurrentSlot();
}

class DeviceRepository implements IDeviceRepository {
  final Isar _isar;
  final IAuthRepository _authRepository;

  DeviceRepository(this._isar, this._authRepository);

  @override
  Future<bool> isRegistered() async {
    final reg = await _isar.deviceRegistrations.where().findFirst();
    return reg != null && reg.smartBoardId.isNotEmpty;
  }

  @override
  Future<DeviceRegistration?> getRegistration() async {
    return await _isar.deviceRegistrations.where().findFirst();
  }

  @override
  Future<void> clearRegistration() async {
    await SecureStorageService.clearAll();
    await _isar.writeTxn(() async {
      await _isar.deviceRegistrations.clear();
      await _isar.timetableEntrys.clear();
      await _isar.activeSessions.clear();
    });
    Log.w('[DeviceRepository] Registration cleared.');
  }

  @override
  Future<void> performMigrationBridge() async {
    try {
      final reg = await getRegistration();
      final hasToken = await SecureStorageService.getRefreshToken() != null;

      if (reg != null && reg.smartBoardId.isNotEmpty && !hasToken) {
        Log.i('[MigrationBridge] Detected legacy registration for ${reg.smartBoardId}. Accountability login required.');
        // Silent migration is disabled in the new Accountable Device model.
        // The device will prompt for Admin Authentication on next boot.
      }
    } catch (e) {
      Log.e('[MigrationBridge] Error during migration: $e');
    }
  }

  @override
  Future<void> sendHeartbeat({
    required String screenState,
    required int uptimeSeconds,
    required String appVersion,
  }) async {
    try {
      await (_authRepository as AuthRepository).apiClient.dio.post(
        '/api/v1/device/heartbeat',
        data: {
          'screen_state': screenState,
          'uptime_seconds': uptimeSeconds,
          'app_version': appVersion,
          'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      Log.w('[DeviceRepository] Heartbeat failed: $e');
    }
  }

  @override
  Future<void> syncTimetable({bool fullSync = false}) async {
    final registration = await getRegistration();
    if (registration == null) return;

    try {
      final classroomId = registration.classroomId ?? registration.smartBoardId;
      final now = DateTime.now();
      final dayName = _getDayNameString(now);

      var query = FirebaseFirestore.instance
          .collection('timetable_slots')
          .where('classroom_id', isEqualTo: classroomId);

      if (!fullSync) {
        query = query.where('day_of_week', isEqualTo: dayName);
      }

      final snapshot = await query.get();
      final entries = snapshot.docs.map((doc) {
        final data = doc.data();
        return TimetableEntry()
          ..dayOfWeek = _getDayNumber(data['day_of_week'] ?? dayName)
          ..startTime = data['start_time'] ?? ''
          ..endTime = data['end_time'] ?? ''
          ..courseName = data['subject_name'] ?? 'Class'
          ..facultyName = data['faculty_name'] ?? 'Professor'
          ..sectionId = data['section_id']?.toString() ?? 'N/A'
          ..slotId = doc.id;
      }).toList();

      await _updateIsarCache(entries, fullSync ? null : now.weekday);
    } catch (e) {
      Log.e('[DeviceRepository] Timetable sync failed: $e');
    }
  }

  @override
  Stream<List<TimetableEntry>> watchTodaySchedule(DeviceRegistration registration) {
    final now = DateTime.now();
    final dayName = _getDayNameString(now);
    final classroomId = registration.classroomId ?? registration.smartBoardId;

    return FirebaseFirestore.instance
        .collection('timetable_slots')
        .where('classroom_id', isEqualTo: classroomId)
        .where('day_of_week', isEqualTo: dayName)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return TimetableEntry()
              ..dayOfWeek = now.weekday
              ..startTime = data['start_time'] ?? ''
              ..endTime = data['end_time'] ?? ''
              ..courseName = data['subject_name'] ?? 'Unknown'
              ..facultyName = data['faculty_name'] ?? 'Unknown'
              ..sectionId = data['section_id']?.toString() ?? 'N/A'
              ..slotId = doc.id;
          }).toList();
        });
  }

  @override
  Stream<Map<String, dynamic>?> watchActiveSession(DeviceRegistration registration) {
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

  @override
  Stream<Map<String, dynamic>?> watchSpecificSession(String sessionId) {
    return FirebaseFirestore.instance
        .collection('ActiveSessions')
        .doc(sessionId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          final data = doc.data()!;
          data['session_id'] = doc.id;
          return data;
        });
  }

  @override
  Future<List<TimetableEntry>> getTodayTimeline() async {
    final now = DateTime.now();
    final dayOfWeek = now.weekday;
    return await _isar.timetableEntrys
        .filter()
        .dayOfWeekEqualTo(dayOfWeek)
        .sortByStartTime()
        .findAll();
  }

  @override
  Future<List<TimetableEntry>> getWeeklyTimeline() async {
    return await _isar.timetableEntrys
        .where()
        .sortByDayOfWeek()
        .thenByStartTime()
        .findAll();
  }

  @override
  Future<TimetableEntry?> getCurrentSlot() async {
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final today = await getTodayTimeline();
    
    for (final entry in today) {
      if (entry.startTime.compareTo(timeStr) <= 0 && timeStr.compareTo(entry.endTime) < 0) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _updateIsarCache(List<TimetableEntry> entries, int? dayOfWeek) async {
    await _isar.writeTxn(() async {
      if (dayOfWeek != null) {
        await _isar.timetableEntrys.filter().dayOfWeekEqualTo(dayOfWeek).deleteAll();
      } else {
        await _isar.timetableEntrys.clear();
      }
      await _isar.timetableEntrys.putAll(entries);
    });
  }

  String _getDayNameString(DateTime date) {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  int _getDayNumber(String dayName) {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final idx = days.indexWhere((d) => d.toLowerCase() == dayName.toLowerCase());
    return idx != -1 ? idx + 1 : DateTime.now().weekday;
  }
}
