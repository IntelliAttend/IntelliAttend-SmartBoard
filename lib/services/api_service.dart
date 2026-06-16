import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import 'package:http/http.dart' as http;

import '../core/utils/logger.dart';
import '../core/config/app_config.dart';
import '../core/telemetry/metrics_collector.dart';
import '../core/platform/hardware_fingerprint_service.dart';
import '../core/security/ssl_pinning_service.dart';
import '../core/circuit_breaker.dart';
import 'time_sync_service.dart';
import '../core/auth/token_manager.dart';

class ApiException implements Exception {
  final String userMessage;
  final int statusCode;
  ApiException(this.userMessage, this.statusCode);

  @override
  String toString() => userMessage;
}

class UnregisteredException extends ApiException {
  UnregisteredException(String message) : super(message, 404);
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(String message) : super(message, 401);
}

class ApiService {
  // ─── Circuit Breakers (AUDIT-2.4) ─────────────────────────────────────────
  //
  // Per-endpoint circuit breakers to prevent cascading failures. Keyed by the
  // URL path — shared across code paths that call the same endpoint.
  static final Map<String, CircuitBreaker> _breakers = {};
  static const int _cbFailureThreshold = 5;
  static const Duration _cbCooldown = Duration(seconds: 60);

  static CircuitBreaker _breakerFor(String path) {
    return _breakers.putIfAbsent(
        path,
        () => CircuitBreaker(
              name: path,
              failureThreshold: _cbFailureThreshold,
              cooldown: _cbCooldown,
            ));
  }

  // ─── URL Resolution ───────────────────────────────────────────────────────

  static String get _baseUrl => AppConfig.baseUrl;

  /// Build a URI from a path segment, normalizing double slashes.
  /// Query parameters are passed as a typed map — never embed `?key=val` in [path].
  static Future<Uri> _buildUri(String path,
      {Map<String, String>? queryParameters}) async {
    final baseUri = Uri.parse(_baseUrl);
    final cleanPath = '/${path.replaceAll(RegExp(r'/+'), '/')}'
        .replaceFirst(RegExp(r'^//+'), '/');
    return baseUri.replace(path: cleanPath, queryParameters: queryParameters);
  }

  static http.Client get _client => SslPinningService.client;

  // ─── Correlation ID (AUDIT-2.8) ───────────────────────────────────────────
  //
  // Every outbound API call gets a unique X-Request-ID so that errors can be
  // traced from the SmartBoard UI to the backend logs. The format is:
  //   <timestamp_ms>-<random_6digit>
  // Example: 1715112345678-483291

  static final _uuid = const Uuid();
  static String _generateRequestId() => _uuid.v4();

  /// Centralized request handler to enforce timeouts (AUDIT-2.3), inject
  /// correlation IDs (AUDIT-2.8), retry transient failures with exponential
  /// backoff (AUDIT-2.2), and guard with circuit breaker (AUDIT-2.4).
  static Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 3,
    Map<String, String>? queryParameters,
  }) async {
    final cb = _breakerFor(path);
    return cb.call(() => _executeWithRetry(
        method, path, headers, body, timeout, maxRetries,
        queryParameters: queryParameters));
  }

  /// The inner retry loop — separated so [CircuitBreaker] can wrap it.
  static Future<http.Response> _executeWithRetry(
    String method,
    String path,
    Map<String, String>? headers,
    Object? body,
    Duration timeout,
    int maxRetries, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = await _buildUri(path, queryParameters: queryParameters);
    const baseDelay = Duration(seconds: 1);

    http.Response? lastResponse;
    Object? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      final reqId = _generateRequestId();
      final mergedHeaders = Map<String, String>.from(headers ?? {});
      mergedHeaders['X-Request-ID'] = reqId;
      if (attempt > 0) {
        mergedHeaders['X-Retry-Attempt'] = attempt.toString();
      }

      Log.d(
          '[API] $method $path attempt=${attempt + 1}/$maxRetries req=$reqId');

      try {
        late http.Response response;
        if (method == 'GET') {
          response =
              await _client.get(uri, headers: mergedHeaders).timeout(timeout);
        } else if (method == 'POST') {
          response = await _client
              .post(uri, headers: mergedHeaders, body: body)
              .timeout(timeout);
        } else {
          throw Exception('Unsupported HTTP method: $method');
        }

        // Check for backend correlation ID echo
        final serverReqId = response.headers['x-request-id'];
        if (serverReqId != null && serverReqId != reqId) {
          Log.w(
              '[API] Correlation ID mismatch: client=$reqId, server=$serverReqId');
        }

        // 401: token expired or invalid — propagate immediately
        if (response.statusCode == 401) {
          Log.w('[API] $method $path got 401 — session expired.');
          throw UnauthorizedException('Session expired.');
        }

        // 5xx server errors are retryable
        if (response.statusCode >= 500 && attempt < maxRetries) {
          Log.w('[API] $method $path got ${response.statusCode}, retrying...');
          lastResponse = response;
          MetricsCollector().recordApiError();
          await Future.delayed(baseDelay * (1 << attempt));
          continue;
        }

        return response;
      } on TimeoutException catch (e) {
        lastError = e;
        MetricsCollector().recordApiError();
        if (attempt < maxRetries) {
          Log.w('[API] $method $path timed out, retrying...');
          await Future.delayed(baseDelay * (1 << attempt));
          continue;
        }
      } catch (e) {
        lastError = e;
        MetricsCollector().recordApiError();
        if (attempt < maxRetries && _isTransient(e)) {
          Log.w('[API] $method $path failed ($e), retrying...');
          await Future.delayed(baseDelay * (1 << attempt));
          continue;
        }
        Log.e('[API] $method $path non-retryable error: $e');
        rethrow;
      }
    }

    MetricsCollector().recordApiError();
    if (lastResponse != null) {
      throw ApiException(
          'Server error (${lastResponse.statusCode})', lastResponse.statusCode);
    }
    Log.e('[API] $method $path exhausted retries: $lastError');
    throw lastError ?? Exception('Request failed after $maxRetries retries');
  }

  /// Whether [error] is transient and worth retrying.
  static bool _isTransient(Object error) {
    return error is SocketException ||
        error is http.ClientException ||
        error is TlsException ||
        error is HandshakeException ||
        (error is Exception && error.toString().contains('Connection refused'));
  }

  // ─── Authentication ───────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    final deviceId = await HardwareFingerprintService.getDeviceId();
    if (deviceId.isNotEmpty && deviceId != 'null') {
      headers['X-Device-ID'] = deviceId;
    }

    // Board endpoints validate Firebase ID tokens directly via
    // firebase_admin.auth.verify_id_token() — no backend JWT needed.
    try {
      final token = await TokenManager().getValidToken();
      headers['Authorization'] = 'Bearer $token';
    } catch (e) {
      Log.w('[ApiService] Cannot attach auth header: $e');
      // Request proceeds without a token — the server will return 401,
      // which is an honest and debuggable response.
    }

    return headers;
  }

  // ─── Time & Context ───────────────────────────────────────────────────────

  static Future<int> syncTime() async {
    final clientSent = DateTime.now().millisecondsSinceEpoch;
    final response = await _request('GET', 'api/v1/board/time',
        headers: await _authHeaders());
    if (response.statusCode != 200) throw _apiError('Time sync', response);

    final data = jsonDecode(response.body);
    final dynamic payload = data['data'] ?? data;
    final serverTs = payload['server_timestamp_ms'] is int
        ? payload['server_timestamp_ms']
        : DateTime.now().millisecondsSinceEpoch;

    final clientReceived = DateTime.now().millisecondsSinceEpoch;
    final rtt = clientReceived - clientSent;
    final skew = serverTs - (clientReceived - (rtt ~/ 2));
    TimeSyncService.setSkew(skew);

    return serverTs;
  }

  // ─── Session Operations ───────────────────────────────────────────────────

  static Future<Map<String, dynamic>> initiateSession(String otp) async {
    final response = await _request(
      'POST',
      'api/v1/board/session/initiate',
      headers: await _authHeaders(),
      body: jsonEncode({'otp': otp}),
    );

    if (response.statusCode != 200) {
      throw _apiError('Session initiation', response);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> syncVault({
    required String sessionId,
    required List<Map<String, dynamic>> queuedScans,
  }) async {
    final response = await _request(
      'POST',
      'api/v1/board/sync/vault',
      headers: await _authHeaders(),
      body: jsonEncode({
        'session_id': sessionId,
        'queued_scans': queuedScans,
      }),
    );

    if (response.statusCode != 200) throw _apiError('Vault sync', response);
  }

  static Future<void> terminateSession(String sessionId) async {
    final response = await _request(
      'POST',
      'api/v1/board/session/terminate',
      headers: await _authHeaders(),
      body: jsonEncode({'session_id': sessionId}),
    );

    if (response.statusCode != 200) {
      throw _apiError('Session termination', response);
    }
  }

  // ─── Heartbeat (v2.0 — SmartBoard Integration Contract) ──────────────────
  //
  // Called every 5 minutes by HeartbeatService. Returns the authoritative
  // session context from the server. This is the board's safety net — if
  // WebSocket disconnects, the heartbeat tells you exactly what session
  // is active.

  static Future<Map<String, dynamic>> sendHeartbeatV2({
    required String smartBoardId,
    required String screenState,
    required int uptimeSeconds,
    required String appVersion,
  }) async {
    final headers = await _authHeaders();
    final timestamp = TimeSyncService.timeNow.toUtc().toIso8601String();

    final response = await _request(
      'POST',
      'api/v1/board/heartbeat',
      headers: headers,
      body: jsonEncode({
        'boardId': smartBoardId,
        'screenState': screenState,
        'uptimeSeconds': uptimeSeconds,
        'appVersion': appVersion,
        'timestamp': timestamp,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    Log.w('[Heartbeat] API returned ${response.statusCode}: ${response.body}');
    return {'status': 'error', 'session': null};
  }

  // ─── WebSocket Ticket (v2.0) ─────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getWebSocketTicket() async {
    final headers = await _authHeaders();
    try {
      final response = await _request(
        'POST',
        'api/v1/websocket/ticket',
        headers: headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      Log.w('[Ticket] Failed: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      Log.e('[Ticket] Error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> getPreFlight(String slotId,
      {int retryCount = 1}) async {
    final response = await _request(
      'GET',
      'api/v1/board/preflight',
      queryParameters: {'slot_id': slotId},
      headers: {
        ...await _authHeaders(),
        'X-Retry-Attempt': retryCount.toString(),
      },
    );
    if (response.statusCode != 200) {
      throw _apiError('Pre-flight Handshake', response);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> syncReadyCheck() async {
    final response = await _request(
      'GET',
      'api/v1/board/ready',
      headers: await _authHeaders(),
    );
    if (response.statusCode != 200) throw _apiError('Ready check', response);
  }

  static Future<bool> boardReady() async {
    try {
      final response = await _request(
        'GET',
        'api/v1/board/ready',
        headers: await _authHeaders(),
        maxRetries: 1,
      );
      if (response.statusCode == 403) {
        Log.w(
            '[ApiService] Board unregistered or forbidden — recovery poll detected 403.');
      }
      return response.statusCode == 200;
    } catch (e) {
      Log.d('[ApiService] Board ready check failed: $e');
      return false;
    }
  }

  static Future<void> sendHardwareTelemetry(Map<String, dynamic> data) async {
    final response = await _request(
      'POST',
      'api/v1/board/telemetry', // Aligned with doc and TelemetryService
      headers: await _authHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      Log.w('⚠️ [ApiService] Telemetry push failed: ${response.body}');
    }
  }

  // ─── Security & Registration (AUDIT-R1/R2) ──────────────────────────────────

  static Future<bool> verifyAdminPin(String pin) async {
    try {
      final response = await _request(
        'POST',
        'api/v1/auth/verify-admin-pin',
        headers: await _authHeaders(),
        body: jsonEncode({'pin': pin}),
      );
      return response.statusCode == 200;
    } catch (e) {
      Log.e('[API] Admin PIN verification failed: $e');
      return false;
    }
  }

  static Future<void> deregisterBoard() async {
    final response = await _request(
      'POST',
      'api/v1/board/deregister',
      headers: await _authHeaders(),
    );
    if (response.statusCode != 200 && response.statusCode != 401) {
      throw _apiError('Deregistration', response);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static Exception _apiError(String operation, http.Response response) {
    Log.e('$operation failed (${response.statusCode}): ${response.body}');

    String? serverMessage;
    try {
      final data = jsonDecode(response.body);
      serverMessage = data['detail']?.toString() ??
          data['message']?.toString() ??
          data['error']?.toString();
    } catch (e) {
      Log.w('[ApiService] Could not parse error response body: $e');
    }

    final userMessage =
        serverMessage ?? _userFriendlyMessage(response.statusCode);

    if (response.statusCode == 404) {
      return UnregisteredException(userMessage);
    }
    if (response.statusCode == 401) {
      return UnauthorizedException(userMessage);
    }

    return ApiException(userMessage, response.statusCode);
  }

  static String _userFriendlyMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Invalid request. Please check your input.';
      case 401:
        return 'Session expired. Please restart the application.';
      case 403:
        return 'Access denied. Please check your permissions.';
      case 404:
        return 'Resource not found. Please try again.';
      case 409:
        return 'Conflict — this operation was already completed.';
      case 422:
        return 'Invalid format. Please check your input and try again.';
      case 429:
        return 'Too many attempts. Please wait and try again.';
      case >= 500 && <= 599:
        return 'Server error. Please try again later.';
      default:
        return 'Network error ($statusCode). Please try again.';
    }
  }
}
