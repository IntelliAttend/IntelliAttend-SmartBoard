import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:isar/isar.dart';
import 'session_manager.dart';
import 'api_service.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  StreamSubscription? _timetableSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;
  late Isar _isar;

  /// Initializes the SyncManager to watch for connectivity changes
  /// and mirrors the Firestore timetable to the local vault.
  void init(String smartBoardId) {
    _isar = SessionManager.isar;

    // 1. Connectivity Listener (Outgoing Sync)
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        _attemptSync();
      }
    });

    // 2. Real-Time Timetable Mirror (Incoming Sync)
    _setupTimetableMirror(smartBoardId);

    // Periodic retry timer for outgoing scans
    _syncTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _attemptSync());

    _attemptSync();
  }

  void _setupTimetableMirror(String smartBoardId) {
    _timetableSubscription?.cancel();

    Log.i(
        '📡 [SyncManager] Establishing Real-Time Timetable Mirror for $smartBoardId...');

    _timetableSubscription = FirebaseFirestore.instance
        .collection('timetable_slots')
        .where('classroom_id', isEqualTo: smartBoardId)
        .snapshots()
        .listen((snapshot) async {
      Log.i(
          '📅 [SyncManager] Timetable update received from Firestore. Mirroring to Isar...');

      final entries = snapshot.docs.map((doc) {
        final data = doc.data();
        return TimetableEntry()
          ..slotId = doc.id
          ..dayOfWeek = _getDayNumber(data['day_of_week'] ?? '')
          ..startTime = data['start_time'] ?? ''
          ..endTime = data['end_time'] ?? ''
          ..courseName = data['subject_name'] ?? 'Class'
          ..facultyName = data['faculty_name'] ?? 'Professor'
          ..sectionId = data['section_id']?.toString() ?? 'N/A';
      }).toList();

      await _isar.writeTxn(() async {
        // Clear existing timetable to ensure perfect mirror
        await _isar.timetableEntrys.clear();
        await _isar.timetableEntrys.putAll(entries);
      });

      Log.i(
          '✅ [SyncManager] Local timetable vault synchronized (${entries.length} slots).');
    }, onError: (e) {
      Log.i('❌ [SyncManager] Timetable Mirror Error: $e');
    });
  }

  int _getDayNumber(String dayName) {
    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final idx =
        days.indexWhere((d) => d.toLowerCase() == dayName.toLowerCase());
    return idx != -1 ? idx + 1 : DateTime.now().weekday;
  }

  /// Attempts to flush any queued attendance data to the server.
  Future<void> _attemptSync() async {
    if (_isSyncing) return;

    final pendingCount = await _isar.queuedScans.count();
    if (pendingCount == 0) return;

    _isSyncing = true;
    Log.i(
        '🔄 [SyncManager] Connection detected. Flushing $pendingCount queued scans...');

    try {
      // 1. Fetch all queued scans
      final allScans = await _isar.queuedScans.where().findAll();

      // 2. Group by Session ID for batch processing
      final Map<String, List<QueuedScan>> groupedScans = {};
      for (var scan in allScans) {
        groupedScans.putIfAbsent(scan.sessionId, () => []).add(scan);
      }

      // 3. Process each session batch
      for (var entry in groupedScans.entries) {
        final sessionId = entry.key;
        final scans = entry.value;

        try {
          final payload = scans
              .map((s) => {
                    'student_id': s.studentId,
                    'qr_payload':
                        s.scannedTotpHash, // In v5.3 this is the Base64 payload
                    'timestamp': s.scanTimestamp.millisecondsSinceEpoch,
                  })
              .toList();

          await ApiService.syncVault(
            sessionId: sessionId,
            queuedScans: payload,
          );

          // 4. Delete successfully synced scans
          final idsToDelete = scans.map((s) => s.id).toList();
          await _isar.writeTxn(() async {
            await _isar.queuedScans.deleteAll(idsToDelete);
          });

          Log.i(
              '✅ [SyncManager] Synced ${scans.length} scans for Session: $sessionId');
        } catch (e) {
          Log.w('⚠️ [SyncManager] Failed to sync session $sessionId: $e');
        }
      }
    } catch (e) {
      Log.i('❌ [SyncManager] Global sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
  }
}
