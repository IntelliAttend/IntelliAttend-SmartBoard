import 'dart:async';
import 'dart:io';
import 'package:isar/isar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/config/firestore_schema.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';
import 'session_manager.dart';
import 'timetable_cache.dart';
import 'firestore_rest_client.dart';
import 'time_sync_service.dart';

class TimetableListenerService {
  static final TimetableListenerService _instance =
      TimetableListenerService._internal();
  factory TimetableListenerService() => _instance;
  TimetableListenerService._internal();

  StreamSubscription<QuerySnapshot>? _subscription;
  String? _currentBoardId;
  DateTime? _lastSnapshotTime;
  Timer? _healthTimer;
  void Function()? _restFallback;

  static const Duration _healthInterval = Duration(minutes: 1);
  static const Duration _staleThreshold = Duration(minutes: 5);

  bool get isListening => _subscription != null;
  bool get isNative => _subscription != null;
  bool get isHealthy =>
      _lastSnapshotTime != null &&
      TimeSyncService.timeNow.difference(_lastSnapshotTime!) < _staleThreshold;

  void start(String smartBoardId, {void Function()? restFallback}) {
    if (isListening && _currentBoardId == smartBoardId) return;

    stop();
    _currentBoardId = smartBoardId;
    _restFallback = restFallback;

    if (Platform.isWindows) {
      Log.w(
          '[TimetableListener] Native Firestore snapshots disabled on Windows; using REST sync only.');
      _restFallback?.call();
      return;
    }

    try {
      _subscription = FirebaseFirestore.instance
          .collection(FirestoreSchema.timetableSlots)
          .where(FirestoreSchema.fieldSmartBoardId, isEqualTo: smartBoardId)
          .snapshots(includeMetadataChanges: false)
          .listen(
            _onTimetableChanged,
            onError: _onSnapshotError,
            onDone: _onSnapshotDone,
            cancelOnError: false,
          );
      Log.i('[TimetableListener] Listening for changes (board: $smartBoardId)');
    } catch (e) {
      Log.w('[TimetableListener] Native snapshots unavailable: $e');
      Log.w('[TimetableListener] Use forceSync() for manual one-time sync.');
    }

    _startHealthMonitor();
  }

  /// Manually sync timetable from Firestore via REST (one-shot).
  /// Safe to call at any time — no automatic polling.
  Future<void> forceSync() async {
    final boardId = _currentBoardId;
    if (boardId == null) return;

    try {
      final docs = await FirestoreRestClient.runQuery(
        collection: FirestoreSchema.timetableSlots,
        where: {FirestoreSchema.fieldSmartBoardId: boardId},
      );

      _lastSnapshotTime = TimeSyncService.timeNow;

      if (docs.isEmpty) {
        Log.w('[TimetableListener] forceSync returned 0 docs — clearing cache');
        await _clearAllEntries();
        TimetableCache().updateAll([]);
        return;
      }

      final entries = <TimetableEntry>[];
      for (final data in docs) {
        final docId = data[FirestoreSchema.fieldDocId]?.toString() ?? '';
        if (docId.isEmpty) continue;
        entries.add(_docToEntry(docId, data));
      }

      final allEntries = await _reconcileAll(entries);
      TimetableCache().updateAll(allEntries);

      Log.i(
          '[TimetableListener] Updated ${entries.length} entries from force sync');
    } catch (e) {
      Log.e('[TimetableListener] Force sync failed: $e');
    }
  }

  void stop() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _currentBoardId = null;
    _lastSnapshotTime = null;
    _restFallback = null;
  }

  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(_healthInterval, (_) => _checkHealth());
  }

  void _checkHealth() {
    if (!isListening) return;

    if (!isHealthy) {
      if (_lastSnapshotTime == null) {
        Log.w(
            '[TimetableListener] No snapshots received since startup — triggering REST fallback');
      } else {
        final minutesSince =
            TimeSyncService.timeNow.difference(_lastSnapshotTime!).inMinutes;
        Log.w(
            '[TimetableListener] No snapshot in $minutesSince min — triggering REST fallback');
      }
      _restFallback?.call();
    }
  }

  void _onSnapshotDone() {
    Log.w('[TimetableListener] Stream closed unexpectedly.');
    Log.w(
        '[TimetableListener] Call forceSync() to re-sync timetable manually.');
    _lastSnapshotTime = null;
    _healthTimer?.cancel();
  }

  void _onSnapshotError(Object error) {
    Log.e('[TimetableListener] Snapshot error: $error');
    _lastSnapshotTime = null;
    Log.w(
        '[TimetableListener] Native snapshots unavailable — use forceSync() for manual sync.');
  }

  /// Processes a Firestore snapshot using docChanges for granular
  /// add/modify/remove operations on Isar.  Never clears the entire
  /// collection — individual upserts keep existing data intact when the
  /// stream delivers an empty or error state (offline, token expired, etc.).
  void _onTimetableChanged(QuerySnapshot snapshot) async {
    _lastSnapshotTime = TimeSyncService.timeNow;

    try {
      if (snapshot.docChanges.isEmpty && snapshot.docs.isEmpty) {
        Log.w('[TimetableListener] Empty snapshot — preserving existing cache');
        return;
      }

      final isar = SessionManager.isar;

      if (snapshot.docChanges.isNotEmpty) {
        // Process granular changes from the native listener.
        // Read all existing entries once for O(1) slotId lookups.
        // (~40-50 entries for a weekly timetable — negligible overhead.)
        final allExisting = await isar.timetableEntrys.where().findAll();
        final existingBySlotId = {for (final e in allExisting) e.slotId: e};

        await isar.writeTxn(() async {
          for (final change in snapshot.docChanges) {
            final data = change.doc.data() as Map<String, dynamic>?;
            if (data == null) continue;

            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
                final entry = _docToEntry(change.doc.id, data);
                final existing = existingBySlotId[entry.slotId];
                if (existing != null) {
                  existing
                    ..dayOfWeek = entry.dayOfWeek
                    ..startTime = entry.startTime
                    ..endTime = entry.endTime
                    ..courseName = entry.courseName
                    ..facultyName = entry.facultyName
                    ..sectionId = entry.sectionId;
                  await isar.timetableEntrys.put(existing);
                } else {
                  await isar.timetableEntrys.put(entry);
                }
                break;

              case DocumentChangeType.removed:
                final existing = existingBySlotId[change.doc.id];
                if (existing != null) {
                  await isar.timetableEntrys.delete(existing.id);
                }
                break;
            }
          }
        });
      } else {
        // No docChanges (unusual but defensive) — fall back to bulk upsert.
        final entries = <TimetableEntry>[];
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) continue;
          entries.add(_docToEntry(doc.id, data));
        }
        if (entries.isEmpty) return;

        final allExisting = await isar.timetableEntrys.where().findAll();
        final existingBySlotId = {for (final e in allExisting) e.slotId: e};

        await isar.writeTxn(() async {
          for (final entry in entries) {
            final existing = existingBySlotId[entry.slotId];
            if (existing != null) {
              existing
                ..dayOfWeek = entry.dayOfWeek
                ..startTime = entry.startTime
                ..endTime = entry.endTime
                ..courseName = entry.courseName
                ..facultyName = entry.facultyName
                ..sectionId = entry.sectionId;
              await isar.timetableEntrys.put(existing);
            } else {
              await isar.timetableEntrys.put(entry);
            }
          }
        });
      }

      // Re-read the full timeline from Isar to refresh the in-memory cache.
      final allEntries = await isar.timetableEntrys
          .where()
          .sortByDayOfWeek()
          .thenByStartTime()
          .findAll();
      TimetableCache().updateAll(allEntries);

      Log.i(
          '[TimetableListener] Incremental update applied (${snapshot.docChanges.length} changes)');
    } catch (e) {
      Log.e('[TimetableListener] Failed to process update: $e');
    }
  }

  /// Upserts [incoming] entries into Isar by slotId, then deletes any
  /// entries that are no longer in the synced set.  Never clears the
  /// collection — empty results are already rejected by the caller.
  Future<void> _clearAllEntries() async {
    final isar = SessionManager.isar;
    await isar.writeTxn(() async {
      await isar.timetableEntrys.clear();
    });
  }

  Future<List<TimetableEntry>> _reconcileAll(
      List<TimetableEntry> incoming) async {
    final isar = SessionManager.isar;
    final existingAll = await isar.timetableEntrys.where().findAll();
    final existingBySlotId = {for (final e in existingAll) e.slotId: e};
    final incomingSlotIds = incoming.map((e) => e.slotId).toSet();

    await isar.writeTxn(() async {
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
          await isar.timetableEntrys.put(existing);
        } else {
          await isar.timetableEntrys.put(entry);
        }
      }

      for (final existing in existingAll) {
        if (existing.slotId.isEmpty) continue;
        if (incomingSlotIds.contains(existing.slotId)) continue;
        await isar.timetableEntrys.delete(existing.id);
      }

      // Dedup: if a concurrent sync created two entries with the same slotId,
      // keep only the one with the lowest auto-increment id.
      final after = await isar.timetableEntrys.where().findAll();
      final seen = <String, int>{};
      for (final e in after) {
        final first = seen[e.slotId];
        if (first != null) {
          await isar.timetableEntrys.delete(e.id);
        } else {
          seen[e.slotId] = e.id;
        }
      }
    });

    return await isar.timetableEntrys
        .where()
        .sortByDayOfWeek()
        .thenByStartTime()
        .findAll();
  }

  TimetableEntry _docToEntry(String docId, Map<String, dynamic> data) {
    final facultyEmail = data[FirestoreSchema.fieldFacultyId]?.toString() ??
        (data[FirestoreSchema.fieldFacultyEmails] as List?)
            ?.firstOrNull
            ?.toString() ??
        '';

    return TimetableEntry()
      ..slotId = docId
      ..dayOfWeek =
          _dayNumber(data[FirestoreSchema.fieldDayOfWeek]?.toString() ?? '')
      ..startTime = data[FirestoreSchema.fieldStartTime]?.toString() ?? ''
      ..endTime = data[FirestoreSchema.fieldEndTime]?.toString() ?? ''
      ..courseName =
          data[FirestoreSchema.fieldSubjectName]?.toString() ?? 'Class'
      ..facultyName = facultyEmail
      ..sectionId = data[FirestoreSchema.fieldSectionId]?.toString() ?? 'N/A';
  }

  int _dayNumber(String dayName) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final idx =
        days.indexWhere((d) => d.toLowerCase() == dayName.toLowerCase());
    return idx != -1 ? idx + 1 : TimeSyncService.timeNow.weekday;
  }
}
