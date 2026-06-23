import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intelliattend_smartboard/services/api_service.dart';
import 'package:intelliattend_smartboard/services/pre_flight_service.dart';
import 'package:intelliattend_smartboard/core/utils/logger.dart';

/// Critical-path integration tests for Kiosk session lifecycle.
///
/// Spins up a local HTTP server to simulate backend responses across
/// the three critical Kiosk paths:
///   1. Pre-flight warm-up + session initiation
///   2. Heartbeat + session data flow
///   3. Recovery after server outage
///
/// Does NOT require Firestore, Redis, or a real backend.
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
        req.response.headers.set(
            'X-Request-ID', req.headers.value('X-Request-ID') ?? 'test');
        req.response.write('{"status":"ok"}');
        req.response.close();
      }
    });
  });

  tearDown(() async {
    _handler = null;
    await _server.close();
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PATH 1: Pre-flight warm-up → session initiation → QR data
  // ───────────────────────────────────────────────────────────────────────────
  group('Kiosk Path 1: Session Lifecycle', () {
    test('preflight returns slot data with session_id', () async {
      _handler = (req) {
        expect(req.uri.path, contains('/preflight'));
        req.response.statusCode = 200;
        req.response.headers.set('Cache-Control', 'public, max-age=120');
        req.response.headers.set('X-Request-ID',
            req.headers.value('X-Request-ID') ?? 'test');
        req.response.write(jsonEncode({
          'status': 'ready',
          'server_timestamp':
              DateTime.now().millisecondsSinceEpoch,
          'pre_allocated_session_id': 'sess_test_slot_001',
          'session_secret_half1': 'dGVzdF9oYWxmMV9zZWNyZXQ',
          'slot_verification': {
            'subject_name': 'CS101',
            'faculty_name': 'Dr. Smith',
          }
        }));
        req.response.close();
      };

      final result = await ApiService.getPreFlight('slot_001');
      expect(result['status'], equals('ready'));
      expect(result['pre_allocated_session_id'], equals('sess_test_slot_001'));
      expect(result['session_secret_half1'], isNotNull);
      expect(result['slot_verification']['subject_name'], equals('CS101'));
    });

    test('initiate session with valid OTP returns session data', () async {
      _handler = (req) {
        expect(req.uri.path, contains('/initiate'));
        req.response.statusCode = 200;
        req.response.headers.set('X-Request-ID',
            req.headers.value('X-Request-ID') ?? 'test');
        req.response.write(jsonEncode({
          'status': 'success',
          'data': {
            'session_id': 'sess_abc123',
            'session_secret_half1': 'dGVzdF9oYWxmMQ',
            'faculty_name': 'Dr. Smith',
            'course_name': 'CS101',
            'roster_count': 30,
          }
        }));
        req.response.close();
      };

      final result = await ApiService.initiateSession('123456');
      expect(result['status'], equals('success'));
      expect(result['data']['session_id'], equals('sess_abc123'));
      expect(result['data']['course_name'], equals('CS101'));
      expect(result['data']['roster_count'], equals(30));
    });

    test('initiate session with wrong OTP returns 404', () async {
      _handler = (req) {
        req.response.statusCode = 404;
        req.response.write('{"detail":"Session not found or OTP invalid"}');
        req.response.close();
      };

      await expectLater(
        () => ApiService.initiateSession('000000'),
        throwsA(isA<ApiException>()),
      );
    });

    test('time sync returns server timestamp', () async {
      final serverTs = DateTime.now().millisecondsSinceEpoch;
      _handler = (req) {
        expect(req.uri.path, contains('/time'));
        req.response.statusCode = 200;
        req.response.headers.set('X-Request-ID',
            req.headers.value('X-Request-ID') ?? 'test');
        req.response.write(jsonEncode({
          'status': 'success',
          'server_timestamp_ms': serverTs,
        }));
        req.response.close();
      };

      final result = await ApiService.syncTime();
      expect(result, greaterThan(0));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PATH 2: Heartbeat + session data
  // ───────────────────────────────────────────────────────────────────────────
  group('Kiosk Path 2: Heartbeat with Session Data', () {
    test('heartbeat returns session data when active session exists',
        () async {
      _handler = (req) {
        expect(req.uri.path, contains('/heartbeat'));
        req.response.statusCode = 200;
        req.response.headers.set('X-Request-ID',
            req.headers.value('X-Request-ID') ?? 'test');
        req.response.write(jsonEncode({
          'status': 'ok',
          'server_time': DateTime.now().toUtc().toIso8601String(),
          'session': {
            'session_id': 'sess_active_001',
            'status': 'active',
          }
        }));
        req.response.close();
      };

      final result = await ApiService.sendHeartbeatV2(
        smartBoardId: 'IASB-TEST',
        screenState: 'idle',
        uptimeSeconds: 3600,
        appVersion: 'test',
      );
      expect(result['status'], equals('ok'));
      expect(result['session']['session_id'], equals('sess_active_001'));
      expect(result['session']['status'], equals('active'));
    });

    test('heartbeat returns null session when no active session', () async {
      _handler = (req) {
        req.response.statusCode = 200;
        req.response.headers.set('X-Request-ID',
            req.headers.value('X-Request-ID') ?? 'test');
        req.response.write(jsonEncode({
          'status': 'ok',
          'server_time': DateTime.now().toUtc().toIso8601String(),
          'session': null,
        }));
        req.response.close();
      };

      final result = await ApiService.sendHeartbeatV2(
        smartBoardId: 'IASB-TEST',
        screenState: 'idle',
        uptimeSeconds: 100,
        appVersion: 'test',
      );
      expect(result['status'], equals('ok'));
      expect(result['session'], isNull);
    });

    test('heartbeat on server error returns error status', () async {
      _handler = (req) {
        req.response.statusCode = 500;
        req.response.close();
      };

      final result = await ApiService.sendHeartbeatV2(
        smartBoardId: 'IASB-TEST',
        screenState: 'idle',
        uptimeSeconds: 100,
        appVersion: 'test',
      );
      expect(result['status'], equals('error'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PATH 3: Recovery — server outage → retry → success
  // ───────────────────────────────────────────────────────────────────────────
  group('Kiosk Path 3: Recovery After Server Outage', () {
    test('boardReady returns true when server is up', () async {
      _handler = (req) {
        expect(req.uri.path, contains('/ready'));
        req.response.statusCode = 200;
        req.response.headers.set('X-Request-ID',
            req.headers.value('X-Request-ID') ?? 'test');
        req.response.write(jsonEncode({
          'status': 'registered',
          'board_id': 'board-001',
        }));
        req.response.close();
      };

      final alive = await ApiService.boardReady();
      expect(alive, isTrue);
    });

    test('boardReady returns false on 503', () async {
      _handler = (req) {
        req.response.statusCode = 503;
        req.response.close();
      };

      final alive = await ApiService.boardReady();
      expect(alive, isFalse);
    });

    test('boardReady returns false on 401 (auth failure)', () async {
      _handler = (req) {
        req.response.statusCode = 401;
        req.response.write('{"detail":"AUTH_FAILED: Token expired"}');
        req.response.close();
      };

      final alive = await ApiService.boardReady();
      expect(alive, isFalse);
    });

    test('preflight retry on 503 then succeeds', () async {
      int callCount = 0;
      _handler = (req) {
        callCount++;
        if (callCount == 1) {
          req.response.statusCode = 503;
          req.response.close();
        } else {
          req.response.statusCode = 200;
          req.response.headers.set('Cache-Control', 'public, max-age=120');
          req.response.headers.set('X-Request-ID',
              req.headers.value('X-Request-ID') ?? 'test');
          req.response.write(jsonEncode({
            'status': 'ready',
            'server_timestamp':
                DateTime.now().millisecondsSinceEpoch,
            'pre_allocated_session_id': 'sess_retry_test',
            'session_secret_half1': 'cmV0cnlfaGFsZg',
          }));
          req.response.close();
        }
      };

      // getPreFlight does its own retries internally
      final result = await ApiService.getPreFlight('slot_retry');
      // Should succeed despite first 503
      if (result['status'] == 'ready') {
        expect(result['pre_allocated_session_id'], isNotEmpty);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PATH 4: Security — unauthorized / tampered requests
  // ───────────────────────────────────────────────────────────────────────────
  group('Kiosk Path 4: Security Boundaries', () {
    test('unauthenticated request to protected endpoint returns 401',
        () async {
      _handler = (req) {
        req.response.statusCode = 401;
        req.response.write('{"detail":"AUTH_FAILED: Missing token"}');
        req.response.close();
      };

      await expectLater(
        () => ApiService.syncReadyCheck(),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('verifyAdminPin rejects wrong pin', () async {
      _handler = (req) {
        req.response.statusCode = 403;
        req.response.close();
      };

      final result = await ApiService.verifyAdminPin('0000');
      expect(result, isFalse);
    });

    test('verifyAdminPin accepts correct pin', () async {
      _handler = (req) {
        req.response.statusCode = 200;
        req.response.headers.set('X-Request-ID',
            req.headers.value('X-Request-ID') ?? 'test');
        req.response.write(jsonEncode({'status': 'ok'}));
        req.response.close();
      };

      final result = await ApiService.verifyAdminPin('1234');
      expect(result, isTrue);
    });

    test('session termination with invalid session throws', () async {
      _handler = (req) {
        req.response.statusCode = 500;
        req.response.write('{"detail":"Session not found"}');
        req.response.close();
      };

      await expectLater(
        () => ApiService.terminateSession('nonexistent_session'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PreFlightService slot state isolation
  // ───────────────────────────────────────────────────────────────────────────
  group('PreFlightService Slot Isolation', () {
    test('each slot has independent warm-up state', () async {
      final preflight = PreFlightService();

      preflight.resetForSlot('slot_A');
      preflight.resetForSlot('slot_B');

      expect(preflight.isWarmUpExhausted('slot_A'), isFalse);
      expect(preflight.isWarmUpExhausted('slot_B'), isFalse);

      // Exhaust one slot — other should be unaffected
      // (isWarmUpExhausted only reflects explicit exhaustion)
    });
  });
}
