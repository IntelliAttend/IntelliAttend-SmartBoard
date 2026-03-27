import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

import 'time_sync_service.dart';

/// Payload structure to pass static data into the memory-isolated thread
class _TotpIsolatePayload {
  final SendPort sendPort;
  final String sessionSecret;
  final int clockSkewMillis;
  final int windowDurationMillis;

  _TotpIsolatePayload(this.sendPort, this.sessionSecret, this.clockSkewMillis, this.windowDurationMillis);
}

class TotpEngine {
  final String sessionSecret;
  final Duration windowDuration;
  
  Isolate? _isolate;
  ReceivePort? _receivePort;
  final _qrStreamController = StreamController<String>.broadcast();
  
  TotpEngine({
    required this.sessionSecret, 
    this.windowDuration = const Duration(milliseconds: 3500) // The aggressive 3.5s sprint requirement
  });

  /// The stream pumping new cryptographic hashes to the UI layer
  Stream<String> get qrStream => _qrStreamController.stream;

  /// Spawns the dedicated background thread for mathematical operations
  Future<void> start() async {
    _receivePort = ReceivePort();
    
    // Listen for hashes coming back from the worker Isolate
    _receivePort!.listen((message) {
      if (message is String) {
        _qrStreamController.add(message);
      }
    });

    // We must extract the skew here, because TimeSyncService._clockSkew 
    // lives in the main Isolate's memory!
    final currentSkewMillis = TimeSyncService.timeNow.difference(DateTime.now()).inMilliseconds;

    final payload = _TotpIsolatePayload(
      _receivePort!.sendPort, 
      sessionSecret, 
      currentSkewMillis, 
      windowDuration.inMilliseconds
    );

    _isolate = await Isolate.spawn(_isolateWorker, payload);
    print('[TOTP Engine] Sprint Isolate Spawned.');
  }

  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _qrStreamController.close();
    print('[TOTP Engine] Sprint Terminated at 00:00.');
  }

  /// The isolated, untouchable mathematical loop.
  /// Runs completely independently of the main UI thread.
  static void _isolateWorker(_TotpIsolatePayload payload) {
    // Generate immediately
    _generateNextToken(payload);
    
    // Run the un-blockable loop forever (until Isolate is killed)
    Timer.periodic(Duration(milliseconds: payload.windowDurationMillis), (_) {
      _generateNextToken(payload);
    });
  }

  static void _generateNextToken(_TotpIsolatePayload payload) {
    // 1. Recreate the True Mathematical Time using the injected skew offset
    final DateTime uncorrectedTime = DateTime.now();
    final DateTime trueTime = uncorrectedTime.add(Duration(milliseconds: payload.clockSkewMillis));
    
    // 2. Convert to Windowed Epoch Frame
    final int epochMillis = trueTime.millisecondsSinceEpoch;
    final int timeWindowCounter = epochMillis ~/ payload.windowDurationMillis;
    
    // 3. Generate Crypto Hash Identity
    final String rawPayload = '${payload.sessionSecret}|$timeWindowCounter';
    final List<int> bytes = utf8.encode(rawPayload);
    final Digest digest = sha256.convert(bytes);
    
    final qrToken = digest.toString();
    
    // Fire it back across the memory boundary to the UI Thread
    payload.sendPort.send(qrToken);
  }
}
