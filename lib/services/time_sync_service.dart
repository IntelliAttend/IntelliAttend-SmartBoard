import 'package:flutter/foundation.dart';
import '../core/security/secure_storage_service.dart';
import '../core/utils/logger.dart';

class TimeSyncService {
  /// The precise millisecond difference between the SmartBoard's hardware clock
  /// and the true time reported by the Python server.
  static int _timeDriftOffset = 0;

  /// Initializes the service by loading the last known skew from secure storage.
  /// Called once at app startup — provides continuity across reboots.
  static Future<void> init() async {
    final cached = await SecureStorageService.getClockSkew();
    if (cached != null) {
      _timeDriftOffset = cached;
      Log.i('[TimeSyncService] Loaded cached clock skew: ${_timeDriftOffset}ms');
    } else {
      Log.i('[TimeSyncService] No cached skew found. Starting at 0ms offset.');
    }
  }

  /// Synchronizes the local hardware clock based on the server's millisecond
  /// timestamp using Round-Trip Time (RTT) math for cryptographic precision.
  ///
  /// The server generates the timestamp right before sending the HTTP response.
  /// The true time at the client's arrival point is: serverTs + (RTT / 2).
  static void synchronizeWithServer(
    DateTime requestSentAt,
    DateTime responseReceivedAt,
    int serverTimestampMs,
  ) {
    final roundTripTime = responseReceivedAt.difference(requestSentAt).inMilliseconds;
    final int trueTimeAtArrival = serverTimestampMs + (roundTripTime ~/ 2);
    final int localTimeAtArrival = responseReceivedAt.millisecondsSinceEpoch;
    _timeDriftOffset = trueTimeAtArrival - localTimeAtArrival;

    // Persist for survival across reboots
    SecureStorageService.storeClockSkew(_timeDriftOffset);

    if (kDebugMode) {
      Log.i('[TimeSyncService] RTT Handshake: rtt=${roundTripTime}ms, skew=${_timeDriftOffset}ms');
    }
  }

  /// Manually sets the clock skew (called by ApiService.syncTime).
  static void setSkew(int skewMs) {
    _timeDriftOffset = skewMs;
    SecureStorageService.storeClockSkew(_timeDriftOffset);
    Log.i('[TimeSyncService] Clock skew updated & persisted: ${_timeDriftOffset}ms');
  }

  /// Returns the current clock skew in milliseconds.
  static int getSkew() => _timeDriftOffset;

  /// Returns the corrected Unix Epoch in seconds (float) as required by v5.2.
  static double get correctedTimestamp =>
      (DateTime.now().millisecondsSinceEpoch + _timeDriftOffset) / 1000.0;

  /// Returns the cryptographically accurate runtime per the server clock.
  static DateTime get timeNow =>
      DateTime.now().add(Duration(milliseconds: _timeDriftOffset));
}
