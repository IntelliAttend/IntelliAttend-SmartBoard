
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

class TotpEngine {
  static const int rotationWindowMs = 3500; // 3.5 second window

  static void run(SendPort mainSendPort) {
    // Receive configuration (seed and clock_skew) from main thread
    final ReceivePort configReceivePort = ReceivePort();
    mainSendPort.send(configReceivePort.sendPort);

    configReceivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final String secret = message['secret'];
        final Duration clockSkew = message['skew'] as Duration;
        
        // Start the 3.5s loop
        Timer.periodic(const Duration(milliseconds: rotationWindowMs), (timer) {
          final DateTime adjustedNow = DateTime.now().add(clockSkew);
          
          // Calculate the epoch window (RFC 6238 modification)
          final int epoch = (adjustedNow.millisecondsSinceEpoch ~/ rotationWindowMs);
          
          // HMAC-SHA256(session_secret, epoch)
          final String token = _generateHash(secret, epoch);
          
          // Send back to main thread to update UI
          mainSendPort.send({
            'token': token,
            'expires_at': (epoch + 1) * rotationWindowMs,
            'sequence': timer.tick
          });
        });
      }
    });
  }

  static String _generateHash(String secret, int epoch) {
    final List<int> secretBytes = utf8.encode(secret);
    final List<int> epochBytes = utf8.encode(epoch.toString());
    
    final Hmac hmac = Hmac(sha256, secretBytes);
    final Digest digest = hmac.convert(epochBytes);
    
    return digest.toString();
  }
}
