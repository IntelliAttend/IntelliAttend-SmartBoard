import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/config/api_schema.dart';
import '../core/utils/logger.dart';
import 'time_sync_service.dart';

enum NotificationPriority {
  emergency, // 0 — full screen takeover, no dismiss
  high,      // 1 — blur overlay, 60s minimum timer
  normal,    // 2 — break auto-pop in bell dropdown
  low,       // 3 — regular tap-to-open in bell dropdown
}

class BoardNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime timestamp;
  final bool read;
  final String? attachmentUrl;
  final String? attachmentName;
  final String? attachmentType;
  final int? attachmentSize;
  final NotificationPriority priority;
  final List<String>? precautionarySteps;
  final String? location;
  final String? safeExit;
  final String? assemblyPoint;

  BoardNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.read = false,
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentType,
    this.attachmentSize,
    this.priority = NotificationPriority.low,
    this.precautionarySteps,
    this.location,
    this.safeExit,
    this.assemblyPoint,
  });

  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;

  String get displayAttachmentName {
    if (attachmentName != null && attachmentName!.isNotEmpty) return attachmentName!;
    if (attachmentUrl != null) {
      final segments = attachmentUrl!.split('/');
      return segments.last;
    }
    return 'document';
  }

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

  factory BoardNotification.fromMap(String id, Map<String, dynamic> data) {
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
      precautionarySteps: (data[ApiSchema.fieldPrecautionarySteps] as List<dynamic>?)
          ?.map((e) => e.toString()).toList(),
      location: data[ApiSchema.fieldLocation]?.toString(),
      safeExit: data[ApiSchema.fieldSafeExit]?.toString(),
      assemblyPoint: data[ApiSchema.fieldAssemblyPoint]?.toString(),
    );
  }
}

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
    _cachedNotifications = [
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
    _notificationsController.add(_cachedNotifications);
    Log.i('[NotificationListener] Injected ${_cachedNotifications.length} sample notifications');
  }

  final StreamController<List<BoardNotification>> _notificationsController =
      StreamController<List<BoardNotification>>.broadcast();

  Stream<List<BoardNotification>> get notificationsStream =>
      _notificationsController.stream;

  List<BoardNotification> _cachedNotifications = [];
  String? _currentBoardId;

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

  bool get isListening => _currentBoardId != null;

  void start(String boardId) {
    if (isListening && _currentBoardId == boardId) return;
    stop();
    _currentBoardId = boardId;

    Log.i('[NotificationListener] Started for board: $boardId');
    // Notifications are fetched on demand via forceSync().
  }

  /// Manually fetch notifications from the backend (one-shot REST).
  Future<void> forceSync() async {
    final boardId = _currentBoardId;
    if (boardId == null) return;

    try {
      final notifications = <BoardNotification>[];

      Log.i('[NotificationListener] Notifications endpoint not yet implemented; '
          'keeping cached data.');
      // TODO: Replace with backend API call when available.
      // final docs = await ApiService.getNotifications(boardId);
      // for (final data in docs) { ... }

      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _cachedNotifications = notifications;
      _notificationsController.add(_cachedNotifications);

      Log.i('[NotificationListener] Loaded ${notifications.length} notifications');
    } catch (e) {
      Log.w('[NotificationListener] Force sync failed: $e');
    }
  }

  /// Removes a notification from the cache by [id] and emits the updated list.
  void removeNotification(String id) {
    _cachedNotifications.removeWhere((n) => n.id == id);
    _notificationsController.add(_cachedNotifications);
  }

  // ── Debug injection helpers ──────────────────────────────────────

  void injectEmergencyForDebug() {
    _cachedNotifications.insert(0, BoardNotification(
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
    ));
    _notificationsController.add(_cachedNotifications);
  }

  void injectPriority1ForDebug() {
    _cachedNotifications.insert(0, BoardNotification(
      id: 'debug-p1-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Faculty Meeting Reminder',
      body: 'All faculty members are requested to attend the urgent meeting in Conference Room A at 12:00 PM.',
      type: 'alert',
      timestamp: TimeSyncService.timeNow,
      priority: NotificationPriority.high,
    ));
    _notificationsController.add(_cachedNotifications);
  }

  void stop() {
    _currentBoardId = null;
  }

  void dispose() {
    stop();
    _notificationsController.close();
  }
}
