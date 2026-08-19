import '../core/utils/logger.dart';
import '../core/security/secure_storage_service.dart';
import '../models/isar_schemas.dart';
import 'api_service.dart';
import 'package:isar/isar.dart';
import 'time_sync_service.dart';

/// Result of a hydration cycle.
class HydrationResult {
  final bool changed;
  final bool fromCache;
  final String? manifestHash;
  final String? error;

  HydrationResult({
    required this.changed,
    required this.fromCache,
    this.manifestHash,
    this.error,
  });
}

/// Client-side hydration service for SmartBoard.
///
/// Fetches the full board context from GET /api/v1/board/hydrate,
/// compares manifest_hash against locally stored value, and persists
/// only when the payload has changed.
class HydrationService {
  /// Run a full hydration cycle.
  ///
  /// Returns a [HydrationResult] describing what happened:
  /// - `changed=true` → new data was persisted
  /// - `fromCache=true` → used local Isar cache (hash matched or network error)
  /// - `manifestHash` → the remote manifest_hash (null on network error)
  static Future<HydrationResult> hydrate({required Isar isar}) async {
    try {
      final response = await ApiService.getHydrationPayload();

      final remoteHash = response['manifest_hash'] as String?;
      if (remoteHash == null) {
        Log.w('[Hydration] No manifest_hash in response');
        return _fallbackToCache(isar);
      }

      final localHash = await SecureStorageService.getManifestHash();

      if (localHash == remoteHash) {
        Log.i('[Hydration] Hash match — using local cache');
        return HydrationResult(
          changed: false,
          fromCache: true,
          manifestHash: remoteHash,
        );
      }

      Log.i('[Hydration] Hash mismatch — persisting new data');

      await _persistPayload(response, isar);

      await SecureStorageService.storeManifestHash(remoteHash);

      Log.i('[Hydration] Payload persisted successfully');
      return HydrationResult(
        changed: true,
        fromCache: false,
        manifestHash: remoteHash,
      );
    } on UnauthorizedException catch (e) {
      // Auth errors must propagate — do NOT fall back to cache.
      // This allows callers (sync button, post-login) to show proper
      // error messages instead of silently showing "already up to date".
      Log.e('[Hydration] Auth error — propagating: $e');
      rethrow;
    } catch (e) {
      Log.w('[Hydration] Network error — falling back to cache: $e');
      return _fallbackToCache(isar, error: e.toString());
    }
  }

  /// Get the locally stored manifest hash without calling the API.
  static Future<String?> getLocalManifestHash() async {
    return SecureStorageService.getManifestHash();
  }

  /// Clear the stored manifest hash (forces full re-hydration on next call).
  static Future<void> clearLocalHash() async {
    await SecureStorageService.clearManifestHash();
  }

  // ── Private ────────────────────────────────────────────────────────────

  static HydrationResult _fallbackToCache(Isar isar, {String? error}) {
    return HydrationResult(
      changed: false,
      fromCache: error == null,
      manifestHash: null,
      error: error,
    );
  }

  static Future<void> _persistPayload(
    Map<String, dynamic> payload,
    Isar isar,
  ) async {
    final profile = payload['profile'] as Map<String, dynamic>?;
    final scheduleList = payload['schedule_list'] as List<dynamic>?;
    final rosters = payload['rosters'] as Map<String, dynamic>?;

    if (profile != null) {
      await _persistProfile(profile, isar);
    }

    if (scheduleList != null) {
      await _persistSchedule(scheduleList, isar);
    }

    if (rosters != null) {
      await _persistRosters(rosters, isar);
    }
  }

  static Future<void> _persistProfile(
    Map<String, dynamic> profile,
    Isar isar,
  ) async {
    await isar.writeTxn(() async {
      await isar.hydrationProfiles.clear();
      final entry = HydrationProfile()
        ..boardId = profile['board_id']?.toString() ?? ''
        ..boardName = profile['board_name']?.toString() ?? ''
        ..roomId = profile['room_id']?.toString() ?? ''
        ..roomNumber = profile['room_number']?.toString()
        ..building = profile['building']?.toString()
        ..floor = profile['floor']?.toString()
        ..institutionId = profile['institution_id']?.toString()
        ..institutionName = profile['institution_name']?.toString()
        ..timezone = profile['timezone']?.toString()
        ..isRegistered = profile['is_registered'] == true;
      await isar.hydrationProfiles.put(entry);

      // Update DeviceRegistration.capacity with the real roster/room capacity
      // from the server so the settings screen shows the correct student count.
      final capacity = profile['capacity'];
      if (capacity is int && capacity > 0) {
        final regs = await isar.deviceRegistrations.where().findAll();
        for (final reg in regs) {
          reg.capacity = capacity;
          await isar.deviceRegistrations.put(reg);
        }
      }
    });
  }

  static Future<void> _persistSchedule(
    List<dynamic> scheduleList,
    Isar isar,
  ) async {
    Log.i('[Hydration] schedule_list count: ${scheduleList.length}');
    if (scheduleList.isNotEmpty) {
      final dayDistribution = <int, int>{};
      for (final raw in scheduleList) {
        final slot = raw as Map<String, dynamic>;
        final dow = _parseDayOfWeek(slot['day_of_week']);
        dayDistribution[dow] = (dayDistribution[dow] ?? 0) + 1;
      }
      Log.i('[Hydration] day_of_week distribution: $dayDistribution');
      final sample = scheduleList.first as Map<String, dynamic>;
      Log.i('[Hydration] sample slot: day_of_week=${sample['day_of_week']} '
          'raw_type=${sample['day_of_week'].runtimeType} '
          'start=${sample['start_time']} end=${sample['end_time']} '
          'course=${sample['subject_name'] ?? sample['course_name']}');
    }

    await isar.writeTxn(() async {
      await isar.timetableEntrys.clear();

      for (final raw in scheduleList) {
        final slot = raw as Map<String, dynamic>;
        final entry = TimetableEntry()
          ..slotId = slot['slot_id']?.toString() ?? ''
          ..dayOfWeek = _parseDayOfWeek(slot['day_of_week'])
          ..startTime = _truncateTime(slot['start_time']?.toString() ?? '')
          ..endTime = _truncateTime(slot['end_time']?.toString() ?? '')
          ..courseName = slot['subject_name']?.toString() ??
              slot['course_name']?.toString() ??
              'Class'
          ..facultyName = slot['faculty_name']?.toString() ?? ''
          ..sectionId = slot['section_id']?.toString() ?? ''
          ..courseCode = slot['course_code']?.toString() ?? ''
          ..subjectCode = slot['subject_code']?.toString() ?? ''
          ..subjectName = slot['subject_name']?.toString() ??
              slot['course_name']?.toString() ??
              ''
          ..sectionName = slot['section_name']?.toString() ?? ''
          ..facultyEmails = (slot['faculty_emails'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              []
          ..roomNumber = slot['room_number']?.toString() ?? ''
          ..slotType = slot['slot_type']?.toString() ?? 'regular'
          ..classType = slot['class_type']?.toString() ?? 'Lecture'
          ..isBreak = slot['is_break'] == true
          ..periodNumber = slot['period_number'] as int?
          ..periodName = slot['period_name']?.toString()
          ..slotDefinitionId = slot['slot_definition_id'] as int?;
        await isar.timetableEntrys.put(entry);
      }
    });
  }

  static Future<void> _persistRosters(
    Map<String, dynamic> rosters,
    Isar isar,
  ) async {
    await isar.writeTxn(() async {
      await isar.hydrationRosters.clear();

      for (final entry in rosters.entries) {
        final rosterKey = entry.key;
        final students = entry.value as List<dynamic>;

        for (final raw in students) {
          final student = raw as Map<String, dynamic>;
          final rosterEntry = HydrationRoster()
            ..rosterKey = rosterKey
            ..studentId = student['student_id']?.toString() ?? ''
            ..name = student['name']?.toString() ?? ''
            ..rollNumber = student['roll_number']?.toString();
          await isar.hydrationRosters.put(rosterEntry);
        }
      }
    });
  }

  /// Parse day_of_week that may be int (1-7) or string ("monday").
  static int _parseDayOfWeek(dynamic value) {
    if (value is int) {
      return value.clamp(1, 7);
    }
    if (value is String) {
      const dayNames = {
        'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
        'friday': 5, 'saturday': 6, 'sunday': 7,
      };
      return dayNames[value.toLowerCase()] ?? TimeSyncService.timeNow.weekday;
    }
    return TimeSyncService.timeNow.weekday;
  }

  /// Truncate HH:MM:SS to HH:MM for backward compatibility with Isar fields.
  static String _truncateTime(String time) {
    if (time.length >= 5) return time.substring(0, 5);
    return time;
  }
}
