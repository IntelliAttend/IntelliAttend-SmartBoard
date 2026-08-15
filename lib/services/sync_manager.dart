import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:isar/isar.dart';
import 'session_manager.dart';
import 'api_service.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';

/// SyncManager — flushes queued attendance data when connectivity returns.
/// Handles both legacy QueuedScans (QR vault) and PendingAttendance (offline submit).
class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  StreamSubscription? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;
  late Isar _isar;

  /// Callback fired when pending attendance is successfully synced.
  /// Used by UI to show sync status.
  void Function(String sessionId)? onAttendanceSynced;

  /// Initializes the SyncManager to watch for connectivity changes
  /// and flush queued data.
  void init(String smartBoardId) {
    _isar = SessionManager.isar;
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        // Small delay to ensure connection is stable
        Future.delayed(const Duration(seconds: 2), () => _attemptSync());
      }
    });

    _syncTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _attemptSync());

    // Initial sync attempt
    _attemptSync();
  }

  /// Attempts to flush any queued attendance data to the server.
  Future<void> _attemptSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // First: flush pending attendance submissions (priority)
      await _flushPendingAttendance();

      // Second: flush legacy queued scans
      await _flushQueuedScans();
    } catch (e) {
      Log.e('[SyncManager] Global sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Flushes pending attendance submissions that were queued while offline.
  Future<void> _flushPendingAttendance() async {
    final pendingCount = await _isar.pendingAttendances.count();
    if (pendingCount == 0) return;

    Log.i('[SyncManager] Found $pendingCount pending attendance submissions. Syncing...');

    final allPending = await _isar.pendingAttendances.where().findAll();

    for (final pending in allPending) {
      try {
        final presentIds = (jsonDecode(pending.presentIdsJson) as List)
            .map((e) => e.toString())
            .toList();
        final absentIds = (jsonDecode(pending.absentIdsJson) as List)
            .map((e) => e.toString())
            .toList();

        await ApiService.submitAttendance(
          sessionId: pending.sessionId,
          presentEmails: presentIds,
          absentEmails: absentIds,
        );

        // Delete from queue after successful sync
        await _isar.writeTxn(() async {
          await _isar.pendingAttendances.delete(pending.id);
        });

        Log.i('[SyncManager] Synced attendance for session ${pending.sessionId}');
        onAttendanceSynced?.call(pending.sessionId);
      } catch (e) {
        // Update retry count and error
        await _isar.writeTxn(() async {
          pending.retryCount++;
          pending.lastError = e.toString();
          await _isar.pendingAttendances.put(pending);
        });
        Log.w('[SyncManager] Failed to sync attendance for ${pending.sessionId}: $e');
      }
    }
  }

  /// Flushes legacy queued QR scans.
  Future<void> _flushQueuedScans() async {
    final pendingCount = await _isar.queuedScans.count();
    if (pendingCount == 0) return;

    Log.i('[SyncManager] Found $pendingCount queued scans. Flushing...');

    try {
      final allScans = await _isar.queuedScans.where().findAll();

      final Map<String, List<QueuedScan>> groupedScans = {};
      for (var scan in allScans) {
        groupedScans.putIfAbsent(scan.sessionId, () => []).add(scan);
      }

      for (var entry in groupedScans.entries) {
        final sessionId = entry.key;
        final scans = entry.value;

        try {
          final payload = scans
              .map((s) => {
                    'student_id': s.studentId,
                    'qr_payload': s.scannedTotpHash,
                    'timestamp': s.scanTimestamp.millisecondsSinceEpoch,
                  })
              .toList();

          await ApiService.syncVault(
            sessionId: sessionId,
            queuedScans: payload,
          );

          final idsToDelete = scans.map((s) => s.id).toList();
          await _isar.writeTxn(() async {
            await _isar.queuedScans.deleteAll(idsToDelete);
          });

          Log.i('[SyncManager] Synced ${scans.length} scans for session $sessionId');
        } catch (e) {
          Log.w('[SyncManager] Failed to sync session $sessionId: $e');
        }
      }
    } catch (e) {
      Log.e('[SyncManager] Global scan sync error: $e');
    }
  }

  /// Returns count of pending items waiting to sync.
  Future<int> getPendingCount() async {
    final attendance = await _isar.pendingAttendances.count();
    final scans = await _isar.queuedScans.count();
    return attendance + scans;
  }

  /// Force sync attempt (called manually or from UI).
  Future<void> forceSyncNow() async {
    await _attemptSync();
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
  }
}
