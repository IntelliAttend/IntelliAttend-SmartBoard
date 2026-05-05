import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:isar/isar.dart';
import 'session_manager.dart';
import 'api_service.dart';
import '../models/isar_schemas.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isSyncing = false;
  late Isar _isar;

  /// Initializes the SyncManager to watch for connectivity changes.
  void init() {
    _isar = SessionManager.isar;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _attemptSync();
      }
    });
    
    // Also try initial sync
    _attemptSync();
  }

  /// Attempts to flush any queued attendance data to the server.
  Future<void> _attemptSync() async {
    if (_isSyncing) return;
    
    final pendingCount = await _isar.queuedScans.count();
    if (pendingCount == 0) return;

    _isSyncing = true;
    print('🔄 [SyncManager] Connection detected. Flushing $pendingCount queued scans...');

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
          final payload = scans.map((s) => {
            'student_id': s.studentId,
            'qr_payload': s.scannedTotpHash, // In v5.3 this is the Base64 payload
            'timestamp': s.scanTimestamp.millisecondsSinceEpoch,
          }).toList();

          await ApiService.syncVault(
            sessionId: sessionId,
            queuedScans: payload,
          );

          // 4. Delete successfully synced scans
          final idsToDelete = scans.map((s) => s.id).toList();
          await _isar.writeTxn(() async {
            await _isar.queuedScans.deleteAll(idsToDelete);
          });
          
          print('✅ [SyncManager] Synced ${scans.length} scans for Session: $sessionId');
        } catch (e) {
          print('⚠️ [SyncManager] Failed to sync session $sessionId: $e');
        }
      }
    } catch (e) {
      print('❌ [SyncManager] Global sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
