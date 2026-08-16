import 'package:isar/isar.dart';

import '../../core/security/secure_storage_service.dart';
import '../../core/utils/logger.dart';
import '../../models/isar_schemas.dart';
import '../../services/api_service.dart';
import '../../services/hydration_service.dart';
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
  Future<void> hydrateFromServer();
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

  // ─── Hydration (replaces Firestore listeners) ───────────────────────────

  @override
  Future<void> hydrateFromServer() async {
    try {
      final result = await HydrationService.hydrate(isar: _isar);

      if (result.error != null) {
        Log.w('[DeviceRepository] Hydration had errors: ${result.error}');
      }

      final allEntries = await getWeeklyTimeline();
      TimetableCache().updateAll(allEntries);
      Log.i('[DeviceRepository] Timetable cache refreshed after hydration (changed=${result.changed})');
    } catch (e) {
      Log.e('[DeviceRepository] Hydration failed: $e');
      rethrow;
    }
  }

  @override
  Future<List<TimetableEntry>> getTodayTimeline() async {
    final dayOfWeek = TimeSyncService.timeNow.weekday;
    final entries = await _isar.timetableEntrys
        .filter()
        .dayOfWeekEqualTo(dayOfWeek)
        .sortByStartTime()
        .findAll();
    Log.d('[DeviceRepository] getTodayTimeline: weekday=$dayOfWeek, '
        'totalInDb=${await _isar.timetableEntrys.count()}, '
        'todayCount=${entries.length}');
    return entries;
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
      if (entry.isBreak) continue;
      if (entry.slotType != 'regular') continue;
      if (entry.startTime.compareTo(timeStr) <= 0 &&
          timeStr.compareTo(entry.endTime) < 0) {
        return entry;
      }
    }
    return null;
  }

}
