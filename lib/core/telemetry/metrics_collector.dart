import 'dart:collection';
import '../../services/time_sync_service.dart';

class MetricsCollector {
  static final MetricsCollector _instance = MetricsCollector._();
  factory MetricsCollector() => _instance;
  MetricsCollector._();

  final DateTime _startedAt = DateTime.now();

  int totalScans = 0;
  int sessionsStarted = 0;
  int sessionsTerminated = 0;

  final Queue<DateTime> _apiErrorTimes = Queue<DateTime>();
  DateTime? _currentSessionStart;

  int get apiErrorsLast5Min {
    _pruneApiErrors();
    return _apiErrorTimes.length;
  }

  int get currentSessionDurationSec => _currentSessionStart != null
      ? DateTime.now().difference(_currentSessionStart!).inSeconds
      : 0;

  void recordScan() {
    totalScans++;
  }

  void recordSessionStart() {
    sessionsStarted++;
    _currentSessionStart = DateTime.now();
  }

  void recordSessionEnd() {
    sessionsTerminated++;
    _currentSessionStart = null;
  }

  void recordApiError() {
    _apiErrorTimes.add(DateTime.now());
    _pruneApiErrors();
  }

  void _pruneApiErrors() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    while (_apiErrorTimes.isNotEmpty && _apiErrorTimes.first.isBefore(cutoff)) {
      _apiErrorTimes.removeFirst();
    }
  }

  Map<String, dynamic> toJson() {
    final elapsedMin = DateTime.now().difference(_startedAt).inMinutes;
    final rate = elapsedMin > 0
        ? (totalScans / elapsedMin).toStringAsFixed(1)
        : '0.0';
    return {
      'total_scans': totalScans,
      'scan_rate_per_min': rate,
      'sessions_started': sessionsStarted,
      'sessions_terminated': sessionsTerminated,
      'api_errors_5min': apiErrorsLast5Min,
      'current_session_duration_sec': currentSessionDurationSec,
      'clock_skew_ms': TimeSyncService.getSkew(),
    };
  }
}
