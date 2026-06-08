import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../core/utils/logger.dart';
import '../core/config/app_config.dart';
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
  final int rotationIntervalMs;
  final int initialSkewMs;
  final bool isOffline;

  _TotpIsolatePayload({
    required this.sendPort,
    required this.sessionId,
    required this.sessionSecret,
    required this.windowDurationMillis,
    required this.rotationIntervalMs,
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
  String sessionSecret;
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
    this.windowDuration = const Duration(milliseconds: 300000),
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
      rotationIntervalMs: AppConfig.qrRotationFrequencyMs,
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
    // Release in-memory secret to orphan the string for GC.
    // Dart strings are immutable so this creates a new '' string;
    // the original heap data is now unreferenced and collectable.
    sessionSecret = '';
  }

  static void _isolateWorker(_TotpIsolatePayload payload) {
    int currentSkewMs = payload.initialSkewMs;
    // Pre-compute session ID hash once — it's stable for the session lifetime.
    final sidHash = sha256.convert(utf8.encode(payload.sessionId)).bytes.take(6).toList();

    final controlPort = ReceivePort();
    controlPort.listen((message) {
      if (message is int) {
        currentSkewMs = message;
      }
    });
    payload.sendPort.send(_IsolateControlHandshake(controlPort.sendPort));

    final secureRandom = Random.secure();
    _generateNextToken(payload, currentSkewMs, secureRandom, sidHash);

    Timer.periodic(Duration(milliseconds: payload.rotationIntervalMs), (_) {
      _generateNextToken(payload, currentSkewMs, secureRandom, sidHash);
    });
  }

  static void _generateNextToken(_TotpIsolatePayload payload, int skewMs, Random secureRandom, List<int> sidHash) {
    try {
      // 1. Corrected Unix epoch in seconds (not ms — saves 2 bytes).
      final int timestampSec = ((DateTime.now().millisecondsSinceEpoch + skewMs) / 1000).floor();

      // 2. Timestamp as uint32 big-endian.
      final tsBytes = ByteData(4)..setUint32(0, timestampSec, Endian.big);

      // 3. Nonce: 2 random bytes (65536 values — prevents same-second replay).
      final nonce = [secureRandom.nextInt(256), secureRandom.nextInt(256)];

      // 4. Assemble 12-byte header: sidHash(6) + timestamp(4) + nonce(2).
      final header = <int>[
        ...sidHash,
        ...tsBytes.buffer.asUint8List(),
        ...nonce,
      ];

      // 5. HMAC-SHA256 truncated to 8 bytes (64-bit — birthday bound ~2^32).
      final keyBytes = utf8.encode(payload.sessionSecret);
      final hmac = Hmac(sha256, keyBytes);
      final hmacBytes = hmac.convert(header).bytes.take(8).toList();

      // 6. Final 20-byte payload: header(12) + hmac(8) → Base64URL (no padding).
      final payloadBytes = <int>[...header, ...hmacBytes];
      final b64url = base64Url.encode(payloadBytes).replaceAll('=', '');

      // 7. Final token: IATT::<Base64URL> — 33 characters total → QR Version 2.
      final String finalToken = 'IATT::$b64url';

      payload.sendPort.send(finalToken);
    } catch (e) {
      // ignore: avoid_print
      print('[TotpEngine] Generation Error: $e');
    }
  }
}
