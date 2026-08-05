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
import '../core/config/api_schema.dart';

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
        } else if (method == 'PATCH') {
          response = await _client
              .patch(uri, headers: mergedHeaders, body: body)
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

        // 401: token expired or invalid — try re-auth once, then propagate
        if (response.statusCode == 401 && attempt == 0) {
          Log.w('[API] $method $path got 401 — attempting re-auth');
          final reAuthed = await _handleAuthFailure();
          if (reAuthed) {
            // Re-fetch auth headers with the fresh token so the retry
            // does not reuse the stale Authorization header.
            final freshHeaders = await _authHeaders();
            headers = freshHeaders;
            continue;
          }
          throw UnauthorizedException('Session expired. Please login again.');
        }

        if (response.statusCode == 401) {
          throw UnauthorizedException('Session expired. Please login again.');
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

    // Get auth token — throws if auth is broken (never silently fails).
    final token = await TokenManager().getValidToken();
    headers['Authorization'] = 'Bearer $token';

    return headers;
  }

  /// Attempt to re-authenticate after a 401 response.
  /// Returns true if re-auth succeeded and caller should retry.
  static Future<bool> _handleAuthFailure() async {
    Log.w('[ApiService] 401 received — attempting re-auth');
    TokenManager().invalidateCache();
    try {
      await TokenManager().getValidToken(forceRefresh: true);
      return true;
    } catch (e) {
      Log.e('[ApiService] Re-auth failed: $e');
      // Auth is broken — TokenManager already set state to unauthenticated
      return false;
    }
  }

  // ─── Time & Context ───────────────────────────────────────────────────────

  static Future<int> syncTime() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final response = await _request(
      'POST',
      'api/v1/board/time',
      headers: await _authHeaders(),
      body: jsonEncode({'client_timestamp_ms': t0}),
    );
    if (response.statusCode != 200) throw _apiError('Time sync', response);

    final data = jsonDecode(response.body);
    final t3 = DateTime.now().millisecondsSinceEpoch;

    // NTP-style compensation using server_received_at_ms
    final serverReceivedMs = data['server_received_at_ms'] as int;
    final sentMs = data['server_timestamp_ms'] as int;

    final rtt = t3 - t0;
    final offset = serverReceivedMs - (t0 + rtt ~/ 2);
    TimeSyncService.setSkew(offset);

    return sentMs;
  }

  // ─── Session Operations ───────────────────────────────────────────────────

  static Future<Map<String, dynamic>> initiateSession(String otp) async {
    final response = await _request(
      'POST',
      'api/v1/board/session/initiate',
      headers: await _authHeaders(),
      body: jsonEncode({'otp': otp}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    // Session-initiation errors are session-level, NOT device-registration
    // errors.  Do NOT route through _apiError (which maps 404 →
    // UnregisteredException) — that would wipe local registration and force
    // re-registration for a transient session issue.
    String? serverMessage;
    try {
      final data = jsonDecode(response.body);
      serverMessage = data['message']?.toString() ??
          data['error']?.toString() ??
          data['error_code']?.toString();
    } catch (_) {}

    final userMessage =
        serverMessage ?? _userFriendlyMessage(response.statusCode);
    Log.e('Session initiation failed (${response.statusCode}): $userMessage');
    throw ApiException(userMessage, response.statusCode);
  }

  // ─── Recovery & Boot (Session Orchestration) ────────────────────────────

  static Future<Map<String, dynamic>> getCurrentState() async {
    final response = await _request(
      'GET',
      'api/v1/session/current-state',
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    Log.w('[ApiService] current-state returned ${response.statusCode}');
    return {};
  }

  static Future<Map<String, dynamic>> boardBoot({
    required String boardId,
    required String hardwareId,
    required String appVersion,
  }) async {
    final response = await _request(
      'POST',
      'smartboard/boot',
      headers: await _authHeaders(),
      body: jsonEncode({
        'board_id': boardId,
        'hardware_id': hardwareId,
        'app_version': appVersion,
        'timestamp': TimeSyncService.timeNow.toUtc().toIso8601String(),
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    Log.w('[ApiService] Boot returned ${response.statusCode}');
    return {};
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

  static Future<void> submitAttendance({
    required String sessionId,
    required List<String> presentEmails,
    required List<String> absentEmails,
  }) async {
    final response = await _request(
      'POST',
      'api/v1/board/session/attendance/submit',
      headers: await _authHeaders(),
      body: jsonEncode({
        'session_id': sessionId,
        'present_emails': presentEmails,
        'absent_emails': absentEmails,
      }),
    );
    if (response.statusCode != 200) throw _apiError('Attendance submit', response);
  }

  /// REST-based individual tap — primary mechanism for marking attendance.
  /// Returns true if record was created, false if already exists (idempotent).
  static Future<bool> tapAttendance({
    required String sessionId,
    required String studentId,
    required String status,
  }) async {
    final response = await _request(
      'POST',
      'api/v1/board/session/attendance/tap',
      headers: await _authHeaders(),
      body: jsonEncode({
        'session_id': sessionId,
        'student_id': studentId,
        'status': status,
      }),
    );
    if (response.statusCode != 200) throw _apiError('Attendance tap', response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['record_id'] != null; // true = new record, false = already existed
  }

  /// Sync queued taps when connectivity returns (offline recovery).
  static Future<Map<String, dynamic>> offlineSync({
    required String sessionId,
    required List<Map<String, dynamic>> entries,
  }) async {
    final response = await _request(
      'POST',
      'api/v1/board/session/attendance/offline-sync',
      headers: await _authHeaders(),
      body: jsonEncode({
        'session_id': sessionId,
        'entries': entries,
      }),
    );
    if (response.statusCode != 200) throw _apiError('Offline sync', response);
    return jsonDecode(response.body) as Map<String, dynamic>;
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

  /// Fetch the board config (feature flags + update manifest) without a full heartbeat.
  /// Used when WS is connected and HTTP heartbeats are skipped.
  static Future<Map<String, dynamic>?> getBoardConfig() async {
    try {
      final response = await _request(
        'GET',
        'api/v1/board/config',
        headers: await _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      Log.d('[ApiService] getBoardConfig failed (non-critical): $e');
    }
    return null;
  }

  // ─── WebSocket Ticket (v2.0) ─────────────────────────────────────────────

  /// Check if there is an active attendance session for this board.
  /// Called right after WS receives `board_connected` (§4).
  static Future<Map<String, dynamic>> getActiveSession() async {
    try {
      final response = await _request(
        'GET',
        'api/v1/board/active-session',
        headers: await _authHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      Log.w('[ApiService] getActiveSession failed: $e');
    }
    return {'active': false, 'session_id': null, 'status': null};
  }

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

  // ─── Timetable ───────────────────────────────────────────────────────────

  // ─── Students ──────────────────────────────────────────────────────────────

  /// Fetch students by section ID.
  static Future<List<Map<String, dynamic>>> getStudentsBySection(
      String sectionId) async {
    final response = await _request(
      'GET',
      'api/v1/students',
      headers: await _authHeaders(),
      queryParameters: {'section_id': sectionId, 'status': ApiSchema.statusActive},
    );

    if (response.statusCode != 200) {
      throw _apiError('Students fetch', response);
    }

    final decoded = jsonDecode(response.body);
    final raw = decoded is List
        ? decoded
        : (decoded[ApiSchema.responseData] as List? ?? []);
    return raw.cast<Map<String, dynamic>>();
  }

  /// Fetch students by class ID.
  static Future<List<Map<String, dynamic>>> getStudentsByClass(
      String classId) async {
    final response = await _request(
      'GET',
      'api/v1/students',
      headers: await _authHeaders(),
      queryParameters: {'class_id': classId, 'status': ApiSchema.statusActive},
    );

    if (response.statusCode != 200) {
      throw _apiError('Students fetch', response);
    }

    final decoded = jsonDecode(response.body);
    final raw = decoded is List
        ? decoded
        : (decoded[ApiSchema.responseData] as List? ?? []);
    return raw.cast<Map<String, dynamic>>();
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

  // ─── Hydration ──────────────────────────────────────────────────────────

  /// Fetch full hydration payload from the server.
  static Future<Map<String, dynamic>> getHydrationPayload() async {
    final response = await _request(
      'GET',
      'api/v1/board/hydrate',
      headers: await _authHeaders(),
      maxRetries: 2,
    );
    if (response.statusCode != 200) throw _apiError('Hydration', response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Fetch session history for this board's room.
  ///
  /// Returns today's sessions, past sessions grouped by day, and calendar
  /// event markers for the last [daysBack] days.
  static Future<Map<String, dynamic>> getBoardSessionHistory({
    int daysBack = 7,
  }) async {
    final response = await _request(
      'GET',
      'api/v1/board/session-history?days_back=$daysBack',
      headers: await _authHeaders(),
      maxRetries: 2,
    );
    if (response.statusCode != 200) throw _apiError('SessionHistory', response);
    return jsonDecode(response.body) as Map<String, dynamic>;
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

  // ─── Resource / R2 Storage Operations ─────────────────────────────────────

  /// Fetch faculty's personal resources for the current session from R2.
  /// Returns a list of resource maps with R2 presigned URLs.
  static Future<List<Map<String, dynamic>>> getMyResources({
    required String sessionId,
    String? sectionId,
    String? courseName,
  }) async {
    final queryParams = <String, String>{
      'session_id': sessionId,
    };
    if (sectionId != null && sectionId.isNotEmpty) {
      queryParams['section_id'] = sectionId;
    }
    if (courseName != null && courseName.isNotEmpty) {
      queryParams['course'] = courseName;
    }

    final response = await _request(
      'GET',
      'api/v1/resources/my',
      headers: await _authHeaders(),
      queryParameters: queryParams,
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final raw = decoded is List
          ? decoded
          : (decoded[ApiSchema.responseData] as List? ?? []);
      return raw.cast<Map<String, dynamic>>();
    }
    if (response.statusCode == 404) {
      Log.d('[ApiService] No personal resources for session $sessionId');
      return [];
    }
    throw _apiError('My resources fetch', response);
  }

  /// Fetch college-wide / departmental resources from R2.
  static Future<List<Map<String, dynamic>>> getCollegeResources({
    String? courseName,
  }) async {
    final queryParams = <String, String>{};
    if (courseName != null && courseName.isNotEmpty) {
      queryParams['course'] = courseName;
    }

    final response = await _request(
      'GET',
      'api/v1/resources/college',
      headers: await _authHeaders(),
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final raw = decoded is List
          ? decoded
          : (decoded[ApiSchema.responseData] as List? ?? []);
      return raw.cast<Map<String, dynamic>>();
    }
    if (response.statusCode == 404) {
      Log.d('[ApiService] No college resources available');
      return [];
    }
    throw _apiError('College resources fetch', response);
  }

  // ─── Update Status Reporting ───────────────────────────────────────────
  //
  // Boards send update success/failure/rollback events to the server so the
  // admin dashboard can track per-board version status. These calls are
  // fire-and-forget (failures are logged but not retried).

  /// Report the outcome of a binary auto-update.
  ///
  /// Payload:
  /// ```json
  /// {
  ///   "current_version": "5.5.0",
  ///   "previous_version": "5.4.0",
  ///   "status": "completed" | "failed" | "rolled_back",
  ///   "stable_startups": 3,
  ///   "rollback_count": 0
  /// }
  /// ```
  static Future<void> reportUpdateStatus({
    required String currentVersion,
    required String previousVersion,
    required String status,
    required int stableStartups,
    required int rollbackCount,
  }) async {
    try {
      await _request(
        'POST',
        'api/v1/board/update-status',
        headers: await _authHeaders(),
        body: jsonEncode({
          'current_version': currentVersion,
          'previous_version': previousVersion,
          'status': status,
          'stable_startups': stableStartups,
          'rollback_count': rollbackCount,
          'timestamp': TimeSyncService.timeNow.toUtc().toIso8601String(),
        }),
        maxRetries: 1, // best-effort only
      );
    } catch (e) {
      Log.d('[ApiService] Update status report failed (non-critical): $e');
    }
  }

  // ─── Notification Operations ────────────────────────────────────────────

  /// Fetch all notifications for this board (REST fallback / history).
  /// Called on boot via [NotificationListenerService.forceSync] and on
  /// pull-to-refresh.  Returns an empty list on error or 404.
  static Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final response = await _request(
        'GET',
        'api/v1/board/notifications',
        headers: await _authHeaders(),
        maxRetries: 1,
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final raw = decoded is List
            ? decoded
            : (decoded[ApiSchema.responseData] as List? ?? []);
        return raw.cast<Map<String, dynamic>>();
      }
      Log.w('[ApiService] getNotifications returned ${response.statusCode}');
    } catch (e) {
      Log.d('[ApiService] getNotifications failed (non-critical): $e');
    }
    return [];
  }

  /// Acknowledge a notification (compliance/audit trail for emergency/P1).
  /// Called when the user taps dismiss on a full_screen or overlay notification.
  static Future<bool> acknowledgeNotification(String notificationId) async {
    try {
      final response = await _request(
        'PATCH',
        'api/v1/user/notifications/$notificationId/acknowledge',
        headers: await _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      Log.w('[ApiService] Acknowledge notification failed: $e');
      return false;
    }
  }

  /// Mark a P3/default notification as read.
  static Future<bool> markNotificationRead(String notificationId) async {
    try {
      final response = await _request(
        'PATCH',
        'api/v1/user/notifications/$notificationId/read',
        headers: await _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      Log.w('[ApiService] Mark notification read failed: $e');
      return false;
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
