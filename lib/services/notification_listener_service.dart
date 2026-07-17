import 'dart:async';
import '../core/config/api_schema.dart';
import '../core/utils/logger.dart';
import '../models/board_notification.dart';
import '../models/notification_event.dart';
import 'api_service.dart';
import 'session_manager.dart';
import 'time_sync_service.dart';

class NotificationListenerService {
  static final NotificationListenerService _instance =
      NotificationListenerService._internal();
  factory NotificationListenerService() => _instance;
  NotificationListenerService._internal();

  final StreamController<List<BoardNotification>> _notificationsController =
      StreamController<List<BoardNotification>>.broadcast();

  final StreamController<BoardNotification> _incomingController =
      StreamController<BoardNotification>.broadcast();

  final StreamController<BoardNotification> _allClearController =
      StreamController<BoardNotification>.broadcast();

  Stream<List<BoardNotification>> get notificationsStream =>
      _notificationsController.stream;

  /// Fires for each *new* notification added to the cache (not the full list).
  /// Use this to react to individual incoming notifications.
  Stream<BoardNotification> get onNotificationArrived =>
      _incomingController.stream;

  /// Fires when an all-clear notification is received.
  /// The listener should restore normal UI.
  Stream<BoardNotification> get onAllClear => _allClearController.stream;

  List<BoardNotification> _cachedNotifications = [];
  String? _currentBoardId;

  /// When true, new notifications are emitted immediately. When false they are
  /// queued and released when [drainQueue] is called (e.g. returning to idle).
  bool _isIdle = true;

  /// Prevents stored notifications from triggering overlays during startup.
  bool _isStartingUp = true;
  bool get isStartingUp => _isStartingUp;
  final List<BoardNotification> _notificationQueue = [];

  // ── Contract v1 dedup state ──────────────────────────────────────

  /// Tracks processed event IDs to skip duplicates on reconnect.
  final Set<String> _processedEventIds = {};

  /// Tracks dismissed notification IDs so they are not re-shown on reconnect.
  final Set<String> _dismissedNotificationIds = {};

  // ── Priority filter helpers ────────────────────────────────────

  List<BoardNotification> get emergencyNotifications =>
      _cachedNotifications
          .where((n) => n.priority == NotificationPriority.emergency)
          .toList();

  List<BoardNotification> get highPriorityNotifications =>
      _cachedNotifications
          .where((n) => n.priority == NotificationPriority.high)
          .toList();

  List<BoardNotification> get bellNotifications =>
      _cachedNotifications.where((n) =>
          n.priority == NotificationPriority.normal ||
          n.priority == NotificationPriority.low).toList();

  // ── Cache access ────────────────────────────────────────────────

  List<BoardNotification> get cachedNotifications =>
      List.unmodifiable(_cachedNotifications);

  // ── Public BoardNotification factory helpers ─────────────────────

  // ── Priority parsing helpers ────────────────────────────────────

  static NotificationPriority _parsePriority(dynamic value) {
    if (value is int) {
      return NotificationPriority.values[value.clamp(0, 3)];
    }
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'emergency': return NotificationPriority.emergency;
        case 'high': return NotificationPriority.high;
        case 'normal': return NotificationPriority.normal;
        case 'low': return NotificationPriority.low;
      }
    }
    return NotificationPriority.low;
  }

  static BoardNotification fromMap(String id, Map<String, dynamic> data) {
    int? parseSize(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return BoardNotification(
      id: id,
      title: data[ApiSchema.fieldTitle]?.toString() ?? 'Notification',
      body: data[ApiSchema.fieldBody]?.toString() ?? '',
      type: data[ApiSchema.fieldType]?.toString() ?? 'info',
      timestamp: data[ApiSchema.fieldTimestamp] is DateTime
          ? (data[ApiSchema.fieldTimestamp] as DateTime)
          : data[ApiSchema.fieldCreatedAt] is DateTime
              ? (data[ApiSchema.fieldCreatedAt] as DateTime)
              : TimeSyncService.timeNow,
      read: data[ApiSchema.fieldRead] == true,
      attachmentUrl: data[ApiSchema.fieldAttachmentUrl]?.toString(),
      attachmentName: data[ApiSchema.fieldAttachmentName]?.toString(),
      attachmentType: data[ApiSchema.fieldAttachmentType]?.toString(),
      attachmentSize: parseSize(data[ApiSchema.fieldAttachmentSize]),
      priority: _parsePriority(data[ApiSchema.fieldPriority]),
      notificationId: data[ApiSchema.fieldNotificationId]?.toString(),
      requiresAcknowledgement: data[ApiSchema.fieldRequiresAcknowledgement] == true,
      durationSeconds: parseSize(data[ApiSchema.fieldDurationSeconds]),
      displayMode: data[ApiSchema.fieldDisplayMode]?.toString(),
      precautionarySteps: (data[ApiSchema.fieldPrecautionarySteps] as List<dynamic>?)
          ?.map((e) => e.toString()).toList(),
      location: data[ApiSchema.fieldLocation]?.toString(),
      safeExit: data[ApiSchema.fieldSafeExit]?.toString(),
      assemblyPoint: data[ApiSchema.fieldAssemblyPoint]?.toString(),
    );
  }

  // ── Local vault persistence ────────────────────────────────────

  /// Loads notifications from the local Isar vault on startup.
  /// Merges with any already-cached items so WebSocket arrivals that
  /// beat this call are not lost. Returns the list sorted by timestamp
  /// descending.
  Future<List<BoardNotification>> loadFromLocalVault() async {
    try {
      final stored = await SessionManager.getAllStoredNotifications();
      // Filter out stale emergency/high-priority notifications from vault.
      // These are time-sensitive alerts only meaningful while live via WebSocket.
      // Loading them from vault causes false overlay activations on boot.
      final staleIds = stored
          .where((n) =>
              n.priority == NotificationPriority.emergency ||
              n.priority == NotificationPriority.high)
          .map((n) => n.notificationId ?? n.id)
          .toList();
      for (final id in staleIds) {
        _dismissedNotificationIds.add(id);
        await SessionManager.deleteStoredNotification(id);
      }
      final eligible = stored
          .where((n) =>
              n.priority != NotificationPriority.emergency &&
              n.priority != NotificationPriority.high)
          .toList();
      // Merge: keep any in-memory items not yet in Isar
      final existingIds = _cachedNotifications.map((n) => n.id).toSet();
      final newFromVault = eligible.where((n) => !existingIds.contains(n.id)).toList();
      _cachedNotifications = [...newFromVault, ..._cachedNotifications];
      _notificationsController.add(_cachedNotifications);
      Log.i('[NotificationListener] Loaded ${eligible.length} notifications from local vault (${stored.length - eligible.length} stale high-priority discarded)');
      return stored;
    } catch (e) {
      Log.w('[NotificationListener] Local vault load failed: $e');
      return [];
    }
  }

  /// Persists a single notification to the local vault.
  Future<void> _persistNotification(BoardNotification notification) async {
    try {
      await SessionManager.saveNotification(notification);
    } catch (e) {
      Log.w('[NotificationListener] Persist failed: $e');
    }
  }

  /// Persists multiple notifications to the local vault.
  Future<void> _persistNotifications(List<BoardNotification> notifications) async {
    try {
      await SessionManager.saveNotifications(notifications);
    } catch (e) {
      Log.w('[NotificationListener] Batch persist failed: $e');
    }
  }

  static BoardNotification _fromPayload(NotificationPayload payload, {DateTime? timestamp}) {
    return BoardNotification.fromNotificationPayload(payload, timestamp: timestamp);
  }

  bool get isListening => _currentBoardId != null;

  Future<void> start(String boardId) async {
    if (isListening && _currentBoardId == boardId) return;
    stop();
    _currentBoardId = boardId;
    _isStartingUp = true;

    // Restore any notifications persisted from previous sessions
    await loadFromLocalVault();

    // Allow real-time notifications to trigger overlays after startup settles.
    Future.delayed(const Duration(seconds: 5), () {
      _isStartingUp = false;
    });

    Log.i('[NotificationListener] Started for board: $boardId');
  }

  /// Manually fetch notifications from the backend (one-shot REST).
  /// Called on boot and on pull-to-refresh.  Merges server notifications into
  /// the local cache, respecting already-dismissed IDs.
  Future<void> forceSync() async {
    final boardId = _currentBoardId;
    if (boardId == null) return;

    try {
      final docs = await ApiService.getNotifications();
      final notifications = <BoardNotification>[];

      for (int i = 0; i < docs.length; i++) {
        final data = docs[i];
        final notificationId =
            data[ApiSchema.fieldNotificationId]?.toString();
        // Skip dismissed notifications
        if (notificationId != null &&
            _dismissedNotificationIds.contains(notificationId)) {
          continue;
        }
        final id = notificationId ?? 'rest-${DateTime.now().millisecondsSinceEpoch}-$i';
        notifications.add(fromMap(id, data));
      }

      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _cachedNotifications = notifications;
      _notificationsController.add(_cachedNotifications);
      _persistNotifications(notifications);

      Log.i('[NotificationListener] Loaded ${notifications.length} notifications from REST');
    } catch (e) {
      Log.w('[NotificationListener] Force sync failed: $e');
    }
  }

  /// Removes a notification from the cache by [id] and emits the updated list.
  /// The notification remains in the local vault (marked read) so the full
  /// history is always preserved.
  void removeNotification(String id) {
    final removed = _cachedNotifications.where((n) => n.id == id).toList();
    _cachedNotifications.removeWhere((n) => n.id == id);
    _notificationsController.add(_cachedNotifications);
    for (final n in removed) {
      final nid = n.notificationId ?? n.id;
      SessionManager.markStoredNotificationRead(nid);
    }
  }

  /// Permanently deletes a notification from both the cache and the local
  /// vault.  Unlike [removeNotification] (which marks read), this is a true
  /// deletion — useful for the "delete" action in the notifications list.
  void deleteNotificationPermanently(String id) {
    final removed = _cachedNotifications.where((n) => n.id == id).toList();
    _cachedNotifications.removeWhere((n) => n.id == id);
    _notificationsController.add(_cachedNotifications);
    for (final n in removed) {
      final nid = n.notificationId ?? n.id;
      _dismissedNotificationIds.add(nid);
      SessionManager.deleteStoredNotification(nid);
    }
  }

  // ── Contract v1: WebSocket notification handling ──────────────────

  /// Main entry point for notification events from WebSocket.
  /// Applies dedup, routes by display_mode, and updates the cache.
  void handleNotificationEvent(NotificationEvent event) {
    // Dedup by event_id
    if (_processedEventIds.contains(event.eventId)) {
      Log.d('[NotificationListener] Skipping duplicate event_id: ${event.eventId}');
      return;
    }
    _processedEventIds.add(event.eventId);

    final payload = event.payload;

    // Dedup by notification_id (previously dismissed)
    if (_dismissedNotificationIds.contains(payload.notificationId)) {
      Log.d('[NotificationListener] Skipping dismissed notification_id: ${payload.notificationId}');
      // Re-acknowledge on reconnect (contract §4.3)
      _sendAcknowledge(payload.notificationId);
      return;
    }

    // Handle all-clear: emit onAllClear stream and archive in history
    if (payload.isAllClear) {
      final notification = _fromPayload(payload, timestamp: event.timestamp);
      _allClearController.add(notification);
      _removeDisplayedNotification(NotificationPriority.emergency);
      _cachedNotifications.insert(0, notification);
      _notificationsController.add(_cachedNotifications);
      _persistNotification(notification);
      Log.i('[NotificationListener] All-clear received. Restoring normal UI.');
      return;
    }

    final notification = _fromPayload(payload, timestamp: event.timestamp);

    switch (payload.displayMode) {
      case NotificationPayload.displayModeFullScreen:
      case NotificationPayload.displayModeOverlay:
        // These go to the overlay system (emergency/high priority)
        addNotification(notification);
        _persistNotification(notification);
        break;

      case NotificationPayload.displayModeReminder:
        // Reminder goes to popdown queue with normal priority
        addNotification(notification);
        _persistNotification(notification);
        break;

      case NotificationPayload.displayModeDefault:
      default:
        // Default goes to inbox AND popdown queue (low priority, no overlay)
        _cachedNotifications.insert(0, notification);
        _notificationsController.add(_cachedNotifications);
        _persistNotification(notification);
        // Emit on incoming stream so idle screen can show popdown
        if (_isIdle) {
          _incomingController.add(notification);
        } else {
          _notificationQueue.add(notification);
        }
        Log.d('[NotificationListener] Added P3 notification: ${notification.title}');
        break;
    }
  }

  /// Dismiss a notification that was displayed via WebSocket.
  /// Sends acknowledge to server and adds to dismissed set.
  /// The notification stays in the local vault (already marked read by
  /// [removeNotification]) for the full history.
  Future<void> dismissNotification(String notificationId) async {
    _dismissedNotificationIds.add(notificationId);
    removeNotification(notificationId);
    _removeDisplayedNotificationByNotificationId(notificationId);
    await _sendAcknowledge(notificationId);
  }

  Future<void> _sendAcknowledge(String notificationId) async {
    try {
      await ApiService.acknowledgeNotification(notificationId);
      Log.i('[NotificationListener] Acknowledged notification: $notificationId');
    } catch (e) {
      Log.w('[NotificationListener] Acknowledge failed for $notificationId: $e');
    }
  }

  void _removeDisplayedNotification(NotificationPriority priority) {
    _cachedNotifications.removeWhere((n) => n.priority == priority);
    _notificationsController.add(_cachedNotifications);
  }

  void _removeDisplayedNotificationByNotificationId(String notificationId) {
    _cachedNotifications.removeWhere((n) => n.notificationId == notificationId);
    _notificationsController.add(_cachedNotifications);
  }

  /// On reconnect, re-acknowledge any previously dismissed notifications
  /// (contract §4.3).
  void reAcknowledgeDismissed() {
    for (final id in _dismissedNotificationIds) {
      _sendAcknowledge(id);
    }
  }

  /// Inserts a notification into the cache. When [_isIdle] is true the
  /// notification fires immediately on [onNotificationArrived]; otherwise it is
  /// queued and released by [drainQueue].
  void addNotification(BoardNotification notification) {
    _cachedNotifications.insert(0, notification);
    _notificationsController.add(_cachedNotifications);

    if (_isStartingUp) {
      return;
    }

    if (_isIdle) {
      _incomingController.add(notification);
    } else {
      _notificationQueue.add(notification);
      Log.d('[NotificationListener] Queued notification ${notification.id} (not idle)');
    }
  }

  /// Sets the idle state. Transitioning to idle drains any queued notifications.
  void markIdle(bool value) {
    _isIdle = value;
    if (value && _notificationQueue.isNotEmpty) {
      drainQueue();
    }
  }

  /// Emits all queued notifications on [onNotificationArrived] and clears the
  /// queue. Returns the list so callers can show a popdown for each.
  List<BoardNotification> drainQueue() {
    if (_notificationQueue.isEmpty) return [];
    final drained = List<BoardNotification>.from(_notificationQueue);
    _notificationQueue.clear();
    for (final n in drained) {
      _incomingController.add(n);
    }
    Log.d('[NotificationListener] Drained ${drained.length} queued notifications');
    return drained;
  }

  void stop() {
    _currentBoardId = null;
  }

  void dispose() {
    stop();
    _incomingController.close();
    _notificationsController.close();
    _allClearController.close();
  }
}
