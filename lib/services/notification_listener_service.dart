import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
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
  final String? attachmentUrl;
  final String? attachmentName;
  final String? attachmentType;
  final int? attachmentSize;

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

  factory BoardNotification.fromMap(String id, Map<String, dynamic> data) {
    int? parseSize(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

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
      attachmentUrl: data[FirestoreSchema.fieldAttachmentUrl]?.toString(),
      attachmentName: data[FirestoreSchema.fieldAttachmentName]?.toString(),
      attachmentType: data[FirestoreSchema.fieldAttachmentType]?.toString(),
      attachmentSize: parseSize(data[FirestoreSchema.fieldAttachmentSize]),
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
      BoardNotification(
        id: 'sample-pdf-1',
        title: 'Lecture Notes — Week 10',
        body: 'Dr. Sharma shared PDF notes for this week\'s lecture on Neural Networks. Includes diagrams, key concepts, and practice problems.',
        type: 'message',
        timestamp: now,
        attachmentUrl: pdf1,
        attachmentName: 'CSE_AIML_Week10_Notes.pdf',
        attachmentType: 'application/pdf',
        attachmentSize: 13264,
      ),
      BoardNotification(
        id: 'sample-pdf-2',
        title: 'Complete Reference — Machine Learning',
        body: 'Full semester reference handbook covering all ML algorithms from linear regression to deep reinforcement learning.',
        type: 'message',
        timestamp: now.subtract(const Duration(minutes: 2)),
        attachmentUrl: pdf2,
        attachmentName: 'Complete_ML_Reference.pdf',
        attachmentType: 'application/pdf',
        attachmentSize: 20597,
      ),
      BoardNotification(
        id: 'sample-docx',
        title: 'Assignment Guidelines — Final Project',
        body: 'Dr. Mehta posted the guidelines for the end-semester project. Includes formatting requirements, rubric, and sample structure.',
        type: 'message',
        timestamp: now.subtract(const Duration(minutes: 5)),
        attachmentUrl: docx,
        attachmentName: 'Final_Project_Guidelines.docx',
        attachmentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        attachmentSize: 1660,
      ),
      BoardNotification(
        id: 'sample-pptx',
        title: 'Faculty Presentation — Deep Learning',
        body: 'Slides from today\'s guest lecture on CNNs, RNNs, and Transformer architectures with real-world case studies.',
        type: 'message',
        timestamp: now.subtract(const Duration(minutes: 8)),
        attachmentUrl: pptx,
        attachmentName: 'Deep_Learning_Session.pptx',
        attachmentType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        attachmentSize: 2881,
      ),
      BoardNotification(
        id: 'sample-xlsx',
        title: 'Grade Sheet — Midterm Results',
        body: 'Consolidated midterm scores for CSE-AIML Section A. Please verify your marks by end of week.',
        type: 'attendance',
        timestamp: now.subtract(const Duration(minutes: 12)),
        attachmentUrl: xlsx,
        attachmentName: 'Midterm_Grades_SecA.xlsx',
        attachmentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        attachmentSize: 2165,
      ),
      BoardNotification(
        id: 'sample-txt',
        title: 'Lab Manual — Python Programming',
        body: 'Step-by-step lab instructions for Experiment 1: Introduction to Python. Includes sample code and expected output.',
        type: 'message',
        timestamp: now.subtract(const Duration(minutes: 18)),
        attachmentUrl: txt,
        attachmentName: 'Lab1_Python_Intro.txt',
        attachmentType: 'text/plain',
        attachmentSize: 1782,
      ),
      BoardNotification(
        id: 'sample-md',
        title: 'Course Syllabus — Machine Learning',
        body: 'Detailed syllabus for CSE-AIML 305 covering all 5 modules, assessment breakdown, and recommended textbooks.',
        type: 'message',
        timestamp: now.subtract(const Duration(minutes: 25)),
        attachmentUrl: md,
        attachmentName: 'ML_Syllabus.md',
        attachmentType: 'text/markdown',
        attachmentSize: 1833,
      ),
      BoardNotification(
        id: 'sample-html',
        title: 'Academic Calendar 2026',
        body: 'Department-wide academic schedule including exam dates, holidays, project fairs, and placement drives.',
        type: 'system',
        timestamp: now.subtract(const Duration(minutes: 35)),
        attachmentUrl: html,
        attachmentName: 'Academic_Calendar_2026.html',
        attachmentType: 'text/html',
        attachmentSize: 3137,
      ),
      BoardNotification(
        id: 'sample-png',
        title: 'Attendance Chart — June 2026',
        body: 'Monthly attendance visualization from the admin dashboard. Shows class-wise and individual trends.',
        type: 'attendance',
        timestamp: now.subtract(const Duration(minutes: 50)),
        attachmentUrl: png,
        attachmentName: 'Attendance_Chart_June2026.png',
        attachmentType: 'image/png',
        attachmentSize: 457,
      ),
      BoardNotification(
        id: 'sample-ppt',
        title: 'Orientation Slides — Industry Visit',
        body: 'Presentation from the pre-visit orientation for the upcoming industry visit to Microsoft Research Lab.',
        type: 'message',
        timestamp: now.subtract(const Duration(hours: 1)),
        attachmentUrl: ppt,
        attachmentName: 'Industry_Visit_Orientation.ppt',
        attachmentType: 'application/vnd.ms-powerpoint',
        attachmentSize: 8,
      ),
    ];
    _notificationsController.add(_cachedNotifications);
    Log.i('[NotificationListener] Injected ${_cachedNotifications.length} sample notifications with local documents');
  }

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
