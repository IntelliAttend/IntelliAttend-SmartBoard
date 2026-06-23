import 'package:flutter/foundation.dart';
import '../core/security/secure_storage_service.dart';
import '../core/utils/logger.dart';

class TimeSyncService {
  /// The precise millisecond difference between the SmartBoard's hardware clock
  /// and the true time reported by the Python server.
  static int _timeDriftOffset = 0;

  /// Unix timestamp (ms) when the skew was last synced with the server.
  static int? _lastSyncedAt;

  /// Maximum age (1 hour) before cached skew is considered stale.
  static const int _maxSkewAgeMs = Duration.millisecondsPerHour;

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
  }

  /// Returns true when no skew data exists or the last sync is older than 1 hour.
  static bool get isSkewStale {
    if (_lastSyncedAt == null) return true;
    final age = DateTime.now().millisecondsSinceEpoch - _lastSyncedAt!;
    return age > _maxSkewAgeMs;
  }

  static void _persistSkew() {
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
    _timeDriftOffset = offset;
    _persistSkew();

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
    _timeDriftOffset = trueTimeAtArrival - localTimeAtArrival;
    _persistSkew();

    if (kDebugMode) {
      Log.i('[TimeSyncService] RTT Handshake (legacy): rtt=${roundTripTime}ms, skew=${_timeDriftOffset}ms');
    }
  }

  /// Manually sets the clock skew.
  static void setSkew(int skewMs) {
    _timeDriftOffset = skewMs;
    _persistSkew();
    Log.i('[TimeSyncService] Clock skew updated & persisted: ${_timeDriftOffset}ms');
  }

  /// Returns the current clock skew in milliseconds.
  static int getSkew() => _timeDriftOffset;

  /// Returns the corrected Unix Epoch in seconds (float).
  static double get correctedTimestamp =>
      (DateTime.now().millisecondsSinceEpoch + _timeDriftOffset) / 1000.0;

  /// Returns the cryptographically accurate runtime per the server clock.
  static DateTime get timeNow =>
      DateTime.now().add(Duration(milliseconds: _timeDriftOffset));
}
