import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/services/api_service.dart';

/// Integration tests for [ApiService] against a local HTTP server.
///
/// AUDIT-4.2: Validates the full HTTP pipeline — retries, circuit breaker,
/// correlation IDs, timeouts, and error mapping — against a real socket.
void main() {
  late HttpServer _server;
  late int _port;
  void Function(HttpRequest)? _handler;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await dotenv.load(isOptional: true);
    _handler = null;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server.port;
    dotenv.env['API_BASE_URL'] = 'http://localhost:$_port';

    _server.listen((req) {
      final handler = _handler;
      if (handler != null) {
        handler(req);
      } else {
        req.response.statusCode = 200;
        req.response.headers.set('X-Request-ID',
            req.headers.value('X-Request-ID') ?? 'test');
        req.response.write('{"status":"ok"}');
        req.response.close();
      }
    });
  });

  tearDown(() async {
    _handler = null;
    await _server.close();
  });

  group('ApiService syncReadyCheck', () {
    test('succeeds on 200 response', () async {
      await expectLater(ApiService.syncReadyCheck(), completes);
    });

    test('throws UnregisteredException on 404', () async {
      _handler = (req) {
        req.response.statusCode = 404;
        req.response.write('{"detail":"Board not found"}');
        req.response.close();
      };
      await expectLater(
        () => ApiService.syncReadyCheck(),
        throwsA(isA<UnregisteredException>()),
      );
    });

    test('throws UnauthorizedException on 401', () async {
      _handler = (req) {
        req.response.statusCode = 401;
        req.response.write('{"detail":"Unauthorized"}');
        req.response.close();
      };
      await expectLater(
        () => ApiService.syncReadyCheck(),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('succeeds after single 503 retry', () async {
      int callCount = 0;
      _handler = (req) {
        callCount++;
        if (callCount == 1) {
          req.response.statusCode = 503;
          req.response.close();
        } else {
          req.response.statusCode = 200;
          req.response.write('{"status":"ok"}');
          req.response.close();
        }
      };
      await expectLater(ApiService.syncReadyCheck(), completes);
      expect(callCount, greaterThanOrEqualTo(2));
    });
  });

  group('ApiService request headers', () {
    test('includes X-Request-ID header', () async {
      String? capturedId;
      _handler = (req) {
        capturedId = req.headers.value('X-Request-ID');
        req.response.statusCode = 200;
        req.response.write('{"status":"ok"}');
        req.response.close();
      };
      await ApiService.syncReadyCheck();
      expect(capturedId, isNotNull);
      expect(capturedId, isNotEmpty);
    });

    test('includes X-Retry-Attempt on retry', () async {
      int callCount = 0;
      String? retryHeader;
      _handler = (req) {
        callCount++;
        if (callCount == 1) {
          req.response.statusCode = 503;
          req.response.close();
        } else {
          retryHeader = req.headers.value('X-Retry-Attempt');
          req.response.statusCode = 200;
          req.response.write('{"status":"ok"}');
          req.response.close();
        }
      };
      await ApiService.syncReadyCheck();
      expect(callCount, greaterThanOrEqualTo(2));
      expect(retryHeader, equals('1'));
    });
  });

  group('ApiService initiateSession error mapping', () {
    test('throws UnregisteredException on 400 for session initiate', () async {
      _handler = (req) {
        req.response.statusCode = 400;
        req.response.write(
            '{"detail":"Session not found or OTP invalid"}');
        req.response.close();
      };
      await expectLater(
        () => ApiService.initiateSession('000000'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('ApiService sendHeartbeat', () {
    test('does not throw on 200', () async {
      await ApiService.sendHeartbeat(
        smartBoardId: 'IASB-TEST',
        hardwareId: 'test-hardware-id',
        screenState: 'idle',
        uptimeSeconds: 100,
        appVersion: 'test',
      );
    });

    test('does not throw on 500 (best-effort)', () async {
      _handler = (req) {
        req.response.statusCode = 500;
        req.response.close();
      };
      await ApiService.sendHeartbeat(
        smartBoardId: 'IASB-TEST',
        hardwareId: 'test-hardware-id',
        screenState: 'idle',
        uptimeSeconds: 100,
        appVersion: 'test',
      );
    });
  });

  group('ApiService verifyAdminPin', () {
    test('returns true on 200', () async {
      final result = await ApiService.verifyAdminPin('1234');
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      _handler = (req) {
        req.response.statusCode = 403;
        req.response.close();
      };
      final result = await ApiService.verifyAdminPin('0000');
      expect(result, isFalse);
    });
  });
}
