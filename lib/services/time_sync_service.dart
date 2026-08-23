import 'dart:io';

import 'package:flutter/foundation.dart';
import '../core/security/secure_storage_service.dart';
import '../core/utils/logger.dart';

class TimeSyncService {
  static bool _initialized = false;

  /// The precise millisecond difference between the SmartBoard's hardware clock
  /// and the true time reported by the Python server.
  static int _timeDriftOffset = 0;

  /// Unix timestamp (ms) when the skew was last synced with the server.
  static int? _lastSyncedAt;

  /// Maximum age (1 hour) before cached skew is considered stale.
  static const int _maxSkewAgeMs = Duration.millisecondsPerHour;

  /// Skew threshold (1 second) above which we attempt to auto-correct the
  /// system clock via PowerShell (requires admin rights).
  static const int _autoCorrectThresholdMs = 1000;

  /// Minimum interval between auto-correct attempts (1 hour).
  static const int _minAutoCorrectIntervalMs = Duration.millisecondsPerHour;

  /// When the last auto-correct was attempted.
  static int? _lastAutoCorrectAt;

  /// When the last timezone check was attempted.
  static int? _lastTimezoneCheckAt;

  /// Minimum interval between timezone check attempts (24 hours).
  static const int _minTimezoneCheckIntervalMs = 24 * Duration.millisecondsPerHour;

  /// Skew threshold (30 minutes) above which the offset is likely a timezone
  /// mismatch rather than simple clock drift.
  static const int _timezoneMismatchThresholdMs = 30 * 60 * 1000;

  /// Maximum sane clock drift (5 minutes). Offsets larger than this are
  /// likely caused by a network error or misconfigured server and should
  /// be rejected to prevent corrupting timeNow across the entire app.
  static const int _maxSaneOffsetMs = 5 * 60 * 1000;

  /// Initializes the service by loading the last known skew from secure storage.
  static Future<void> init() async {
    final cached = await SecureStorageService.getClockSkew();
    if (cached != null) {
      _timeDriftOffset = cached;
      _lastSyncedAt = await SecureStorageService.getClockSkewTimestamp();
      Log.i('[TimeSyncService] Loaded cached clock skew: ${_timeDriftOffset}ms'
          '${_lastSyncedAt != null ? ' (synced ${DateTime.fromMillisecondsSinceEpoch(_lastSyncedAt!)})' : ' (no sync timestamp)'}');
    } else {
      Log.i('[TimeSyncService] No cached skew found. Starting at 0ms offset.');
    }
    _initialized = true;
  }

  /// Returns true when no skew data exists or the last sync is older than 1 hour.
  static bool get isSkewStale {
    if (!_initialized) return true;
    if (_lastSyncedAt == null) return true;
    final age = DateTime.now().millisecondsSinceEpoch - _lastSyncedAt!;
    return age > _maxSkewAgeMs;
  }

  static void _persistSkew() {
    if (!_initialized) return;
    _lastSyncedAt = DateTime.now().millisecondsSinceEpoch;
    SecureStorageService.storeClockSkew(_timeDriftOffset);
    SecureStorageService.storeClockSkewTimestamp(_lastSyncedAt!);
  }

  /// NTP-style clock synchronisation.
  ///
  /// Uses the server's `server_received_at_ms` (the server clock reading when
  /// it received our request) and the round-trip time to compute a clock offset.
  ///
  /// Formula (same as NTP):
  ///   offset = server_received_at_ms - (t0 + rtt/2)
  ///   where t0 = local time just before sending, t3 = local time just after
  ///   receiving, and rtt = t3 - t0.
  static void synchronizeWithServer(
    int t0,                    // local ms before request
    int t3,                    // local ms after response
    int serverReceivedAtMs,    // server clock when it received our request
  ) {
    final rtt = t3 - t0;
    final offset = serverReceivedAtMs - (t0 + rtt ~/ 2);

    // Sanity check: reject offsets larger than 5 minutes — likely a network
    // error or misconfigured server response.
    if (offset.abs() > _maxSaneOffsetMs) {
      Log.w('[TimeSyncService] NTP sync rejected: offset ${offset}ms '
          'exceeds ${_maxSaneOffsetMs}ms max. Keeping previous offset ${_timeDriftOffset}ms.');
      return;
    }

    _timeDriftOffset = offset;
    _persistSkew();
    _tryAutoCorrectTimezone();
    _tryAutoCorrectSystemClock();

    if (kDebugMode) {
      Log.i('[TimeSyncService] NTP sync: rtt=${rtt}ms, offset=${_timeDriftOffset}ms');
    }
  }

  /// Legacy sync — kept for backward compatibility.
  /// Uses `server_timestamp_ms` (server response time) instead of
  /// `server_received_at_ms`.
  static void synchronizeWithServerLegacy(
    DateTime requestSentAt,
    DateTime responseReceivedAt,
    int serverTimestampMs,
  ) {
    final roundTripTime = responseReceivedAt.difference(requestSentAt).inMilliseconds;
    final int trueTimeAtArrival = serverTimestampMs + (roundTripTime ~/ 2);
    final int localTimeAtArrival = responseReceivedAt.millisecondsSinceEpoch;
    final int offset = trueTimeAtArrival - localTimeAtArrival;

    // Sanity check: reject offsets larger than 5 minutes.
    if (offset.abs() > _maxSaneOffsetMs) {
      Log.w('[TimeSyncService] Legacy sync rejected: offset ${offset}ms '
          'exceeds ${_maxSaneOffsetMs}ms max. Keeping previous offset ${_timeDriftOffset}ms.');
      return;
    }

    _timeDriftOffset = offset;
    _persistSkew();
    _tryAutoCorrectTimezone();
    _tryAutoCorrectSystemClock();

    if (kDebugMode) {
      Log.i('[TimeSyncService] RTT Handshake (legacy): rtt=${roundTripTime}ms, skew=${_timeDriftOffset}ms');
    }
  }

  /// Manually sets the clock skew.
  static void setSkew(int skewMs) {
    if (skewMs.abs() > _maxSaneOffsetMs) {
      Log.w('[TimeSyncService] setSkew rejected: ${skewMs}ms '
          'exceeds ${_maxSaneOffsetMs}ms max. Keeping previous offset ${_timeDriftOffset}ms.');
      return;
    }
    _timeDriftOffset = skewMs;
    _persistSkew();
    _tryAutoCorrectTimezone();
    _tryAutoCorrectSystemClock();
    Log.i('[TimeSyncService] Clock skew updated & persisted: ${_timeDriftOffset}ms');
  }

  /// Attempt to correct the Windows timezone if the drift offset suggests a
  /// timezone mismatch (>30 minutes). The drift offset compensates at the
  /// application level, but a wrong timezone breaks `DateTime.now()` for any
  /// code that bypasses `TimeSyncService.timeNow`.
  ///
  /// Uses `tzutil /s "India Standard Time"` (Windows only). Requires admin
  /// rights; silently falls back on failure.
  static Future<void> _tryAutoCorrectTimezone() async {
    if (!Platform.isWindows) return;
    if (_timeDriftOffset.abs() < _timezoneMismatchThresholdMs) return;

    // Rate-limit timezone checks to once per 24 hours
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastTimezoneCheckAt != null &&
        (now - _lastTimezoneCheckAt!) < _minTimezoneCheckIntervalMs) {
      return;
    }
    _lastTimezoneCheckAt = now;

    // Detect local UTC offset from the OS timezone
    final localUtcOffset = DateTime.now().timeZoneOffset;
    final expectedOffset = const Duration(hours: 5, minutes: 30); // IST
    final offsetDiff = (localUtcOffset - expectedOffset).inMinutes.abs();

    if (offsetDiff < 30) {
      // Timezone appears correct — the drift is likely pure clock drift
      Log.d('[TimeSyncService] Timezone check: local UTC offset '
          '${localUtcOffset.inHours}h${localUtcOffset.inMinutes.remainder(60)}m '
          'matches expected IST (diff=${offsetDiff}min)');
      return;
    }

    Log.w('[TimeSyncService] Timezone mismatch detected: '
        'local UTC offset is ${localUtcOffset.inHours}h'
        '${localUtcOffset.inMinutes.remainder(60)}m, '
        'expected IST (UTC+5:30). '
        'Drift offset=${_timeDriftOffset}ms. '
        'Attempting to correct Windows timezone...');

    try {
      final result = await Process.run(
        'tzutil',
        ['/s', 'India Standard Time'],
      ).timeout(const Duration(seconds: 10));

      if (result.exitCode == 0) {
        Log.i('[TimeSyncService] Windows timezone corrected to '
            '"India Standard Time". '
            'Resetting drift offset — time is now correct. '
            'Next pre-flight call will recalibrate precisely.');
        // The cached drift offset was computed against the WRONG timezone.
        // Reset to 0 so TimeSyncService.timeNow uses the corrected local
        // clock. With the correct timezone + offset 0, time is accurate.
        // The next pre-flight call will recalibrate to sub-second precision.
        _timeDriftOffset = 0;
        _persistSkew();
      } else {
        Log.w('[TimeSyncService] Timezone correction failed '
            '(exit ${result.exitCode}): ${result.stderr}');
      }
    } catch (e) {
      Log.w('[TimeSyncService] Timezone correction not available '
          '(admin rights may be required): $e');
    }
  }

  /// Attempt to correct the Windows system clock via PowerShell if skew exceeds
  /// [_autoCorrectThresholdMs]. Requires admin rights; silently falls back on failure.
  static Future<void> _tryAutoCorrectSystemClock() async {
    if (!Platform.isWindows) return;
    if (_timeDriftOffset.abs() < _autoCorrectThresholdMs) return;

    // Rate-limit auto-correct attempts
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastAutoCorrectAt != null &&
        (now - _lastAutoCorrectAt!) < _minAutoCorrectIntervalMs) {
      return;
    }
    _lastAutoCorrectAt = now;

    try {
      final targetTime = DateTime.now()
          .add(Duration(milliseconds: _timeDriftOffset));
      final timeStr = '${targetTime.year}-'
          '${_pad(targetTime.month)}-${_pad(targetTime.day)} '
          '${_pad(targetTime.hour)}:${_pad(targetTime.minute)}:${_pad(targetTime.second)}';
      Log.i('[TimeSyncService] Attempting system clock correction via PowerShell '
          '(skew=${_timeDriftOffset}ms, target=$timeStr)...');

      final result = await Process.run(
        'powershell',
        ['-Command', "Set-Date '$timeStr'"],
      ).timeout(const Duration(seconds: 10));

      if (result.exitCode == 0) {
        Log.i('[TimeSyncService] System clock corrected successfully.');
        _timeDriftOffset = 0;
        _persistSkew();
      } else {
        Log.w('[TimeSyncService] System clock correction failed '
            '(exit ${result.exitCode}): ${result.stderr}');
      }
    } catch (e) {
      Log.w('[TimeSyncService] System clock correction not available '
          '(admin rights may be required): $e');
    }
  }

  /// Pad a 2-digit number (e.g. month, day, hour).
  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Returns the current clock skew in milliseconds.
  static int getSkew() => _timeDriftOffset;

  /// Returns the corrected Unix Epoch in seconds (float).
  static double get correctedTimestamp =>
      (DateTime.now().millisecondsSinceEpoch + _timeDriftOffset) / 1000.0;

  /// Returns the cryptographically accurate runtime per the server clock.
  static DateTime get timeNow =>
      DateTime.now().add(Duration(milliseconds: _timeDriftOffset));
}