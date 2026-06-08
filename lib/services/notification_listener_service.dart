import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/config/firestore_schema.dart';
import '../core/utils/logger.dart';
import 'firestore_rest_client.dart';
import 'time_sync_service.dart';

class BoardNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime timestamp;
  final bool read;

  BoardNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.read = false,
  });

  factory BoardNotification.fromMap(String id, Map<String, dynamic> data) {
    return BoardNotification(
      id: id,
      title: data[FirestoreSchema.fieldTitle]?.toString() ?? 'Notification',
      body: data[FirestoreSchema.fieldBody]?.toString() ?? '',
      type: data[FirestoreSchema.fieldType]?.toString() ?? 'info',
      timestamp: data[FirestoreSchema.fieldTimestamp] is Timestamp
          ? (data[FirestoreSchema.fieldTimestamp] as Timestamp).toDate()
          : data[FirestoreSchema.fieldCreatedAt] is Timestamp
              ? (data[FirestoreSchema.fieldCreatedAt] as Timestamp).toDate()
              : TimeSyncService.timeNow,
      read: data[FirestoreSchema.fieldRead] == true,
    );
  }
}

class NotificationListenerService {
  static final NotificationListenerService _instance =
      NotificationListenerService._internal();
  factory NotificationListenerService() => _instance;
  NotificationListenerService._internal();

  final StreamController<List<BoardNotification>> _notificationsController =
      StreamController<List<BoardNotification>>.broadcast();

  Stream<List<BoardNotification>> get notificationsStream =>
      _notificationsController.stream;

  StreamSubscription<QuerySnapshot>? _subscription;
  List<BoardNotification> _cachedNotifications = [];
  String? _currentBoardId;

  List<BoardNotification> get cachedNotifications =>
      List.unmodifiable(_cachedNotifications);

  bool get isListening => _subscription != null;
  bool get isNative => _subscription != null;

  void start(String boardId) {
    if (isListening && _currentBoardId == boardId) return;
    stop();
    _currentBoardId = boardId;

    try {
      _subscription = FirebaseFirestore.instance
          .collection(FirestoreSchema.notifications)
          .where(FirestoreSchema.fieldSmartBoardId, isEqualTo: boardId)
          .orderBy(FirestoreSchema.fieldCreatedAt, descending: true)
          .snapshots(includeMetadataChanges: false)
          .listen(
            _onNotificationsChanged,
            onError: _onError,
            onDone: _onDone,
            cancelOnError: false,
          );
      Log.i('[NotificationListener] Listening for notifications (board: $boardId)');
    } catch (e) {
      Log.w('[NotificationListener] Native snapshots unavailable: $e');
      Log.w('[NotificationListener] Use forceSync() for manual one-time refresh.');
    }
  }

  /// Manually fetch notifications from Firestore via REST (one-shot).
  /// Safe to call at any time — no automatic polling.
  Future<void> forceSync() async {
    final boardId = _currentBoardId;
    if (boardId == null) return;

    try {
      final docs = await FirestoreRestClient.runQuery(
        collection: FirestoreSchema.notifications,
        where: {FirestoreSchema.fieldSmartBoardId: boardId},
      );

      final notifications = <BoardNotification>[];
      for (final data in docs) {
        final docId = data[FirestoreSchema.fieldDocId]?.toString() ?? '';
        if (docId.isEmpty) continue;
        notifications.add(BoardNotification.fromMap(docId, data));
      }

      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _cachedNotifications = notifications;
      _notificationsController.add(_cachedNotifications);

      Log.i('[NotificationListener] Loaded ${notifications.length} notifications from force sync');
    } catch (e) {
      Log.w('[NotificationListener] Force sync failed: $e');
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _currentBoardId = null;
  }

  void _onDone() {
    Log.w('[NotificationListener] Stream closed unexpectedly.');
    Log.w('[NotificationListener] Call forceSync() to re-fetch notifications.');
  }

  void _onError(Object error) {
    Log.e('[NotificationListener] Stream error: $error');
    Log.w('[NotificationListener] Native snapshots unavailable — use forceSync() for manual refresh.');
  }

  void _onNotificationsChanged(QuerySnapshot snapshot) async {
    try {
      final notifications = <BoardNotification>[];
      final newestFirst = snapshot.docs.reversed;

      for (final doc in newestFirst) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        notifications.add(BoardNotification.fromMap(doc.id, data));
      }

      if (notifications.isEmpty) {
        Log.w('[NotificationListener] Skipping empty snapshot — preserving existing cache');
        return;
      }

      _cachedNotifications = notifications.reversed.toList();
      _notificationsController.add(_cachedNotifications);

      Log.i('[NotificationListener] ${notifications.length} notifications loaded');
    } catch (e) {
      Log.e('[NotificationListener] Failed to process notifications: $e');
    }
  }

  void dispose() {
    stop();
    _notificationsController.close();
  }
}
