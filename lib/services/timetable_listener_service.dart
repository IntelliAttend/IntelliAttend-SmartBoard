import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/isar_schemas.dart';
import '../core/utils/logger.dart';
import 'session_manager.dart';
import 'timetable_cache.dart';

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
  bool get isHealthy =>
      _lastSnapshotTime != null &&
      DateTime.now().difference(_lastSnapshotTime!) < _staleThreshold;

  void start(String smartBoardId, {void Function()? restFallback}) {
    if (_subscription != null && _currentBoardId == smartBoardId) return;

    stop();
    _currentBoardId = smartBoardId;
    _restFallback = restFallback;

    _subscription = FirebaseFirestore.instance
        .collection('timetable_slots')
        .where('smart_board_id', isEqualTo: smartBoardId)
        .snapshots(includeMetadataChanges: false)
        .listen(
          _onTimetableChanged,
          onError: _onError,
          onDone: _onDone,
          cancelOnError: false,
        );

    _startHealthMonitor();

    Log.i(
        '[TimetableListener] Listening for changes (board: $smartBoardId)');
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
      final minutesSince =
          DateTime.now().difference(_lastSnapshotTime!).inMinutes;
      Log.w(
          '[TimetableListener] No snapshot in $minutesSince min — triggering REST fallback');
      _restFallback?.call();
    }
  }

  void _onDone() {
    Log.w(
        '[TimetableListener] Stream closed unexpectedly. Check Firebase connection.');
    _lastSnapshotTime = null;
    _healthTimer?.cancel();
  }

  void _onTimetableChanged(QuerySnapshot snapshot) async {
    _lastSnapshotTime = DateTime.now();

    try {
      final entries = <TimetableEntry>[];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        entries.add(_docToEntry(doc.id, data));
      }

      final isar = SessionManager.isar;
      await isar.writeTxn(() async {
        await isar.timetableEntrys.clear();
        await isar.timetableEntrys.putAll(entries);
      });

      TimetableCache().updateAll(entries);

      Log.i(
          '[TimetableListener] Updated ${entries.length} entries from snapshot');
    } catch (e) {
      Log.e('[TimetableListener] Failed to process update: $e');
    }
  }

  void _onError(Object error) {
    Log.e('[TimetableListener] Snapshot error: $error');
  }

  TimetableEntry _docToEntry(String docId, Map<String, dynamic> data) {
    final facultyEmail = data['faculty_id']?.toString() ??
        (data['faculty_emails'] as List?)?.firstOrNull?.toString() ?? '';

    return TimetableEntry()
      ..slotId = docId
      ..dayOfWeek = _dayNumber(data['day_of_week']?.toString() ?? '')
      ..startTime = data['start_time']?.toString() ?? ''
      ..endTime = data['end_time']?.toString() ?? ''
      ..courseName = data['subject_name']?.toString() ?? 'Class'
      ..facultyName = facultyEmail
      ..sectionId = data['section_id']?.toString() ?? 'N/A';
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
    return idx != -1 ? idx + 1 : DateTime.now().weekday;
  }
}
