class TimeSyncService {
  /// The precise millisecond difference between the SmartBoard's hardware clock 
  /// and the true time reported by the Python server.
  /// This exists ONLY in RAM to comply with v5.2 Volatile Memory guardrails.
  static int _timeDriftOffset = 0;

  /// Synchronizes the local hardware clock based on the Python server's millisecond timestamp
  /// using Round-Trip Time (RTT) math for cryptographic precision.
  static void synchronizeWithServer(DateTime requestSentAt, DateTime responseReceivedAt, int serverTimestampMs) {
    // RTT = When we got the response - When we sent the request
    final roundTripTime = responseReceivedAt.difference(requestSentAt).inMilliseconds;
    
    // The Python server generated the timestamp right before sending the HTTP response.
    // The exact true time when the packet arrived is the server's time + half of the transit time (RTT/2).
    final int trueTimeAtArrival = serverTimestampMs + (roundTripTime ~/ 2);
    
    // The hardware skew is the difference between that mathematical true time and the local clock.
    final int localTimeAtArrival = responseReceivedAt.millisecondsSinceEpoch;
    _timeDriftOffset = trueTimeAtArrival - localTimeAtArrival;
    
    print('--- [v5.3] Millisecond Handshake Complete ---');
    print('Round-Trip Time (RTT): ${roundTripTime}ms');
    print('Time Drift Offset Applied: ${_timeDriftOffset}ms');
  }

  /// Manually sets the clock skew. (v5.3 Spec)
  static void setSkew(int skewMs) {
    _timeDriftOffset = skewMs;
    print('--- [v5.3] Clock Skew Updated: ${_timeDriftOffset}ms ---');
  }

  /// Returns the current clock skew in milliseconds.
  static int getSkew() => _timeDriftOffset;

  /// Returns the corrected Unix Epoch in seconds (float) as required by v5.2.
  static double get correctedTimestamp => (DateTime.now().millisecondsSinceEpoch + _timeDriftOffset) / 1000.0;

  /// Returns the cryptographically accurate runtime according to the Python Server.
  static DateTime get timeNow => DateTime.now().add(Duration(milliseconds: _timeDriftOffset));
}
