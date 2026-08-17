import 'package:flutter/foundation.dart';
import '../models/isar_schemas.dart';
import 'time_sync_service.dart';

class TimetableCache extends ChangeNotifier {
  static final TimetableCache _instance = TimetableCache._internal();
  factory TimetableCache() => _instance;
  TimetableCache._internal();

  List<TimetableEntry> _weeklyTimeline = [];

  List<TimetableEntry> get weeklyTimeline =>
      List.unmodifiable(_weeklyTimeline);

  List<TimetableEntry> get todayTimeline {
    final dayOfWeek = TimeSyncService.timeNow.weekday;
    final today = _weeklyTimeline
        .where((e) => e.dayOfWeek == dayOfWeek)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return today;
  }

  TimetableEntry? get currentSlot {
    final now = TimeSyncService.timeNow;
    final currentMinutes = now.hour * 60 + now.minute;

    // Only return regular class/lab slots — never break, tutorial, or library slots
    for (final entry in todayTimeline) {
      if (entry.isBreak) continue;
      if (entry.slotType == 'tutorial' || entry.slotType == 'library') continue;
      final startParts = entry.startTime.split(':');
      final endParts = entry.endTime.split(':');
      if (startParts.length != 2 || endParts.length != 2) continue;

      final startMins =
          int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMins = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

      if (endMins < startMins) {
        if (currentMinutes >= startMins || currentMinutes < endMins) {
          return entry;
        }
      } else {
        if (currentMinutes >= startMins && currentMinutes < endMins) {
          return entry;
        }
      }
    }
    return null;
  }

  void updateAll(List<TimetableEntry> entries) {
    _weeklyTimeline = List.from(entries);
    notifyListeners();
  }
}
