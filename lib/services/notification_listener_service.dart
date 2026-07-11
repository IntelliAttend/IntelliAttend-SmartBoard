import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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

  /// Copies a bundled asset file to the local documents directory.
  Future<String> _copyAsset(String assetName) async {
    final dir = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${dir.path}/documents');
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    final fileName = assetName.split('/').last;
    final destPath = '${docsDir.path}/$fileName';
    final destFile = File(destPath);
    if (!await destFile.exists()) {
      final data = await rootBundle.load('assets/$fileName');
      await destFile.writeAsBytes(data.buffer.asUint8List());
    }
    return destPath;
  }

  /// Injects sample notifications with locally bundled documents into the
  /// local cache for testing the document viewer. Runs only when docs enabled.
  Future<void> injectSampleData() async {
    final pdf1 = await _copyAsset('sample.pdf');
    final pdf2 = await _copyAsset('orimi_sample.pdf');
    final txt = await _copyAsset('sample.txt');
    final md = await _copyAsset('sample_notes.md');
    final html = await _copyAsset('sample_report.html');
    final png = await _copyAsset('chart_sample.png');
    final docx = await _copyAsset('sample_document.docx');
    final xlsx = await _copyAsset('sample_spreadsheet.xlsx');
    final pptx = await _copyAsset('sample_presentation.pptx');
    final ppt = await _copyAsset('sample_presentation.ppt');

    final now = TimeSyncService.timeNow;
    final samples = <BoardNotification>[
      BoardNotification(id: 'sample-pdf-1',
        title: 'Lecture Notes — Week 10',
        body: 'Dr. Sharma shared PDF notes for this week\'s lecture on Neural Networks.',
        type: 'message', timestamp: now,
        attachmentUrl: pdf1, attachmentName: 'CSE_AIML_Week10_Notes.pdf',
        attachmentType: 'application/pdf', attachmentSize: 13264,
      ),
      BoardNotification(id: 'sample-pdf-2',
        title: 'Complete Reference — Machine Learning',
        body: 'Full semester reference handbook covering all ML algorithms.',
        type: 'message', timestamp: now.subtract(const Duration(minutes: 2)),
        attachmentUrl: pdf2, attachmentName: 'Complete_ML_Reference.pdf',
        attachmentType: 'application/pdf', attachmentSize: 20597,
      ),
      BoardNotification(id: 'sample-docx',
        title: 'Assignment Guidelines — Final Project',
        body: 'Guidelines for the end-semester project.',
        type: 'message', timestamp: now.subtract(const Duration(minutes: 5)),
        attachmentUrl: docx, attachmentName: 'Final_Project_Guidelines.docx',
        attachmentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        attachmentSize: 1660,
      ),
      BoardNotification(id: 'sample-pptx',
        title: 'Faculty Presentation — Deep Learning',
        body: 'Slides from today\'s guest lecture.',
        type: 'message', timestamp: now.subtract(const Duration(minutes: 8)),
        attachmentUrl: pptx, attachmentName: 'Deep_Learning_Session.pptx',
        attachmentType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        attachmentSize: 2881,
      ),
      BoardNotification(id: 'sample-xlsx',
        title: 'Grade Sheet — Midterm Results',
        body: 'Consolidated midterm scores for CSE-AIML Section A.',
        type: 'attendance', timestamp: now.subtract(const Duration(minutes: 12)),
        attachmentUrl: xlsx, attachmentName: 'Midterm_Grades_SecA.xlsx',
        attachmentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        attachmentSize: 2165,
      ),
      BoardNotification(id: 'sample-txt',
        title: 'Lab Manual — Python Programming',
        body: 'Step-by-step lab instructions for Experiment 1.',
        type: 'message', timestamp: now.subtract(const Duration(minutes: 18)),
        attachmentUrl: txt, attachmentName: 'Lab1_Python_Intro.txt',
        attachmentType: 'text/plain', attachmentSize: 1782,
      ),
      BoardNotification(id: 'sample-md',
        title: 'Course Syllabus — Machine Learning',
        body: 'Detailed syllabus for CSE-AIML 305.',
        type: 'message', timestamp: now.subtract(const Duration(minutes: 25)),
        attachmentUrl: md, attachmentName: 'ML_Syllabus.md',
        attachmentType: 'text/markdown', attachmentSize: 1833,
      ),
      BoardNotification(id: 'sample-html',
        title: 'Academic Calendar 2026',
        body: 'Department-wide academic schedule.',
        type: 'system', timestamp: now.subtract(const Duration(minutes: 35)),
        attachmentUrl: html, attachmentName: 'Academic_Calendar_2026.html',
        attachmentType: 'text/html', attachmentSize: 3137,
      ),
      BoardNotification(id: 'sample-png',
        title: 'Attendance Chart — June 2026',
        body: 'Monthly attendance visualization.',
        type: 'attendance', timestamp: now.subtract(const Duration(minutes: 50)),
        attachmentUrl: png, attachmentName: 'Attendance_Chart_June2026.png',
        attachmentType: 'image/png', attachmentSize: 457,
      ),
      BoardNotification(id: 'sample-ppt',
        title: 'Orientation Slides — Industry Visit',
        body: 'Pre-visit orientation presentation.',
        type: 'message', timestamp: now.subtract(const Duration(hours: 1)),
        attachmentUrl: ppt, attachmentName: 'Industry_Visit_Orientation.ppt',
        attachmentType: 'application/vnd.ms-powerpoint', attachmentSize: 8,
      ),
    ];
    // Append samples to existing cache so previously persisted notifications
    // are not lost when docs mode is enabled.
    _cachedNotifications = [...samples, ..._cachedNotifications];
    _notificationsController.add(_cachedNotifications);
    Log.i('[NotificationListener] Injected ${samples.length} sample notifications');
  }

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

  // ── Debug injection helpers ──────────────────────────────────────

  void injectEmergencyForDebug() {
    final n = BoardNotification(
      id: 'debug-emergency-${DateTime.now().millisecondsSinceEpoch}',
      title: 'FIRE EMERGENCY',
      body: 'Fire reported in Block B, 2nd Floor. Evacuate immediately.',
      type: 'emergency',
      timestamp: TimeSyncService.timeNow,
      priority: NotificationPriority.emergency,
      location: 'Block B, Room 204',
      safeExit: 'NORTH-EAST',
      assemblyPoint: 'Main Ground Assembly Point',
      precautionarySteps: [
        'Remain Calm — Do not panic or run',
        'Alert Others — Inform nearby students and staff',
        'Exit Immediately — Use nearest fire exit',
        'Do Not Use Elevators — Use stairwell only',
        'Report to Assembly Point — Main ground area',
      ],
    );
    addNotification(n);
    _persistNotification(n);
  }

  void injectPriority1ForDebug() {
    final n = BoardNotification(
      id: 'debug-p1-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Faculty Meeting Reminder',
      body: 'All faculty members are requested to attend the urgent meeting in Conference Room A at 12:00 PM.',
      type: 'alert',
      timestamp: TimeSyncService.timeNow,
      priority: NotificationPriority.high,
    );
    addNotification(n);
    _persistNotification(n);
  }

  void injectP2ForDebug() {
    final n = BoardNotification(
      id: 'debug-reminder-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Library Book Due',
      body: 'Please return "Introduction to Machine Learning" to the library by tomorrow.',
      type: 'reminder',
      timestamp: TimeSyncService.timeNow,
      priority: NotificationPriority.normal,
      notificationId: 'debug-reminder-nid',
      requiresAcknowledgement: false,
      durationSeconds: null,
      displayMode: NotificationPayload.displayModeReminder,
    );
    addNotification(n);
    _persistNotification(n);
  }

  void injectDefaultForDebug() {
    final notification = BoardNotification(
      id: 'debug-default-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Campus Announcement',
      body: 'The cafeteria will be closed for maintenance this weekend.',
      type: 'info',
      timestamp: TimeSyncService.timeNow,
      priority: NotificationPriority.low,
      notificationId: 'debug-default-nid',
      requiresAcknowledgement: false,
      durationSeconds: null,
      displayMode: NotificationPayload.displayModeDefault,
    );
    _cachedNotifications.insert(0, notification);
    _notificationsController.add(_cachedNotifications);
    _persistNotification(notification);
    Log.d('[NotificationListener] Added P3 debug notification to inbox: ${notification.title}');
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
