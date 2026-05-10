import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/utils/logger.dart';
import '../core/platform/hardware_fingerprint_service.dart';
import '../core/security/ssl_pinning_service.dart';
import '../core/circuit_breaker.dart';
import 'time_sync_service.dart';
import '../core/security/secure_storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  static const String _defaultBaseUrl =
      'https://api-dev.balaseetharamanjaneyulu.com';

  // ─── Circuit Breakers (AUDIT-2.4) ─────────────────────────────────────────
  //
  // Per-endpoint circuit breakers to prevent cascading failures. Keyed by the
  // URL path — shared across code paths that call the same endpoint.
  static final Map<String, CircuitBreaker> _breakers = {};
  static const int _cbFailureThreshold = 5;
  static const Duration _cbCooldown = Duration(seconds: 60);

  static CircuitBreaker _breakerFor(String path) {
    return _breakers.putIfAbsent(path, () => CircuitBreaker(
      name: path,
      failureThreshold: _cbFailureThreshold,
      cooldown: _cbCooldown,
    ));
  }

  // ─── URL Resolution ───────────────────────────────────────────────────────

  static Future<String> _resolveBaseUrl() async {
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;

    return _defaultBaseUrl;
  }

  /// Build a URI from a path segment, normalizing double slashes.
  static Future<Uri> _buildUri(String path) async {
    final base = await _resolveBaseUrl();
    final baseUri = Uri.parse(base);
    final cleanPath = '/${path.replaceAll(RegExp(r'/+'), '/')}'
        .replaceFirst(RegExp(r'^//+'), '/');
    return baseUri.replace(path: cleanPath);
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
  }) async {
    final cb = _breakerFor(path);
    return cb.call(() => _executeWithRetry(
        method, path, headers, body, timeout, maxRetries));
  }

  /// The inner retry loop — separated so [CircuitBreaker] can wrap it.
  static Future<http.Response> _executeWithRetry(
    String method,
    String path,
    Map<String, String>? headers,
    Object? body,
    Duration timeout,
    int maxRetries,
  ) async {
    final uri = await _buildUri(path);
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

      Log.d('[API] $method $path attempt=${attempt + 1}/$maxRetries req=$reqId');

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

        // 5xx server errors are retryable
        if (response.statusCode >= 500 && attempt < maxRetries) {
          Log.w('[API] $method $path got ${response.statusCode}, retrying...');
          lastResponse = response;
          await Future.delayed(baseDelay * (1 << attempt));
          continue;
        }

        return response;
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt < maxRetries) {
          Log.w('[API] $method $path timed out, retrying...');
          await Future.delayed(baseDelay * (1 << attempt));
          continue;
        }
      } catch (e) {
        lastError = e;
        if (attempt < maxRetries && _isTransient(e)) {
          Log.w('[API] $method $path failed ($e), retrying...');
          await Future.delayed(baseDelay * (1 << attempt));
          continue;
        }
        Log.e('[API] $method $path non-retryable error: $e');
        rethrow;
      }
    }

    if (lastResponse != null) {
      throw ApiException(
          'Server error (${lastResponse!.statusCode})', lastResponse!.statusCode);
    }
    Log.e('[API] $method $path exhausted retries: $lastError');
    throw lastError ?? Exception('Request failed after $maxRetries retries');
  }

  /// Whether [error] is transient and worth retrying.
  static bool _isTransient(Object error) {
    return error is SocketException ||
        error is http.ClientException ||
        (error is Exception && error.toString().contains('Connection refused'));
  }

  // ─── Authentication ───────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    final deviceId = await HardwareFingerprintService.getDeviceId();
    if (deviceId.isNotEmpty && deviceId != 'null') {
      headers['X-Device-ID'] = deviceId;
    }

    // Try Firebase current user first — valid after signInWithCustomToken()
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final idToken = await firebaseUser.getIdToken();
        if (idToken != null && idToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $idToken';
          return headers;
        }
      }
    } catch (_) {}

    // Fall through to stored access token
    String? token = await SecureStorageService.getValidAccessToken();
    token ??= await _refreshToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
      return headers;
    }

    final apiKey = await SecureStorageService.getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    return headers;
  }

  static Future<String?> _refreshToken() async {
    final refreshToken = await SecureStorageService.getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await _request(
        'POST',
        'api/v1/board/auth/refresh',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newToken = data['access_token']?.toString();
        if (newToken != null) {
          final expiresAt = data['expires_in'] is int
              ? DateTime.now().millisecondsSinceEpoch +
                  (data['expires_in'] as int) * 1000
              : DateTime.now().millisecondsSinceEpoch + 900000;
          await SecureStorageService.storeAccessToken(newToken, expiresAt);
          Log.i('Access token refreshed');
          return newToken;
        }
      }
    } catch (e) {
      Log.e('Token refresh failed: $e');
    }
    return null;
  }

  // ─── Registration Flow ────────────────────────────────────────────────────

  static Future<void> requestRegistrationOtp(
      {required String smartBoardId}) async {
    final response = await _request(
      'POST',
      'api/v1/board/register/request-otp',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'classroom_id': smartBoardId}),
    );

    if (response.statusCode != 200) {
      throw _apiError('OTP request', response);
    }
  }

  static Future<Map<String, dynamic>> verifyRegistrationOtp({
    required String smartBoardId,
    required String otp,
    String? deviceName,
  }) async {
    final hardwareId = await HardwareFingerprintService.getDeviceId();
    final response = await _request(
      'POST',
      'api/v1/board/register',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'classroom_id': smartBoardId,
        'otp': otp,
        'hardware_fingerprint': hardwareId,
        'device_name': deviceName ?? 'SmartBoard $smartBoardId',
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw _apiError('Registration verification', response);
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

  static Future<Map<String, dynamic>> syncContext() async {
    final response = await _request('GET', 'api/v1/board/sync-context',
        headers: await _authHeaders());

    if (response.statusCode != 200) throw _apiError('Context sync', response);
    return jsonDecode(response.body) as Map<String, dynamic>;
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

  static Future<void> recordLiveAttendance({
    required String studentId,
    required String sessionId,
    required String smartBoardId,
    required String entryType,
  }) async {
    final response = await _request(
      'POST',
      'api/v1/board/session/attendance/record-live',
      headers: await _authHeaders(),
      body: jsonEncode({
        'student_id': studentId,
        'session_id': sessionId,
        'room_id': smartBoardId,
        'entry_type': entryType,
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    if (response.statusCode != 200) {
      throw _apiError('Live attendance', response);
    }
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

  // ─── Heartbeat (AUDIT-1.3) ─────────────────────────────────────────────────
  //
  // Called every 60s by HeartbeatService. Writes to board_heartbeats/<device_id>
  // in Firestore so IT can monitor board health.

  static Future<void> sendHeartbeat({
    required String smartBoardId,
    required String hardwareId,
    required String screenState,
    required int uptimeSeconds,
    required String appVersion,
  }) async {
    final headers = await _authHeaders();
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final response = await _request(
      'POST',
      'api/v1/device/heartbeat',
      headers: headers,
      body: jsonEncode({
        'smart_board_id': smartBoardId,
        'hardware_id': hardwareId,
        'screen_state': screenState,
        'uptime_seconds': uptimeSeconds,
        'app_version': appVersion,
        'system_metrics': {
          'memory_usage_mb': 0,
          'cpu_load_percent': 0.0,
          'network_latency_ms': 0,
        },
        'timestamp': timestamp,
      }),
    );

    if (response.statusCode != 200) {
      Log.w(
          '[Heartbeat] API returned ${response.statusCode}: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getPreFlight(String slotId,
      {int retryCount = 1}) async {
    final response = await _request(
      'GET',
      'api/v1/board/preflight?slot_id=$slotId',
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
    } catch (_) {}

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
