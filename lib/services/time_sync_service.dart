class TimeSyncService {
  /// The precise millisecond difference between the SmartBoard's hardware clock 
  /// and the true time reported by the Python server.
  static Duration _clockSkew = Duration.zero;

  /// Synchronizes the local hardware clock based on the Python server's exact timestamp
  /// using Round-Trip Time (RTT) math for cryptographic precision.
  static void synchronizeWithServer(DateTime requestSentAt, DateTime responseReceivedAt, DateTime pythonServerTime) {
    // RTT = When we got the response - When we sent the request
    final roundTripTime = responseReceivedAt.difference(requestSentAt);
    
    // The Python server generated the timestamp right before sending the HTTP response.
    // The exact true time when the packet arrived is the server's time + half of the transit time (RTT/2).
    final trueTimeAtArrival = pythonServerTime.add(Duration(milliseconds: roundTripTime.inMilliseconds ~/ 2));
    
    // The hardware skew is the difference between that mathematical true time and the uncorrected Windows clock.
    _clockSkew = trueTimeAtArrival.difference(responseReceivedAt);
    
    print('--- Python Server RTT Sync ---');
    print('Round-Trip Time (RTT): ${roundTripTime.inMilliseconds}ms');
    print('Hardware Clock Skew Applied: ${_clockSkew.inMilliseconds}ms');
  }

  /// Returns the cryptographically accurate runtime according to the Python Server.
  /// ALL TOTP QR generation functions MUST use this getter to guarantee hash validation.
  static DateTime get timeNow => DateTime.now().add(_clockSkew);
}
