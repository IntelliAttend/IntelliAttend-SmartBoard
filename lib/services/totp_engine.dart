import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';

import '../core/utils/logger.dart';
import 'time_sync_service.dart';

/// Payload structure to pass static data into the memory-isolated thread.
///
/// `initialSkewMs` is only the *starting* offset; once the worker is alive it
/// listens on a control [ReceivePort] for live skew updates pushed from the
/// main isolate (see [TotpEngine._broadcastSkew]). This keeps the QR
/// generator's virtual server clock honest across long classes where the host
/// clock may drift due to OS time corrections, NTP nudges, or CMOS sag.
class _TotpIsolatePayload {
  final SendPort sendPort;
  final String sessionId;
  final String sessionSecret;
  final int windowDurationMillis;
  final int initialSkewMs;
  final bool isOffline;

  _TotpIsolatePayload({
    required this.sendPort,
    required this.sessionId,
    required this.sessionSecret,
    required this.windowDurationMillis,
    required this.initialSkewMs,
    this.isOffline = false,
  });
}

/// Wire-format markers the worker uses on its parent SendPort to distinguish
/// a control handshake (where it ships its own ReceivePort.sendPort back) from
/// a regular QR token broadcast (a plain string).
class _IsolateControlHandshake {
  final SendPort controlPort;
  _IsolateControlHandshake(this.controlPort);
}

class TotpEngine {
  final String sessionId;
  final String sessionSecret;
  final Duration windowDuration;
  final bool isOffline;

  /// How often the main isolate refreshes the worker's view of the server
  /// time skew. 30s is a good balance: NTP and OS time corrections rarely
  /// happen faster, and we don't want to spam the cross-isolate channel.
  static const Duration _skewBroadcastInterval = Duration(seconds: 30);

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _isolateControlPort;
  Timer? _skewBroadcastTimer;
  final _qrStreamController = StreamController<String>.broadcast();

  TotpEngine({
    required this.sessionId,
    required this.sessionSecret,
    this.windowDuration = const Duration(milliseconds: 3500),
    this.isOffline = false,
  });

  Stream<String> get qrStream => _qrStreamController.stream;

  Future<void> start() async {
    // Idempotency guard — calling start() twice without stop() would leak the
    // first isolate, its ReceivePort, and the broadcast timer.
    if (_isolate != null) {
      Log.w(
          '[v5.4 Engine] start() called but isolate already running; ignoring.');
      return;
    }
    _receivePort = ReceivePort();

    _receivePort!.listen((message) {
      if (message is _IsolateControlHandshake) {
        // Worker has come up and handed us its inbound port — store it so we
        // can push skew updates in the future.
        _isolateControlPort = message.controlPort;
        // Send the current skew immediately so the very first token isn't
        // generated against a stale value (the spawn-time skew).
        _isolateControlPort!.send(TimeSyncService.getSkew());
      } else if (message is String) {
        _qrStreamController.add(message);
      }
    });

    // Capture the current drift to seed the isolate. This is also the value
    // that will be used until the first skew-broadcast tick fires.
    final int currentSkew = TimeSyncService.getSkew();

    final payload = _TotpIsolatePayload(
      sendPort: _receivePort!.sendPort,
      sessionId: sessionId,
      sessionSecret: sessionSecret,
      windowDurationMillis: windowDuration.inMilliseconds,
      initialSkewMs: currentSkew,
      isOffline: isOffline,
    );

    _isolate = await Isolate.spawn(_isolateWorker, payload);

    // Periodically push the latest skew into the worker. Done from the main
    // isolate because TimeSyncService's static state lives here, not in the
    // worker.
    _skewBroadcastTimer = Timer.periodic(_skewBroadcastInterval, (_) {
      _broadcastSkew();
    });

    Log.i('[v5.4 Engine] Live-skew Isolate Spawned for Session: $sessionId');
  }

  void _broadcastSkew() {
    final port = _isolateControlPort;
    if (port == null) return;
    final skew = TimeSyncService.getSkew();
    port.send(skew);
    Log.d('[v5.4 Engine] Skew refresh sent to TOTP isolate: ${skew}ms');
  }

  void stop() {
    // Order matters: cancel timer first so no in-flight skew message races
    // with the kill, then drop the control-port reference so future
    // `_broadcastSkew()` calls (if any) early-return, then kill the isolate
    // (which reclaims the worker-side ReceivePort + periodic Timer along
    // with the entire isolate heap), then close the parent ReceivePort, and
    // finally close the broadcast stream.
    _skewBroadcastTimer?.cancel();
    _skewBroadcastTimer = null;
    _isolateControlPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    if (!_qrStreamController.isClosed) {
      _qrStreamController.close();
    }
  }

  static void _isolateWorker(_TotpIsolatePayload payload) {
    // Mutable closure so every timer tick reads the current value, not the
    // value baked in at spawn time.
    int currentSkewMs = payload.initialSkewMs;

    // Inbound channel for skew updates from the main isolate. We hand this
    // port's SendPort back via the parent SendPort using a typed marker so
    // QR-token broadcasts (plain String) and control messages (int skew) can
    // share the same parent channel without ambiguity.
    final controlPort = ReceivePort();
    controlPort.listen((message) {
      if (message is int) {
        currentSkewMs = message;
      }
    });
    payload.sendPort.send(_IsolateControlHandshake(controlPort.sendPort));

    _generateNextToken(payload, currentSkewMs);

    Timer.periodic(Duration(milliseconds: payload.windowDurationMillis), (_) {
      _generateNextToken(payload, currentSkewMs);
    });
  }

  static void _generateNextToken(_TotpIsolatePayload payload, int skewMs) {
    try {
      // 1. Calculate Corrected Unix Epoch in Milliseconds (Virtual Server Clock).
      final int timestampMs = DateTime.now().millisecondsSinceEpoch + skewMs;

      // 2. Construct Data String: session_id|timestamp_ms|nonce
      final String nonce =
          base64.encode(List<int>.generate(4, (_) => Random().nextInt(256)));
      final String dataString = '${payload.sessionId}|$timestampMs|$nonce';

      // 3. Encode to Standard Base64
      final String base64Payload = base64.encode(utf8.encode(dataString));

      // 4. HMAC-SHA256 Cryptographic Signature
      final List<int> keyBytes = utf8.encode(payload.sessionSecret);
      final List<int> messageBytes = utf8.encode(base64Payload);

      final hmac = Hmac(sha256, keyBytes);
      final Digest digest = hmac.convert(messageBytes);

      // 5. Signature Encoding: Hexadecimal
      final String signatureHex = digest.toString();

      // 6. Final Token Assembly: IATT::<payload>::<signature>
      String finalToken = 'IATT::$base64Payload::$signatureHex';

      // v6.1: Trust Engine Offline Flag
      if (payload.isOffline) {
        finalToken += '_offline_generated';
      }

      payload.sendPort.send(finalToken);
    } catch (e) {
      Log.e('[TotpEngine] Generation Error: $e');
    }
  }
}
