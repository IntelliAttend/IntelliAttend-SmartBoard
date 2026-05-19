import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:isar/isar.dart';
import 'session_manager.dart';
import 'api_service.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';

/// SyncManager — flushes queued attendance scans when connectivity returns.
/// Timetable synchronization is now handled solely by DeviceRepository via
/// one-shot REST sync (called on boot and on manual refresh), eliminating the
/// redundant Firestore snapshot listener that previously wrote to the same
/// Isar collection.
class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  StreamSubscription? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;
  late Isar _isar;

  /// Initializes the SyncManager to watch for connectivity changes
  /// and flush queued scans.
  void init(String smartBoardId) {
    _isar = SessionManager.isar;
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        _attemptSync();
      }
    });


    _syncTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _attemptSync());

    _attemptSync();
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

          Log.i(
              '✅ [SyncManager] Synced ${scans.length} scans for Session: $sessionId');
        } catch (e) {
          Log.w('⚠️ [SyncManager] Failed to sync session $sessionId: $e');
        }
      }
    } catch (e) {
      Log.e('❌ [SyncManager] Global sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
  }
}
