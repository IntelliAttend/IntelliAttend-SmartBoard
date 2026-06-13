import 'package:isar/isar.dart';

import '../../core/config/firestore_schema.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/logger.dart';
import '../../models/isar_schemas.dart';
import '../../services/api_service.dart';
import '../../services/firestore_rest_client.dart';
import '../../services/timetable_cache.dart';
import '../../services/time_sync_service.dart';
import 'auth_repository.dart';

/// IDeviceRepository — board-side reads / writes that touch device identity,
/// timetable cache, and live session state.
///
/// Timetable data is read from the local Isar cache (synced via one-shot REST).
/// No Firestore snapshot listeners are used, eliminating unnecessary read costs.
abstract class IDeviceRepository {
  Future<bool> isRegistered();
  Future<DeviceRegistration?> getRegistration();
  Future<void> clearRegistration();
  Future<void> performMigrationBridge();
  Future<void> sendHeartbeat({
    required String smartBoardId,
    required String hardwareId,
    required String screenState,
    required int uptimeSeconds,
    required String appVersion,
  });
  Future<void> syncTimetable({bool fullSync = false});
  Future<List<TimetableEntry>> getTodayTimeline();
  Future<List<TimetableEntry>> getWeeklyTimeline();
  Future<TimetableEntry?> getCurrentSlot();
}

class DeviceRepository implements IDeviceRepository {
  final Isar _isar;

  DeviceRepository(this._isar, IAuthRepository authRepository);

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
        Log.i('[MigrationBridge] Legacy registration for ${reg.smartBoardId} '
            'without auth tokens — admin login required.');
      }
    } catch (e) {
      Log.e('[MigrationBridge] Error during migration: $e');
    }
  }

  @override
  Future<void> sendHeartbeat({
    required String smartBoardId,
    required String hardwareId,
    required String screenState,
    required int uptimeSeconds,
    required String appVersion,
  }) async {
    try {
      await ApiService.sendHeartbeatV2(
        smartBoardId: smartBoardId,
        screenState: screenState,
        uptimeSeconds: uptimeSeconds,
        appVersion: appVersion,
      );
    } catch (e) {
      Log.w('[DeviceRepository] Heartbeat failed: $e');
    }
  }

  // ─── Timetable sync (one-shot, called on boot / reconnect) ──────────────

  @override
  Future<void> syncTimetable({bool fullSync = false}) async {
    final registration = await getRegistration();
    if (registration == null) return;

    try {
      final smartBoardId = registration.smartBoardId;
      final now = TimeSyncService.timeNow;
      final dayName = _getDayNameString(now);

      final filters = <String, dynamic>{FirestoreSchema.fieldSmartBoardId: smartBoardId};
      if (!fullSync) filters[FirestoreSchema.fieldDayOfWeek] = dayName;

      final docs = await FirestoreRestClient.runQuery(
        collection: FirestoreSchema.timetableSlots,
        where: filters,
      );

      if (docs.isEmpty) {
        Log.w('[DeviceRepository] syncTimetable returned 0 docs — preserving existing cache');
        return;
      }

      final entries = docs.map(_entryFromDoc).toList();
      final allEntries = await _reconcileEntries(entries, dayFilter: fullSync ? null : now.weekday);
      TimetableCache().updateAll(allEntries);
    } catch (e) {
      Log.e('[DeviceRepository] Timetable sync failed: $e');
    }
  }

  @override
  Future<List<TimetableEntry>> getTodayTimeline() async {
    final dayOfWeek = TimeSyncService.timeNow.weekday;
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
    final now = TimeSyncService.timeNow;
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final today = await getTodayTimeline();

    for (final entry in today) {
      if (entry.startTime.compareTo(timeStr) <= 0 &&
          timeStr.compareTo(entry.endTime) < 0) {
        return entry;
      }
    }
    return null;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Convert a Firestore REST document (flattened) into a [TimetableEntry].
  /// Matches the field semantics established earlier:
  ///   - `subject_name`  → courseName
  ///   - `faculty_id` or first of `faculty_emails` → facultyName (the
  ///     IdleScreen UI formats email → display name)
  ///   - `section_id`     → sectionId
  TimetableEntry _entryFromDoc(Map<String, dynamic> data) {
    final facultyEmail = data[FirestoreSchema.fieldFacultyId]?.toString() ??
        (data[FirestoreSchema.fieldFacultyEmails] as List?)?.firstOrNull?.toString() ??
        '';
    return TimetableEntry()
      ..slotId = data[FirestoreSchema.fieldDocId]?.toString() ?? ''
      ..dayOfWeek = _getDayNumber(data[FirestoreSchema.fieldDayOfWeek]?.toString() ?? '')
      ..startTime = data[FirestoreSchema.fieldStartTime]?.toString() ?? ''
      ..endTime = data[FirestoreSchema.fieldEndTime]?.toString() ?? ''
      ..courseName = data[FirestoreSchema.fieldSubjectName]?.toString() ?? 'Class'
      ..facultyName = facultyEmail
      ..sectionId = data[FirestoreSchema.fieldSectionId]?.toString() ?? 'N/A';
  }

  /// Upserts [incoming] entries into Isar by slotId, then deletes any
  /// existing entries that are no longer present in the synced set.
  ///
  /// When [dayFilter] is non-null, stale deletion is scoped to that day so
  /// day-specific syncs don't touch other days' data.  Returns the full
  /// (possibly multi-day) timeline so the caller can refresh the in-memory
  /// cache with a single read.
  ///
  /// CRITICAL: This method NEVER clears the entire collection.  On network
  /// failure or empty server response the existing local data is preserved
  /// intact, keeping the app fully functional offline.
  Future<List<TimetableEntry>> _reconcileEntries(
    List<TimetableEntry> incoming, {
    int? dayFilter,
  }) async {
    final existingAll = await _isar.timetableEntrys.where().findAll();
    final existingBySlotId = {for (final e in existingAll) e.slotId: e};

    final incomingSlotIds = incoming.map((e) => e.slotId).toSet();

    await _isar.writeTxn(() async {
      for (final entry in incoming) {
        final existing = existingBySlotId[entry.slotId];
        if (existing != null) {
          existing
            ..dayOfWeek = entry.dayOfWeek
            ..startTime = entry.startTime
            ..endTime = entry.endTime
            ..courseName = entry.courseName
            ..facultyName = entry.facultyName
            ..sectionId = entry.sectionId;
          await _isar.timetableEntrys.put(existing);
        } else {
          await _isar.timetableEntrys.put(entry);
        }
      }

      for (final existing in existingAll) {
        if (existing.slotId.isEmpty) continue;
        if (incomingSlotIds.contains(existing.slotId)) continue;
        if (dayFilter != null && existing.dayOfWeek != dayFilter) continue;
        await _isar.timetableEntrys.delete(existing.id);
      }

      // Dedup: if a concurrent sync created two entries with the same slotId,
      // keep only the one with the lowest auto-increment id.
      final after = await _isar.timetableEntrys.where().findAll();
      final seen = <String, int>{};
      for (final e in after) {
        final first = seen[e.slotId];
        if (first != null) {
          await _isar.timetableEntrys.delete(e.id);
        } else {
          seen[e.slotId] = e.id;
        }
      }
    });

    return await _isar.timetableEntrys
        .where()
        .sortByDayOfWeek()
        .thenByStartTime()
        .findAll();
  }

  String _getDayNameString(DateTime date) {
    return dayNames[date.weekday - 1];
  }

  int _getDayNumber(String dayName) {
    final idx =
        dayNames.indexWhere((d) => d.toLowerCase() == dayName.toLowerCase());
    return idx != -1 ? idx + 1 : TimeSyncService.timeNow.weekday;
  }
}
